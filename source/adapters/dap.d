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

class DAPAdapter : IAdapter
{
    enum
    {
        CONTINUE,
        QUIT,
    }
    
    this()
    {
        // Initialize DAP session, server services not required
        commands["initialize"] =
        (ref JSONValue j) {
            if (initialized)
            {
                error("Already initialized");
                return CONTINUE;
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
            
            JSONValue reply;
            
            JSONValue jcapabilities;
            foreach (ref Capability capability; server.capabilities)
            {
                if (capability.supported)
                    jcapabilities[capability.name] = true;
            }
            
            if (jcapabilities.isNull() == false)
                reply["body"] = jcapabilities;
            
            success(reply);
            return CONTINUE;
        };
        // Client is done configuring itself
        commands["configurationDone"] =
        (ref JSONValue j) {
            success();
            return CONTINUE;
        };
        // Launch process with debugger
        commands["launch"] =
        (ref JSONValue j) {
            if (initialized == false)
            {
                error("Uninitialized");
                return CONTINUE;
            }
            JSONValue jargs = required!JSONValue(j, "arguments");
            string path = required!string(jargs, "path");
            debugger.launch(path, null, null);
            return CONTINUE;
        };
        // Attach debugger to process
        commands["attach"] =
        (ref JSONValue j) {
            if (initialized == false)
            {
                error("Uninitialized");
                return CONTINUE;
            }
            JSONValue jargs = required!JSONValue(j, "arguments");
            int pid = required!int(jargs, "pid");
            debugger.attach(pid);
            return CONTINUE;
        };
        // Continue debugging session
        commands["continue"] =
        (ref JSONValue j) {
            if (initialized == false)
            {
                error("Uninitialized");
                return CONTINUE;
            }
            JSONValue jargs = required!JSONValue(j, "arguments");
            int tid = required!int(jargs, "threadId");
            debugger.continue_(tid);
            return CONTINUE;
        };
        // Disconnect from the debugger"
        commands["disconnect"] =
        (ref JSONValue j) {
            if (initialized == false)
            {
                error("Uninitialized");
                return CONTINUE;
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
            return QUIT;
        };
    }
    
    // Return short name of this adapter
    string name()
    {
        return "dap";
    }
    
    // Parse incoming data from client to a message
    void loop(IDebugger d, ITransport t)
    {
        transport = t;
        debugger  = d;
        
        // Print server capabilities
        string servercap;
        foreach (ref Capability capability; server.capabilities)
            if (capability.supported)
                servercap ~= text(" ", capability.prettyName());
        if (servercap == string.init)
            servercap = " none";
        logInfo("Server capabilities:%s", servercap);
        
        //
        // Request
        //
        
    Lrequest: // new request
        size_t content_length;
        
        try // reading headers
        {
            string[string] headers = readmsg();
            
            const(string)* ContentLength = "Content-Length" in headers;
            if (ContentLength == null)
                throw new Exception("HTTP missing field: 'Content-Length'");
            
            content_length = to!size_t(*ContentLength);
        }
        catch (Exception ex)
        {
            error(ex.msg);
            goto Lrequest;
        }
        
        string jsonbody = cast(string)transport.read(content_length);
        
        // Parse body as JSON
        JSONValue j = parseJSON(jsonbody);
        request_id = required!int(j, "seq");
        string mtype = j["type"].str;
        if (mtype != "request")
        {
            logWarn("Message is not type 'request', but '%s', ignoring", mtype);
        }
        
        // Extract command from its name
        const(JSONValue) *jcommand = "command" in j;
        if (jcommand == null)
        {
            error("'command' field missing");
            goto Lrequest;
        }
        
        // Get function from command name
        request_command = jcommand.str();
        logTrace("command: '%s'", request_command);
        int delegate(ref JSONValue) *func = request_command in commands;
        if (func == null)
        {
            error(text("Command not found: '", request_command, ","));
            goto Lrequest;
        }
        
        // Execute command
        try if ((*func)(j) == QUIT)
            return;
        catch (Exception ex)
            error(ex.msg);
        goto Lrequest;
    }
    
    void event(ref DebuggerEvent event)
    {
        logTrace("Event=%s", event.type);
        
        JSONValue j;
        j["seq"] = current_seq++;
        
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
            j["reason"] = eventStoppedReasonString(event.stopped.reason);
            //j["description"] = event.stopped.description;
            //j["threadId"] = event.stopped.threadId;
            break;
        case exited:
            j["exitCode"] = event.exited.code;
            break;
        default:
            throw new Exception(text("Event unimplemented: ", event.type));
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
        logTrace("line: %s", line);
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
        transport.send(cast(ubyte[])j.toString());
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
