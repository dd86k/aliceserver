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
import adapters;
import types;
import debuggers;
import transports;
import debugger.alicedbg;
import ddlogger;

// TODO: Accept multi-session
//
//       This could be a request type, or server simply launching new ones with
//       matching sequence IDs (as DAP goes).

// TODO: Debugger server request queue
//
//       Currently, there are no ways for manage multiple requests, for example,
//       if the adapter bursts more than one request for fine-grained control.
//       This would be nice to have before multi-session handling
//
//       Ideas:
//       - Make adapters return a dynamic array of requests?
//       - Use message passing? One concurrent thread per adapter?

// TODO: Adapter-driven debugger requests
//
//       Right now, the server server handles all requests sequencially with
//       the intent to reply to the client, but there are times when the adapter
//       simply wants additional information that wouldn't be relevant to another
//       adapter. (e.g., MI protocol wants frame info on a stop event, DAP doesn't)
//
//       Ideas:
//       - Attach debugger instance to a Session class with its adapter?
//       - Abstract class can setup the event thread, etc.

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
/// 
enum DebuggerType { alicedbg }

struct DebuggerSettings
{
    DebuggerType type;
}

struct AdapterSettings
{
    AdapterType type;
}

struct ServerSettings
{
    DebuggerSettings debugger;
    AdapterSettings adapter;
    
    ushort tcpPort;
    
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
    Thread eventThread = new Thread({
    Levent:
        AdapterEvent event = debugger.wait();
        adapter.event(event); // relay to client
        
        switch (event.type) with (AdapterEventType) {
        case exited: // Process exited, so quit event thread
            return;
        default:
            goto Levent;
        }
    });
    scope(exit) if (eventThread.isRunning()) debugger.terminate();
    
    logTrace("Listening via %s using %s...", adapter.name(), adapter.transportName());
    // Get requests
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
        logTrace("Launching");
        
        with (request.launchOptions)
            try debugger.launch(path, null, null);
        catch (Exception ex)
        {
            adapter.reply(AdapterError(ex.msg));
            goto Lrequest;
        }
        
        if (request.attachOptions.run)
            eventThread.start();
        
        adapter.reply(AdapterReply());
        debuggerType = AdapterRequestType.launch;
        break;
    // Attach debugger to process
    case AdapterRequestType.attach:
        logTrace("Attaching");
        
        with (request.attachOptions)
            try debugger.attach(pid);
        catch (Exception ex)
        {
            adapter.reply(AdapterError(ex.msg));
            goto Lrequest;
        }
        
        if (request.attachOptions.run)
            eventThread.start();
        
        adapter.reply(AdapterReply());
        debuggerType = AdapterRequestType.attach;
        break;
    // Explicitly run
    case AdapterRequestType.run:
        logTrace("Running");
        
        switch (debuggerType) with (AdapterRequestType) {
        case launch, attach: // Previously launched or attached
            if (eventThread.isRunning()) { // already running...
                adapter.reply(AdapterError("Process is already running"));
                break;
            }
            eventThread.start();
            adapter.reply(AdapterReply());
            break;
        default:
        }
        break;
    // Continue
    case AdapterRequestType.continue_:
        logTrace("Continuing");
        
        try debugger.continue_();
        catch (Exception ex)
        {
            adapter.reply(AdapterError(ex.msg));
            goto Lrequest;
        }
        
        adapter.reply(AdapterReply());
        eventThread.start();
        break;
    // Detach debugger from process
    case AdapterRequestType.detach:
        logTrace("Detaching");
        
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
        logTrace("Terminating");
        
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
        logTrace("Closing debugger");
        switch (debuggerType) {
        case AdapterRequestType.launch: // was launched
            goto case AdapterRequestType.terminate;
        case AdapterRequestType.attach: // was attached
            goto case AdapterRequestType.detach;
        default:
        }
        return;
    default:
        string e = format("Request not implemented: %s", request.type);
        logError(e);
        adapter.reply(AdapterError(e));
    }
    
    goto Lrequest;
}
