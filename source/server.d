/// Server core.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module server;

// std
import std.concurrency;
import std.conv;
import std.string;
import core.thread;
// self
import logging;
import adapters;
import adapters.dap;
import transports;
// ext
import adbg.debugger.process;
import adbg.debugger.exception;
import adbg.error;

/// Server settings.
struct ServerSettings
{
    
}

/// Start server loop.
///
/// Right now, only single-session mode and DAP are supported.
void serverStart(ServerSettings settings)
{
    adapter = new DAPAdapter(new HTTPStdioTransport());
    
    logTrace("Listening...");
    AdapterRequest request = void;
LISTEN:
    try request = adapter.listen();
    catch (Exception ex)
    {
        logError(ex.msg);
        adapter.reply(AdapterError(ex.msg));
        goto LISTEN;
    }
    
    switch (request.type) {
    case RequestType.launch:
        if (debugger.active)
        {
            adapter.reply(AdapterError("Debugger already active"));
            break;
        }
        debugger.tid = spawn(&handleDebugger, thisTid,
            DebuggerStartOptions(request.launchOptions.path));
        break;
    case RequestType.attach:
        if (debugger.active)
        {
            adapter.reply(AdapterError("Debugger already active"));
            break;
        }
        debugger.tid = spawn(&handleDebugger, thisTid,
            DebuggerStartOptions(request.attachOptions.pid));
        break;
    case RequestType.detach:
        if (debugger.active == false) // Nothing to detach from
        {
            break;
        }
        send(debugger.tid, MsgDetach());
        break;
    case RequestType.terminate:
        if (debugger.active == false) // Nothing to terminate
        {
            break;
        }
        send(debugger.tid, MsgTerminate());
        break;
    case RequestType.close:
        if (debugger.active && request.closeOptions.action != CloseAction.nothing)
        {
            logTrace("Sending debugger termination signal...");
            send(debugger.tid, MsgQuit());
            logTrace("Wait for debugger to quit...");
            static immutable Duration quitTimeout = 5.seconds;
            if (receiveTimeout(quitTimeout, (MsgQuitAck mack) {}) == false)
                logWarn("Debugger did not reply in %s, quitting anyway", quitTimeout);
        }
        return;
    default:
        logCritical("Request not implemented: %s", request.type);
        assert(false);
    }
    goto LISTEN;
}

private:

struct DebuggerInfo
{
    bool active;
    adbg_process_t *process;
    Tid tid;
}

//
// Messages
//

struct MsgDetach {}
struct MsgTerminate {}
struct MsgQuit {}
struct MsgQuitAck {}

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

__gshared Adapter adapter;
__gshared DebuggerInfo debugger;

//TODO: Should errors and replies be sent back to server?
void handleDebugger(Tid parent, DebuggerStartOptions options)
{
    debugger.process = options.type == RequestType.attach ?
        adbg_debugger_attach(options.attachOptions.pid, 0) :
        adbg_debugger_spawn(options.launchOptions.path.toStringz(), 0);
    if (debugger.process == null)
    {
        scope errmsg = cast(string)fromStringz(adbg_error_msg());
        logError("Debugger: %s", errmsg);
        debugger.active = false;
        adapter.reply(AdapterError(errmsg));
        return;
    }
    
    Tid debugger_events_tid = spawn(&handleDebuggerEvents, thisTid);

    //TODO: Add logging for debug session here
    //      Client would like to know everything related to debug session
    //      but not the internal state of the debugger server.
    
    debugger.active = true;
    AdapterReply res;
    res.type = options.type;
    adapter.reply(res);
    
    bool done;
    while (done == false)
    {
        receive(
            (MsgDetach mdetach) {
                if (adbg_debugger_detach(debugger.process))
                {
                    adapter.reply(AdapterError(
                        cast(string)fromStringz(adbg_error_msg())
                    ));
                }
                else
                {
                    send(debugger_events_tid, MsgQuit());
                    res.type = RequestType.detach;
                    adapter.reply(res);
                }
            },
            (MsgTerminate mterminate) {
            },
            (MsgQuit mquit) {
                logTrace("Debugger: Closing debugger...");
                send(parent, MsgQuitAck());
                send(debugger_events_tid, MsgQuit());
                done = true;
            }
        );
    }
}

void handleDebuggerEvents(Tid parent)
{
    bool done;
    while (done == false)
    {
        if (adbg_debugger_wait(debugger.process, &debuggerException))
        {
            string errmsg = cast(string)fromStringz(adbg_error_msg());
            logError("EventHandler: %s", errmsg);
            //send(Msg
            return;
        }
        receiveTimeout(25.msecs,
            (MsgQuit mquit) {
                logTrace("Closing event handler thread...");
                done = true;
            }
        );
    }
}

string eventName(int type)
{
    switch (type) with (AdbgEvent) {
    case exception: return "Exception";
    default:        return "Unknown";
    }
}

extern (C)
void debuggerException(adbg_process_t *proc, int type, void *data)
{
    logTrace("Event: %s (%d)", eventName(type), type);
    switch (type) with (AdbgEvent) {
    case exception:
        adbg_exception_t *ex = cast(adbg_exception_t*)data;
        //adapter.event(AdapterEvent());
        break;
    default:
        return;
    }
}
