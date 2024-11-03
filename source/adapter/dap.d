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
module adapter.dap;

import std.json;
import std.string : chompPrefix;
import std.conv : text;
import std.utf : validate;
import adapter.base, adapter.types;
import util.json;
import ddlogger;

// NOTE: DAP notes
//       - Client only sends Requests.
//       - Server responses to requests with Reponses or Errors.
//       - Server can send Events at any time.
//       - DAP is encoded using an "HTTP-like" message with JSON as the body.

// NOTE: Single-session DAP flow
// * client spawns server and communiates via standard streams (stdio)
// * client and server start their sequence number (seq) at 1
// client> Initialize request with interface InitializeRequestArguments
// server> Replies server capabilities
// client> (Optional) Sets breakpoints if any, then requests configurationDone
// server> (Optional) Replies configurationDone
// client> Sends an attach or spawn request

// NOTE: Multi-session
//
//       It is possible to have a "newSession" request type from a DAP
//       "StartDebuggingRequest" request.
//       Then, server can call something like "addSession" once it supports
//       multi-sessions.

private
string eventStoppedReasonString(AdapterEventStoppedReason reason)
{
    final switch (reason) with (AdapterEventStoppedReason) {
    case step:
        return "step";
    case breakpoint:
        return "breakpoint";
    case exception:
        return "exception";
    case pause:
        return "pause";
    case entry:
        return "entry";
    case goto_:
        return "goto";
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

class DAPAdapter : Adapter
{
    this(ITransport t)
    {
        super(t);
        
        // Print server capabilities
        string servercap;
        foreach (ref Capability capability; server.capabilities)
            if (capability.supported)
                servercap ~= text(" ", capability.prettyName());
        if (servercap == string.init)
            servercap = " none";
        logInfo("Server capabilities:%s", servercap);
    }
    
    // Return short name of this adapter
    override
    string name()
    {
        return "dap";
    }
    
    // Parse incoming data from client to a message
    override
    AdapterRequest listen()
    {
    Lread:
        ubyte[] buffer = receive();
        
        request = AdapterRequest.init;
        
        // Parse JSON into a message
        JSONValue j = parseJSON(cast(immutable(char)[])buffer);
        request.id = cast(int)j["seq"].integer; // Must be 32-bit int
        string mtype = j["type"].str;
        if (mtype != "request")
        {
            logWarn("Message is not type 'request', but '%s', ignoring", mtype);
        }
        
        const(JSONValue) *pcommand = "command" in j;
        if (pcommand == null)
            throw new Exception("'command' field missing");
        
        scope mcommand = pcommand.str(); // Validated before Request.init
        
        logTrace("command: '%s'", mcommand);
        switch (mcommand) {
        // Initialize DAP session, server services not required
        case "initialize":
            request.type = AdapterRequestType.initializaton;
            
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
            
            reply(AdapterReply());
            goto Lread;
        // Client configuration done, server services not required
        case "configurationDone":
            JSONValue jconfigdone;
            jconfigdone["seq"] = current_seq++;
            jconfigdone["request_seq"] = request.id;
            jconfigdone["type"] = "response";
            jconfigdone["success"] = true;
            jconfigdone["command"] = "configurationDone";
            send(jconfigdone);
            goto Lread;
        case "launch":
            request.type = AdapterRequestType.launch;
            JSONValue jargs;
            required(j, "arguments", jargs);
            required(jargs, "path", request.launchOptions.path);
            request.launchOptions.run = true; // DAP wants to immediately continue
            break;
        case "attach":
            request.type = AdapterRequestType.attach;
            JSONValue jargs;
            required(j, "arguments", jargs);
            required(jargs, "pid", request.attachOptions.pid);
            request.attachOptions.run = true; // DAP wants to immediately continue
            break;
        case "continue":
            request.type = AdapterRequestType.continue_;
            JSONValue jargs;
            required(j, "arguments", jargs);
            required(jargs, "threadId", request.continueOptions.tid);
            break;
        case "disconnect":
            // "the debug adapter must terminate the debuggee if it was started
            // with the launch request. If an attach request was used to connect
            // to the debuggee, then the debug adapter must not terminate the debuggee."
            request.type = AdapterRequestType.close;
            if (const(JSONValue) *pjdisconnect = "arguments" in j)
            {
                // "Indicates whether the debuggee should be terminated when the
                // debugger is disconnected.
                // If unspecified, the debug adapter is free to do whatever it
                // thinks is best. The attribute is only honored by a debug
                // adapter if the corresponding capability `supportTerminateDebuggee` is true."
                optional(pjdisconnect, "terminateDebuggee", request.closeOptions.terminate);
                // "Indicates whether the debuggee should stay suspended when the
                // debugger is disconnected.
                // If unspecified, the debuggee should resume execution. The
                // attribute is only honored by a debug adapter if the corresponding
                // capability `supportSuspendDebuggee` is true."
                // TODO: bool suspendDebuggee (optional)
                // TODO: bool restart (optional)
            }
            break;
        default:
            throw new Exception("Invalid request command: "~mcommand);
        }
        
        return request;
    }
    
    override
    void reply(AdapterReply response)
    {
        logTrace("Response=%s", request.type);
        
        JSONValue j;
        j["seq"] = current_seq++;
        j["request_seq"] = request.id;
        j["type"] = "response";
        j["success"] = true;
        
        switch (request.type) {
        case AdapterRequestType.unknown:
            break;
        case AdapterRequestType.initializaton:
            j["command"] = "initialize";
            
            JSONValue jcapabilities;
            foreach (ref Capability capability; server.capabilities)
            {
                if (capability.supported)
                    jcapabilities[capability.name] = true;
            }
            
            if (jcapabilities.isNull() == false)
                j["body"] = jcapabilities;
            
            send(j);
            break;
        case AdapterRequestType.launch: // Empty reply bodies
            j["command"] = "launch";
            break;
        case AdapterRequestType.attach: // Empty reply bodies
            j["command"] = "attach";
            break;
        default:
            throw new Exception(text("Reply unimplemented: ", request.type));
        }
        
        send(j);
    }
    
    override
    void reply(AdapterError error)
    {
        logTrace("Error=%s", error.message);
        
        JSONValue j;
        j["seq"] = current_seq++;
        j["request_seq"] = request.id;
        j["type"] = "response";
        j["success"] = false;
        j["body"] = [ "error": error.message ];
        
        send(j);
    }
    
    override
    void event(AdapterEvent event)
    {
        logTrace("Event=%s", event.type);
        
        JSONValue j;
        j["seq"] = current_seq++;
        
        switch (event.type) with (AdapterEventType) {
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
            string reason = void;
            final switch (event.stopped.reason) with (AdapterEventStoppedReason) {
            case step:          reason =  "step"; break;
            case breakpoint:    reason =  "breakpoint"; break;
            case exception:     reason =  "exception"; break;
            case pause:         reason =  "pause"; break;
            case entry:         reason =  "entry"; break;
            case goto_:         reason =  "goto"; break;
            case functionBreakpoint:    reason =  "function breakpoint"; break;
            case dataBreakpoint:        reason =  "data breakpoint"; break;
            case instructionBreakpoint: reason =  "instruction breakpoint"; break;
            }
            j["reason"] = reason;
            j["description"] = event.stopped.description;
            //j["threadId"] = reason;
            break;
        case exited:
            j["exitCode"] = event.exited.code;
            break;
        default:
            throw new Exception(text("Event unimplemented: ", event.type));
        }
        
        send(j);
    }
    
    override
    void close()
    {
        // Send empty reply.
        // This is to reply to a close request.
        reply(AdapterReply());
    }
    
    private
    void send(ref JSONValue json)
    {
        super.send(json.toString());
    }
    
private:
    /// Current serving request.
    AdapterRequest request;
    // TODO: Consider updating seq atomically
    /// Server sequencial ID.
    int current_seq = 1;
    
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
}
