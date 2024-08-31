/// Debuger Adapter Protocol adapter.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapters.dap;

import std.json;
import std.string : chompPrefix;
import std.conv : text;
import std.utf : validate;
import adapters.base;
import utils.json;
import ddlogger;

// References:
// - https://microsoft.github.io/debug-adapter-protocol/
// - gdb/python/lib/gdb/dap/
// - lldb/tools/lldb-vscode/
//   lldb-vscode is soon to be renamed lldb-dap

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
struct Capability
{
    //TODO: Add ctor with default value?
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

//TODO: Consider update seq atomically
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
            request.type = RequestType.initializaton;
            
            JSONValue jarguments = j["arguments"];
            
            //
            // Required fields
            //
            
            required(jarguments, "adapterID", client.adapterId);
            logInfo("Adapter ID: %s", client.adapterId);
            
            //
            // Optional fields
            //
            
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
            
            // Process client capabilities
            string clientcap;
            foreach (ref Capability capability; client.capabilities)
            {
                optional(jarguments, capability.name, capability.supported);
                if (capability.supported)
                {
                    clientcap ~= text(" ", capability.prettyName());
                }
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
            processCreation = request.type = RequestType.launch;
            JSONValue jargs;
            required(j, "arguments", jargs);
            required(jargs, "path", request.launchOptions.path);
            break;
        case "attach":
            processCreation = request.type = RequestType.attach;
            JSONValue jargs;
            required(j, "arguments", jargs);
            required(jargs, "pid", request.attachOptions.pid);
            break;
        case "disconnect":
            // If launched, close debuggee.
            // If attached, detach. Unless terminateDebuggee:true specified.
            request.type = RequestType.close;
            switch (processCreation) {
            case RequestType.attach:
                if (const(JSONValue) *pjdisconnect = "arguments" in j)
                {
                    bool kill; // Defaults to false
                    optional(pjdisconnect, "terminateDebuggee", kill);
                    with (CloseAction) request.closeOptions.action = kill ? terminate : detach;
                }
                else
                {
                    request.closeOptions.action = CloseAction.detach;
                }
                break;
            case RequestType.launch:
                request.closeOptions.action = CloseAction.terminate;
                break;
            default:
                request.closeOptions.action = CloseAction.nothing;
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
        case RequestType.unknown:
            break;
        case RequestType.initializaton:
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
        case RequestType.launch: // Empty reply bodies
            j["command"] = "launch";
            break;
        case RequestType.attach: // Empty reply bodies
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
        
        switch (event.type) with (EventType) {
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
    AdapterRequest request;
    /// Server sequencial ID.
    int current_seq = 1;
    RequestType processCreation;
    
    struct ClientCapabilities
    {
        string adapterId;
        string id;
        string name;
        /// ISO-639
        string locale;
        /// 'path' or 'uri'
        PathFormat pathFormat;
        
        //TODO: Issue with linesStartAt1/columnsStartAt1: They default to one
        Capability[] capabilities = [
            { "linesStartAt1" },
            { "columnsStartAt1" },
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
