/// Server core.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module server;

import std.concurrency;
import std.conv;
import std.string;
import core.thread;
import adapter.base : Adapter;
import adapter.types;
import debugger;
import ddlogger;

// TODO: Accept multi-session
//
//       This could be a request type, or server simply launching new ones with
//       matching sequence IDs (as DAP goes).

// NOTE: Structure
//
//       The server can ultimately handle one adapter protocol, and if the
//       adapter allows it, the server can handle multiple debugger sessions,
//       often called "multi-session" servers, at the request of the adapter.
//
//       In general, the server understands close requests, but debuggers do not
//       (their UI do, though). Debuggers only understand detach and terminate
//       requests.

// NOTE: Threading
//
//       The main thread handles the adapter instance, and one or
//       more threads are spun on new debugger session requests.
//
//       Child thread handle their own debugger instance.
//       (TODO) Attach debugger ID to requests.

debug enum LogLevel DEFAULT_LOGLEVEL = LogLevel.trace;
else  enum LogLevel DEFAULT_LOGLEVEL = LogLevel.info;

/// Adapter type.
enum AdapterType { dap, mi, mi2, mi3, mi4 }

/// Server settings.
struct ServerSettings
{
    AdapterType adapterType;
    bool logStderr;
    string logFile;
    LogLevel logLevel = DEFAULT_LOGLEVEL;
}

private
{
    immutable string messageDebuggerActive   = "Debugger is already active";
    immutable string messageDebuggerUnactive = "Debugger is not active";
    
    struct Target
    {
        string   exec;
        string[] args;
    }
    __gshared Target target;
}

/// Get currently set target executable path.
/// Returns: Path string.
string targetExec()
{
    return target.exec;
}
/// Set target executable path.
/// Params: path = Path string.
void targetExec(string path)
{
    target.exec = path;
}

/// Set target arguments
/// Params: args = Arguments.
void targetExecArgs(string[] args)
{
    target.args = args;
}

/// Starts the initial server instance.
///
/// Adapters and main command-line interface can set target parameters.
void startServer(Adapter adapter) // Handles adapter
{
    assert(adapter, "No adapter set before calling function");
    
    IDebugger debugger = new AliceDebugger();
    
    // Get requests
    logTrace("Listening to %s via %s...", adapter.transportName(), adapter.name());
    Thread eventThread = new Thread({
        Levent:
            AdapterEvent event = debugger.wait();
            adapter.event(event);
            
            switch (event.type) with (AdapterEventType) {
            case exited: // Process exited
                return;
            default: goto Levent;
            }
        });
    AdapterRequest request = void;
Lrequest:
    try request = adapter.listen();
    catch (Exception ex)
    {
        logError(ex.msg);
        adapter.reply(AdapterError(ex.msg));
        goto Lrequest;
    }
    
    // Process request depending on type
    AdapterRequestType debuggerType;
    switch (request.type) {
    // Launch process with debugger
    case AdapterRequestType.launch:
        if (debuggerType)
        {
            adapter.reply(AdapterError(messageDebuggerActive));
            goto Lrequest;
        }
        
        with (request.launchOptions) try debugger.launch(path, null, null);
        catch (Exception ex)
        {
            adapter.reply(AdapterError(ex.msg));
            goto Lrequest;
        }
        
        adapter.reply(AdapterReply());
        debuggerType = AdapterRequestType.launch;
        break;
    // Attach debugger to process
    case AdapterRequestType.attach:
        if (debuggerType)
        {
            adapter.reply(AdapterError(messageDebuggerActive));
            goto Lrequest;
        }
        
        with (request.attachOptions) try debugger.attach(pid);
        catch (Exception ex)
        {
            adapter.reply(AdapterError(ex.msg));
            goto Lrequest;
        }
        
        adapter.reply(AdapterReply());
        debuggerType = AdapterRequestType.attach;
        break;
    // Continue
    case AdapterRequestType.continue_:
        adapter.reply(AdapterReply());
        eventThread.start();
        break;
    // Detach debugger from process
    case AdapterRequestType.detach:
        if (debuggerType == AdapterRequestType.unknown) // Nothing to detach from
        {
            adapter.reply(AdapterError(messageDebuggerUnactive));
            goto Lrequest;
        }
        
        try debugger.detach();
        catch (Exception ex)
        {
            adapter.reply(AdapterError(ex.msg));
            goto Lrequest;
        }
        
        debuggerType = AdapterRequestType.unknown;
        adapter.reply(AdapterReply());
        adapter.close();
        break;
    // Terminate process
    case AdapterRequestType.terminate:
        if (debuggerType == AdapterRequestType.unknown) // Nothing to terminate
        {
            adapter.reply(AdapterError(messageDebuggerUnactive));
            goto Lrequest;
        }
        
        try debugger.terminate();
        catch (Exception ex)
        {
            adapter.reply(AdapterError(ex.msg));
            goto Lrequest;
        }
        
        debuggerType = AdapterRequestType.unknown;
        adapter.reply(AdapterReply());
        adapter.close();
        break;
    // Either detaches or terminates process depending how the debugger is attached
    case AdapterRequestType.close:
        switch (debuggerType) {
        case AdapterRequestType.launch: // was launched
            logTrace("Close -> Terminate");
            goto case AdapterRequestType.terminate;
        case AdapterRequestType.attach: // was attached
            logTrace("Close -> Detach");
            goto case AdapterRequestType.detach;
        default: // no idea
            logWarn("Debugger was requested to close, but clueless of state");
        }
        break;
    default:
        string e = format("Request not implemented: %s", request.type);
        logError(e);
        adapter.reply(AdapterError(e));
    }
    
    goto Lrequest;
}
