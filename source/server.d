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
import adapters, debuggers;
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
    
    // Get requests
    logTrace("Listening..."); // TODO: Add adapter and transport names into log
    RequestType debuggerType;
    Tid debuggerTid;
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
    switch (request.type) {
    // Launch process with debugger
    case RequestType.launch:
        if (debuggerType)
        {
            adapter.reply(AdapterError(messageDebuggerActive));
            goto Lrequest;
        }
        
        debuggerTid = spawn(&startDebugger, thisTid,
            DebuggerStartOptions(request.launchOptions.path));
        
        MsgReply reply = receiveOnly!MsgReply;
        if (reply.message)
        {
            adapter.reply(AdapterError(reply.message));
            goto Lrequest;
        }
        
        adapter.reply(AdapterReply());
        debuggerType = RequestType.launch;
        break;
    // Attach debugger to process
    case RequestType.attach:
        if (debuggerType)
        {
            adapter.reply(AdapterError(messageDebuggerActive));
            goto Lrequest;
        }
        
        debuggerTid = spawn(&startDebugger, thisTid,
            DebuggerStartOptions(request.attachOptions.pid));
        
        MsgReply reply = receiveOnly!MsgReply;
        if (reply.message)
        {
            adapter.reply(AdapterError(reply.message));
            goto Lrequest;
        }
        
        adapter.reply(AdapterReply());
        debuggerType = RequestType.attach;
        break;
    // Detach debugger from process
    case RequestType.detach:
        if (debuggerType == RequestType.unknown) // Nothing to detach from
        {
            adapter.reply(AdapterError(messageDebuggerUnactive));
            goto Lrequest;
        }
        
        send(debuggerTid, RequestDetach());
        
        MsgReply reply = receiveOnly!MsgReply;
        if (reply.message)
        {
            adapter.reply(AdapterError(reply.message));
            goto Lrequest;
        }
        
        adapter.reply(AdapterReply());
        debuggerType = RequestType.unknown;
        break;
    // Terminate process
    case RequestType.terminate:
        if (debuggerType == RequestType.unknown) // Nothing to terminate
        {
            adapter.reply(AdapterError(messageDebuggerUnactive));
            goto Lrequest;
        }
        
        send(debuggerTid, RequestTerminate());
        
        MsgReply reply = receiveOnly!MsgReply;
        if (reply.message)
        {
            adapter.reply(AdapterError(reply.message));
            goto Lrequest;
        }
        
        adapter.reply(AdapterReply());
        debuggerType = RequestType.unknown;
        break;
    // Either detaches or terminates process depending how the debugger is attached
    case RequestType.close:
        static immutable Duration quitTimeout = 10.seconds;
        switch (debuggerType) {
        case RequestType.launch: // if was launched
            send(debuggerTid, RequestTerminate());
            break;
        case RequestType.attach: // if was attached
            send(debuggerTid, RequestDetach());
            break;
        default:
        }
        
        if (debuggerType)
        {
            logTrace("Waiting for debugger to quit (timeout: %s)...", quitTimeout);
            if (receiveTimeout(quitTimeout, (MsgReply reply) {}) == false)
                logWarn("Debugger timeout, quitting anyway");
        }
        
        // TODO: Multi-session: Return to listen to requests if adapterCount > 0
        //       And reset debuggerType.
        adapter.close();
        return;
    default:
        string e = format("Request not implemented: %s", request.type);
        logError(e);
        adapter.reply(AdapterError(e));
    }
    
    goto Lrequest;
}

private:

// NOTE: spawn() does not allow thread-local data, like object instances

//
// Messages
//

struct MsgReply
{
    string message;
}

struct RequestDetach {}
struct RequestTerminate {}

//TODO: Add configuration settings (mainly breakpoints) before starting
struct DebuggerStartOptions
{
    this(int pid)
    {
        type = RequestType.attach;
        attachOptions.pid = pid;
    }
    
    this(string path)
    {
        type = RequestType.launch;
        launchOptions.path = path;
    }
    
    RequestType type;
    union
    {
        struct DebuggerStartAttachOptions
        {
            int pid;
        }
        DebuggerStartAttachOptions attachOptions;
        struct DebuggerStartLaunchOptions
        {
            string path;
        }
        DebuggerStartLaunchOptions launchOptions;
    }
}

// Start a new debugger instance.
//
// The only message this is allowed to send is MsgReply.
void startDebugger(Tid parent, DebuggerStartOptions start) // Handles debugger
{
    // Select debugger
    IDebugger debugger = new Alicedbg();
    
    // Hook debugger to process
    switch (start.type) with (RequestType) {
    case launch:
        try debugger.launch(start.launchOptions.path, null, null);
        catch (Exception ex)
        {
            send(parent, MsgReply(ex.msg));
            return;
        }
        
        logInfo("Debugger launched '%s'", start.launchOptions.path);
        send(parent, MsgReply());
        break;
    case attach:
        try debugger.attach(start.attachOptions.pid);
        catch (Exception ex)
        {
            send(parent, MsgReply(ex.msg));
            return;
        }
        
        logInfo("Debugger attached to process %d", start.attachOptions.pid);
        send(parent, MsgReply());
        break;
    default:
        string e = format("Unimplemented start request: %s", start.type);
        logCritical(e);
        send(parent, MsgReply(e));
        return;
    }
    
    // Now accepting requests
    bool active = true;
    while (active) receive(
        (RequestDetach req) {
            logTrace("Debugger: Detaching debugger from process...");
            /*
            try debugger.detach();
            catch (Exception ex)
            {
                send(parent, MsgReply(ex.msg));
                return;
            }
            send(parent, MsgReply());
            */
            active = false;
        },
        (RequestTerminate req) {
            logTrace("Debugger: Terminating process...");
            active = false;
        }
    );
    
    // Send terminating message
    send(parent, MsgReply());
}
