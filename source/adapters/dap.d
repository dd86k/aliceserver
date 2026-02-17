/// Debuger Adapter Protocol implementation.
///
/// References:
/// - https://microsoft.github.io/debug-adapter-protocol/
/// - gdb/python/lib/gdb/dap/
/// - lldb/tools/lldb-vscode/
///   lldb-vscode is soon to be renamed lldb-dap
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapters.dap;

import std.json;
import std.string : chompPrefix;
import std.conv : text;
import std.utf : validate;
import std.conv;
import std.string;
import util.json;
import ddlogger;
import adapter;
import debugger;

version(unittest) import testing;

// NOTE: Single-session DAP flow
// * client spawns server and communiates via standard streams (stdio)
// * client and server start their sequence number (seq) at 1
// client> Initialize request with interface InitializeRequestArguments
// server> Replies server capabilities
// client> (Optional) Sets breakpoints if any, then requests configurationDone
// server> (Optional) Replies configurationDone
// client> Sends an attach or spawn request

private
string eventStoppedReasonString(DebuggerStoppedReason reason)
{
    final switch (reason) with (DebuggerStoppedReason) {
    case pause:
        return "pause";
    case entry:
        return "entry";
    case goto_:
        return "goto";
    case exception:
    case accessViolationException:
    case illegalInstructionException:
        return "exception";
    case step:
        return "step";
    case breakpoint:
        return "breakpoint";
    case functionBreakpoint:
        return "function breakpoint";
    case dataBreakpoint:
        return "data breakpoint";
    case instructionBreakpoint:
        return "instruction breakpoint";
    }
}

private
struct Capability
{
    string name;
    bool supported;

    string prettyName()
    {
        return name
            .chompPrefix("supports")
            .chompPrefix("support");
    }
}

private enum PathFormat { path, uri }

struct DAPRequest
{
    int seq;
    string command;
    string type;       // "request", "response", etc.
    JSONValue arguments;
    JSONValue raw;     // full parsed JSON
}

/// Parse raw DAP header text into key-value pairs.
/// Headers are lines separated by `\r\n` (or `\n`), each in the form `Name: Value`.
private
string[string] parseDAPHeaders(string rawHeaders)
{
    import std.string : lineSplitter, indexOf, strip;

    string[string] headers;
    foreach (line; rawHeaders.lineSplitter())
    {
        string stripped = strip(line);
        if (stripped.length == 0)
            continue;

        ptrdiff_t colonIdx = indexOf(stripped, ':');
        if (colonIdx < 0)
            throw new Exception("HTTP field delimiter not found");
        if (colonIdx + 1 >= stripped.length)
            throw new Exception("HTTP missing value");

        string field = strip(stripped[0 .. colonIdx]);
        string value = strip(stripped[colonIdx + 1 .. $]);
        headers[field] = value;
    }
    return headers;
}

unittest
{
    // Normal headers with Content-Length
    {
        auto h = parseDAPHeaders("Content-Length: 42\r\n");
        assert(h["Content-Length"] == "42");
    }
    // Multiple headers
    {
        auto h = parseDAPHeaders("Content-Length: 100\r\nContent-Type: utf-8\r\n");
        assert(h["Content-Length"] == "100");
        assert(h["Content-Type"] == "utf-8");
    }
    // Empty input
    {
        auto h = parseDAPHeaders("");
        assert(h.length == 0);
    }
    // Missing colon
    {
        bool threw = false;
        try parseDAPHeaders("BadHeader\r\n");
        catch (Exception) threw = true;
        assert(threw);
    }
    // No value after colon (colon at end of line)
    {
        bool threw = false;
        try parseDAPHeaders("Content-Length:\r\n");
        catch (Exception) threw = true;
        assert(threw);
    }
}

/// Parse a JSON body string into a DAPRequest.
DAPRequest parseDAPRequest(string jsonBody)
{
    DAPRequest req;
    req.raw = parseJSON(jsonBody);
    req.seq = required!int(req.raw, "seq");
    req.type = req.raw["type"].str;

    const(JSONValue)* jcommand = "command" in req.raw;
    if (jcommand !is null)
        req.command = jcommand.str;

    const(JSONValue)* jargs = "arguments" in req.raw;
    if (jargs !is null)
        req.arguments = *jargs;

    return req;
}

unittest
{
    // Valid request
    {
        auto req = parseDAPRequest(`{"seq":1,"type":"request","command":"initialize","arguments":{"adapterID":"test"}}`);
        assert(req.seq == 1);
        assert(req.type == "request");
        assert(req.command == "initialize");
        assert(req.arguments["adapterID"].str == "test");
    }
    // Missing command field
    {
        auto req = parseDAPRequest(`{"seq":2,"type":"request"}`);
        assert(req.seq == 2);
        assert(req.type == "request");
        assert(req.command is null);
    }
    // Non-request type
    {
        auto req = parseDAPRequest(`{"seq":3,"type":"response","command":"initialize"}`);
        assert(req.seq == 3);
        assert(req.type == "response");
        assert(req.command == "initialize");
    }
    // No arguments field
    {
        auto req = parseDAPRequest(`{"seq":4,"type":"request","command":"configurationDone"}`);
        assert(req.seq == 4);
        assert(req.command == "configurationDone");
        assert(req.arguments.type == JSONType.null_);
    }
}

class DAPAdapter : IAdapter
{
    this()
    {
        // Initialize DAP session, server services not required
        commands["initialize"] =
        (ref JSONValue j) {
            if (initialized)
            {
                error("Already initialized");
                return ADAPTER_CONTINUE;
            }

            JSONValue jarguments = j["arguments"];

            // Required fields
            required(jarguments, "adapterID", client.adapterId);
            logInfo("Adapter ID: %s", client.adapterId);

            // Optional fields
            optional(jarguments, "clientID", client.id);
            optional(jarguments, "clientName", client.name);
            with (client) if (id && name)
                logInfo("Client: %s (%s)", name, id);
            optional(jarguments, "locale", client.locale);

            string pathFormat;
            if (optional(jarguments, "pathFormat", pathFormat))
            {
                switch (pathFormat) {
                case "path": //TODO: Setup functions/enums
                    client.pathFormat = PathFormat.path;
                    break;
                case "uri":
                    client.pathFormat = PathFormat.uri;
                    break;
                default:
                    throw new Exception(text("Invalid pathFormat: ",
                        client.pathFormat));
                }
            }

            // Process client capabilities by attempting to query all
            // possible fields and populating them in our client features array
            string clientcap;
            foreach (ref Capability capability; client.capabilities)
            {
                optional(jarguments, capability.name, capability.supported);
                if (capability.supported)
                    clientcap ~= text(" ", capability.prettyName()); // names, informal
            }
            if (clientcap == string.init)
                clientcap = " none";
            logInfo("Client capabilities:%s", clientcap);

            initialized = true;

            JSONValue jcapabilities;
            foreach (ref Capability capability; server.capabilities)
            {
                if (capability.supported)
                    jcapabilities[capability.name] = true;
            }

            if (jcapabilities.isNull() == false)
                success(jcapabilities);
            else
                success();
            return ADAPTER_CONTINUE;
        };
        // Client is done configuring itself
        commands["configurationDone"] =
        (ref JSONValue j) {
            success();
            return ADAPTER_CONTINUE;
        };
        // Launch process with debugger
        commands["launch"] =
        (ref JSONValue j) {
            if (initialized == false)
            {
                error("Uninitialized");
                return ADAPTER_CONTINUE;
            }
            JSONValue jargs = required!JSONValue(j, "arguments");
            string path = required!string(jargs, "path");
            debugger.launch(path, null, null);
            return ADAPTER_CONTINUE;
        };
        // Attach debugger to process
        commands["attach"] =
        (ref JSONValue j) {
            if (initialized == false)
            {
                error("Uninitialized");
                return ADAPTER_CONTINUE;
            }
            JSONValue jargs = required!JSONValue(j, "arguments");
            int pid = required!int(jargs, "pid");
            debugger.attach(pid);
            return ADAPTER_CONTINUE;
        };
        // Continue debugging session
        commands["continue"] =
        (ref JSONValue j) {
            if (initialized == false)
            {
                error("Uninitialized");
                return ADAPTER_CONTINUE;
            }
            JSONValue jargs = required!JSONValue(j, "arguments");
            int tid = required!int(jargs, "threadId");
            debugger.continueThread(tid);
            return ADAPTER_CONTINUE;
        };
        // Disconnect from the debugger"
        commands["disconnect"] =
        (ref JSONValue j) {
            if (initialized == false)
            {
                error("Uninitialized");
                return ADAPTER_CONTINUE;
            }
            // "the debug adapter must terminate the debuggee if it was started
            // with the launch request. If an attach request was used to connect
            // to the debuggee, then the debug adapter must not terminate the debuggee.
            /+if (const(JSONValue) *jdisconnect = "arguments" in j)
            {
                // "Indicates whether the debuggee should be terminated when the
                // debugger is disconnected.
                // If unspecified, the debug adapter is free to do whatever it
                // thinks is best. The attribute is only honored by a debug
                // adapter if the corresponding capability `supportTerminateDebuggee` is true."
                bool terminate = optional!bool(jdisconnect, "terminateDebuggee");
                // "Indicates whether the debuggee should stay suspended when the
                // debugger is disconnected.
                // If unspecified, the debuggee should resume execution. The
                // attribute is only honored by a debug adapter if the corresponding
                // capability `supportSuspendDebuggee` is true."
                // TODO: bool suspendDebuggee (optional)
                // TODO: bool restart (optional)
            }+/
            success();
            return ADAPTER_QUIT;
        };
    }

    // Return short name of this adapter
    string name()
    {
        return "dap";
    }

    // Handle one incoming request from transport.
    int handleRequest(IDebugger d, ITransport t)
    {
        debugger  = d;
        transport = t;

        // Print server capabilities on first request
        if (!capsPrinted)
        {
            string servercap;
            foreach (ref Capability capability; server.capabilities)
                if (capability.supported)
                    servercap ~= text(" ", capability.prettyName());
            if (servercap == string.init)
                servercap = " none";
            logInfo("Server capabilities:%s", servercap);
            capsPrinted = true;
        }

        // Read headers
        size_t content_length;

        try
        {
            string[string] headers = readmsg();
            logTrace("headers: %s", headers);

            const(string)* ContentLength = "Content-Length" in headers;
            if (ContentLength == null)
                throw new Exception("HTTP missing field: 'Content-Length'");

            content_length = to!size_t(*ContentLength);
        }
        catch (Exception ex)
        {
            error(ex.msg);
            return ADAPTER_CONTINUE;
        }

        string jsonbody = cast(string)transport.read(content_length);

        // Parse body as DAP request
        DAPRequest dapReq;
        try
            dapReq = parseDAPRequest(jsonbody);
        catch (Exception ex)
        {
            error(ex.msg);
            return ADAPTER_CONTINUE;
        }

        request_id = dapReq.seq;
        if (dapReq.type != "request")
        {
            logWarn("Message is not type 'request', but '%s', ignoring command", dapReq.type);
            return ADAPTER_CONTINUE;
        }

        if (dapReq.command is null)
        {
            error("'command' field missing");
            return ADAPTER_CONTINUE;
        }

        // Get function from command name
        request_command = dapReq.command;
        logTrace("command: '%s'", request_command);
        JSONValue j = dapReq.raw;
        int delegate(ref JSONValue) *func = request_command in commands;
        if (func == null)
        {
            error(text("Command not found: '", request_command, "'"));
            return ADAPTER_CONTINUE;
        }

        // Execute command
        try return (*func)(j);
        catch (Exception ex)
        {
            error(ex.msg);
            return ADAPTER_CONTINUE;
        }
    }

    void sendEvent(DebuggerEvent event, ITransport t)
    {
        transport = t;

        logTrace("Event=%s", event.type);

        JSONValue j;
        j["seq"] = current_seq++;
        j["type"] = "event";

        switch (event.type) with (DebuggerEventType) {
        case output:
            j["event"] = "output";
            // console  : Client UI debug console, informative only
            // important: Important message from debugger
            // stdout   : Debuggee stdout message
            // stderr   : Debuggee stderr message
            // telemetry: Sent to a telemetry server instead of client
            j["body"] = [ // 'console' | 'important' | 'stdout' | 'stderr' | 'telemetry'
                "": ""
            ];
            break;
        case stopped:
            j["event"] = "stopped";
            JSONValue body_;
            body_["reason"] = eventStoppedReasonString(event.stopped.reason);
            //body_["description"] = event.stopped.description;
            //body_["threadId"] = event.stopped.threadId;
            j["body"] = body_;
            break;
        case exited:
            j["event"] = "exited";
            JSONValue body_;
            body_["exitCode"] = event.exited.code;
            j["body"] = body_;
            break;
        default:
            logWarn("Event unimplemented: %s", event.type);
            return;
        }
        reply(j);
    }

private:
    ///
    ITransport transport;
    ///
    IDebugger debugger;

    ///
    bool initialized;
    /// Whether server capabilities have been printed
    bool capsPrinted;
    /// Server sequencial ID.
    int current_seq = 1;
    /// Request ID
    int request_id = 1;
    /// Request command name
    string request_command;
    /// Implemented commands.
    int delegate(ref JSONValue)[string] commands;

    struct ClientCapabilities
    {
        string adapterId;
        string id;
        string name;
        /// ISO-639
        string locale;
        /// 'path' or 'uri'
        PathFormat pathFormat;

        Capability[] capabilities = [
            { "linesStartAt1", true },
            { "columnsStartAt1", true },
            { "supportsVariableType" },
            { "supportsVariablePaging" },
            { "supportsRunInTerminalRequest" },
            { "supportsMemoryReferences" },
            { "supportsProgressReporting" },
            { "supportsInvalidatedEvent" },
            { "supportsMemoryEvent" },
            { "supportsArgsCanBeInterpretedByShell" },
            { "supportsStartDebuggingRequest" },
        ];
    }
    ClientCapabilities client;

    // NOTE: Set to true when server supports
    struct ServerCapabilities
    {
        Capability[] capabilities = [
            { "supportsConfigurationDoneRequest" },
            { "supportsFunctionBreakpoints" },
            { "supportsConditionalBreakpoints" },
            { "supportsHitConditionalBreakpoints" },
            { "supportsEvaluateForHovers" },
            { "supportsStepBack" },
            { "supportsSetVariable" },
            { "supportsRestartFrame" },
            { "supportsGotoTargetsRequest" },
            { "supportsStepInTargetsRequest" },
            { "supportsCompletionsRequest" },
            { "supportsModulesRequest" },
            { "supportsExceptionOptions" },
            { "supportsValueFormattingOptions" },
            { "supportsExceptionInfoRequest" },
            { "supportTerminateDebuggee" },
            { "supportSuspendDebuggee" },
            { "supportsDelayedStackTraceLoading" },
            { "supportsLoadedSourcesRequest" },
            { "supportsLogPoints" },
            { "supportsTerminateThreadsRequest" },
            { "supportsSetExpression" },
            { "supportsTerminateRequest" },
            { "supportsDataBreakpoints" },
            { "supportsReadMemoryRequest" },
            { "supportsWriteMemoryRequest" },
            { "supportsDisassembleRequest" },
            { "supportsCancelRequest" },
            { "supportsBreakpointLocationsRequest" },
            { "supportsClipboardContext" },
            { "supportsSteppingGranularity" },
            { "supportsInstructionBreakpoints" },
            { "supportsExceptionFilterOptions" },
            { "supportsSingleThreadExecutionRequests" },
        ];
    }
    ServerCapabilities server;

    string[string] readmsg()
    {
        string[string] headers;

    Lentry:
        // Read one HTTP field
        string line = strip( cast(string)transport.readline() );
        if (line.length == 0)
            return headers;

        // Get field separator (':')
        ptrdiff_t fieldidx = indexOf(line, ':');
        if (fieldidx < 0)
            throw new Exception("HTTP field delimiter not found");
        if (fieldidx + 1 >= line.length)
            throw new Exception("HTTP missing value");

        // Check field name
        string field = strip( line[0 .. fieldidx] );
        string value = strip( line[fieldidx + 1 .. $] );
        headers[field] = value;

        goto Lentry;
    }

    void reply(ref JSONValue j)
    {
        string body_ = j.toString();
        string header = "Content-Length: " ~ to!string(body_.length) ~ "\r\n\r\n";
        transport.send(cast(ubyte[])(header ~ body_));
    }

    void success()
    {
        JSONValue j;
        j["seq"] = current_seq++;
        j["request_seq"] = request_id;
        j["command"] = request_command;
        j["type"] = "response";
        j["success"] = true;
        reply(j);
    }

    void success(ref JSONValue body_)
    {
        JSONValue j;
        j["seq"] = current_seq++;
        j["request_seq"] = request_id;
        j["command"] = request_command;
        j["type"] = "response";
        j["success"] = true;
        j["body"] = body_;
        reply(j);
    }

    void error(string message)
    {
        logError("Error=%s", message);

        JSONValue j;
        j["seq"] = current_seq++;
        j["request_seq"] = request_id;
        j["command"] = request_command;
        j["type"] = "response";
        j["success"] = false;
        j["body"] = [ "error": message ];
        reply(j);
    }
}

version(unittest)
{
    /// Feed a DAP JSON request through mock transport and call handleRequest.
    private int feedDAPRequest(DAPAdapter adapter, testing.MockTransport mt, testing.MockDebugger md, string jsonBody)
    {
        import std.conv : to;

        // Queue the Content-Length header line, then empty line (header terminator),
        // then the body bytes.
        mt.feedLine("Content-Length: " ~ to!string(jsonBody.length));
        mt.feedBytes(cast(ubyte[])jsonBody);
        return adapter.handleRequest(md, mt);
    }
}

unittest
{
    import testing;

    // Test: initialize request returns success with capabilities
    {
        auto adapter = new DAPAdapter();
        auto mt = new MockTransport();
        auto md = new MockDebugger();

        string req = `{"seq":1,"type":"request","command":"initialize","arguments":{"adapterID":"test-client"}}`;
        int result = feedDAPRequest(adapter, mt, md, req);
        assert(result == ADAPTER_CONTINUE);

        // Parse the response
        string data = mt.sentData();
        assert(data.length > 0);
        // Find JSON body after headers
        import std.string : indexOf;
        auto bodyStart = indexOf(data, "\r\n\r\n");
        assert(bodyStart >= 0);
        auto responseJson = parseJSON(data[bodyStart + 4 .. $]);
        assert(responseJson["success"].get!bool == true);
        assert(responseJson["command"].str == "initialize");
        assert(responseJson["type"].str == "response");
        assert(responseJson["request_seq"].get!int == 1);
    }

    // Test: launch before initialize returns error
    {
        auto adapter = new DAPAdapter();
        auto mt = new MockTransport();
        auto md = new MockDebugger();

        string req = `{"seq":1,"type":"request","command":"launch","arguments":{"path":"/bin/test"}}`;
        int result = feedDAPRequest(adapter, mt, md, req);
        assert(result == ADAPTER_CONTINUE);

        string data = mt.sentData();
        import std.string : indexOf;
        auto bodyStart = indexOf(data, "\r\n\r\n");
        assert(bodyStart >= 0);
        auto responseJson = parseJSON(data[bodyStart + 4 .. $]);
        assert(responseJson["success"].get!bool == false);
    }

    // Test: disconnect after initialize returns ADAPTER_QUIT
    {
        auto adapter = new DAPAdapter();
        auto mt = new MockTransport();
        auto md = new MockDebugger();

        // First initialize
        string initReq = `{"seq":1,"type":"request","command":"initialize","arguments":{"adapterID":"test"}}`;
        feedDAPRequest(adapter, mt, md, initReq);

        // Then disconnect
        auto mt2 = new MockTransport();
        string discReq = `{"seq":2,"type":"request","command":"disconnect","arguments":{}}`;
        int result = feedDAPRequest(adapter, mt2, md, discReq);
        assert(result == ADAPTER_QUIT);

        string data = mt2.sentData();
        import std.string : indexOf;
        auto bodyStart = indexOf(data, "\r\n\r\n");
        assert(bodyStart >= 0);
        auto responseJson = parseJSON(data[bodyStart + 4 .. $]);
        assert(responseJson["success"].get!bool == true);
        assert(responseJson["command"].str == "disconnect");
    }

    // Test: unknown command returns error
    {
        auto adapter = new DAPAdapter();
        auto mt = new MockTransport();
        auto md = new MockDebugger();

        string req = `{"seq":1,"type":"request","command":"nonexistent","arguments":{}}`;
        int result = feedDAPRequest(adapter, mt, md, req);
        assert(result == ADAPTER_CONTINUE);

        string data = mt.sentData();
        import std.string : indexOf;
        auto bodyStart = indexOf(data, "\r\n\r\n");
        assert(bodyStart >= 0);
        auto responseJson = parseJSON(data[bodyStart + 4 .. $]);
        assert(responseJson["success"].get!bool == false);
    }
}
