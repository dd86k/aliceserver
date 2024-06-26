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
import adapters;
import transports;
import logging;
import utils.formatting : encodeHTTP;
import utils.json;

// References:
// - https://microsoft.github.io/debug-adapter-protocol/
// - gdb/python/lib/gdb/dap/
// - lldb/tools/lldb-vscode/
//   lldb-vscode is soon to be renamed lldb-dap

// NOTE: Overview
//       - Client only sends Requests
//       - Server responses to those with Reponses or Errors
//       - Server can send Events at any time

// NOTE: Single-session DAP flow
// client spawns server and communiates via standard streams and starts seq to 1
// client and server: Start seq at 1
// client> Initialize request with interface InitializeRequestArguments
// server> Replies server capabilities
// client> (Optional) Sets breakpoints if any, then requests configurationDone
// server> (Optional) Replies configurationDone
// client> Sends an attach or spawn request

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

// To be honest, only the first two are used
private
enum ClientCapabilityIndex : size_t
{
    linesStartAt1,
    columnsStartAt1,
}

//TODO: Consider update seq atomically
class DAPAdapter : IAdapter
{
    ITransport transport;
    int current_seq = 1;
    int request_seq;
    RequestType processCreation;
    
    struct ClientCapabilities
    {
        string adapterId;
        string id;
        string name;
        /// ISO-639
        string locale;
        /// 'path' or 'uri'
        string pathFormat;
        
        //TODO: Issue with linesStartAt1/columnsStartAt1: They default to one
        Capability[11] capabilities = [
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
        Capability[34] capabilities = [
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
    
    this()
    {
        string servercap;
        foreach (ref Capability capability; server.capabilities)
        {
            if (capability.supported)
            {
                servercap ~= text(" ",
                    capability.prettyName());
            }
        }
        if (servercap == string.init)
            servercap = " none";
        logInfo("Server capabilities:%s", servercap);
    }
    
    void attach(ITransport t)
    {
        transport = t;
    }
    
    // Parse incoming data from client to a message
    AdapterRequest listen()
    {
LISTEN:
        ubyte[] buffer = transport.receive();
        
        // Cast as string and validate
        const(char)[] rawmsg = cast(const(char)[])buffer;
        logTrace("Reply: Got %d bytes", rawmsg.length);
        validate(rawmsg);
        
        // Parse JSON into a message
        JSONValue j = parseJSON(rawmsg);
        request_seq = cast(int)j["seq"].integer; // Must be 32-bit int
        string mtype = j["type"].str;
        if (mtype != "request")
        {
            logWarn("Message is not type 'request', but '%s', ignoring", mtype);
        }
        
        scope mcommand = j["command"].str; // Validated before Request.init
        
        AdapterRequest request;
        switch (mcommand) {
        case "initialize": // Not given to server
            request.type = RequestType.initializaton;
            
            JSONValue jarguments = j["arguments"];
            
            // Required
            required(jarguments, "adapterID", client.adapterId);
            logInfo("Adapter ID: %s", client.adapterId);
            
            // Optional
            optional(jarguments, "clientID", client.id);
            optional(jarguments, "clientName", client.name);
            
            with (client) if (id && name)
                logInfo("Client: %s (%s)", name, id);
            
            optional(jarguments, "locale", client.locale);
            optional(jarguments, "pathFormat", client.pathFormat);
            switch (client.pathFormat) {
            case string.init: break;
            case "path": break; //TODO: Setup functions/enums
            case "uri": break;
            default:
                throw new Exception(text("Invalid pathFormat: ",
                    client.pathFormat));
            }
            
            string clientcap;
            foreach (ref Capability capability; client.capabilities)
            {
                optional(jarguments, capability.name, capability.supported);
                if (capability.supported)
                {
                    clientcap ~= text(" ",
                        capability.prettyName());
                }
            }
            if (clientcap == string.init)
                clientcap = " none";
            logInfo("Client capabilities: %s", clientcap);
            
            AdapterReply res;
            res.type = RequestType.initializaton;
            reply(res);
            goto LISTEN;
        case "configurationDone":
            JSONValue jconfigdone;
            jconfigdone["seq"] = current_seq++;
            jconfigdone["request_seq"] = request_seq;
            jconfigdone["type"] = "response";
            jconfigdone["success"] = true;
            jconfigdone["command"] = "configurationDone";
            send(jconfigdone);
            goto LISTEN;
        case "launch":
            processCreation =
                request.type = RequestType.spawn;
            JSONValue jargs;
            required(j, "arguments", jargs);
            required(jargs, "path", request.launchOptions.path);
            break;
        case "attach":
            processCreation =
                request.type = RequestType.attach;
            JSONValue jargs;
            required(j, "arguments", jargs);
            required(jargs, "pid", request.attachOptions.pid);
            break;
        case "disconnect":
            // If launched, close debuggee.
            // If attached, detach. Unless terminateDebuggee:true specified.
            //
            // Server should only understand closing, so send appropriate
            // request type.
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
    
    void reply(AdapterReply response)
    {
        logTrace("Response=%s", response.type);
        
        JSONValue j;
        j["seq"] = current_seq++;
        j["request_seq"] = request_seq;
        j["type"] = "response";
        j["success"] = true;
        
        switch (response.type) {
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
            break;
        case RequestType.launch: // Empty reply bodies
            j["command"] = "launch";
            break;
        case RequestType.attach: // Empty reply bodies
            j["command"] = "attach";
            break;
        default:
            throw new Exception(text("Not implemented: ", response.type));
        }
        
        send(j);
    }
    
    void reply(AdapterError error)
    {
        logTrace("Error=%s", error.message);
        
        JSONValue j;
        
        j["seq"] = current_seq++;
        j["request_seq"] = request_seq; // todo: match seq
        j["type"] = "response";
        j["success"] = false;
        j["body"] = [
            "error": error.message
        ];
        
        send(j);
    }
    
    void event(AdapterEvent event)
    {
        logTrace("Event=%s", event.type);
        
        JSONValue j;
        j["seq"] = current_seq++;
        
        //TODO: Final switch
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
            assert(false, "Implement event type");
        }
        
        send(j);
    }
    
    void send(JSONValue json)
    {
        transport.send(cast(ubyte[])encodeHTTP(json.toString()));
    }
}
