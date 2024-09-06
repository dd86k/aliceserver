/// Implements a debugger using Alicedbg.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module debugger.alicedbg;

import std.string : toStringz, fromStringz;
import logging;
import debugger.base;
import adapter.base;
import adbg.debugger;
import adbg.process.exception;
import adbg.error;

// TODO: Could be possible to make a "AlicedbgRemote" class for remote sessions
//       Could support multiple protocols (SSH, custom, etc.)

class AliceDebugger : IDebugger
{
    void launch(string exec, string[] args, string cwd)
    {
        process = adbg_debugger_spawn(exec.toStringz(), 0);
        if (process == null)
            throw new Exception(adbgErrorMessage());
    }
    
    void attach(int pid)
    {
        process = adbg_debugger_attach(pid, 0);
        if (process == null)
            throw new Exception(adbgErrorMessage());
    }
    
    AdapterEvent wait()
    {
        if (process == null)
            throw new Exception("No process instance.");
        AdapterEvent event = void;
        if (adbg_debugger_wait(process, &handleAdbg, &event))
            throw new Exception(adbgErrorMessage());
        return event;
    }
    
private:
    /// Current process.
    adbg_process_t *process;
    
    string adbgErrorMessage()
    {
        return cast(string)fromStringz(adbg_error_message());
    }
}

private
string adbgExceptionName(AdbgException ex)
{
    switch (ex) with (AdbgException) {
    case Exit:              return "Exit";
    case Breakpoint:        return "Breakpoint";
    case Step:              return "Step";
    case Fault:             return "Fault";
    case BoundExceeded:     return "BoundExceeded";
    case Misalignment:      return "Misalignment";
    case IllegalInstruction:return "IllegalInstruction";
    case ZeroDivision:      return "ZeroDivision";
    case PageError:         return "PageError";
    case IntOverflow:       return "IntOverflow";
    case StackOverflow:     return "StackOverflow";
    case PrivilegedOpcode:  return "PrivilegedOpcode";
    case FPUDenormal:       return "FPUDenormal";
    case FPUZeroDivision:   return "FPUZeroDivision";
    case FPUInexact:        return "FPUInexact";
    case FPUIllegal:        return "FPUIllegal";
    case FPUOverflow:       return "FPUOverflow";
    case FPUUnderflow:      return "FPUUnderflow";
    case FPUStackOverflow:  return "FPUStackOverflow";
    case Disposition:       return "Disposition";
    case NoContinue:        return "NoContinue";
    default:                return null;
    }
}

extern (C)
private
void handleAdbg(adbg_process_t *proc, int type, void *edata, void *udata)
{
    AdapterEvent *event = cast(AdapterEvent*)udata;
    
    switch (type) {
    case AdbgEvent.exception:
        adbg_exception_t *ex = cast(adbg_exception_t*)edata;
    
        event.type = AdapterEventType.stopped;
        event.stopped.reason = AdapterEventStoppedReason.exception;
        event.stopped.description = "Exception";
        event.stopped.threadId = ex.tid;
        event.stopped.text = adbgExceptionName(ex.type);
        return;
    default:
        // ...
    }
}