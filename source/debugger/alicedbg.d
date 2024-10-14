/// Implements a debugger using Alicedbg.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module debugger.alicedbg;

import std.string : toStringz, fromStringz;
import logging;
import debugger.base;
import adapter.types;
import adbg.debugger;
import adbg.process.exception;
import adbg.error;

// TODO: Could be possible to make a "AlicedbgRemote" class for remote sessions
//       Could support multiple protocols (SSH, custom, etc.)

class AlicedbgException : Exception
{
    this()
    {
        super(cast(string)fromStringz(adbg_error_message()));
    }
}

class AliceDebugger : IDebugger
{
    void launch(string exec, string[] args, string cwd)
    {
        process = adbg_debugger_spawn(exec.toStringz(), 0);
        if (process == null)
            throw new AlicedbgException();
    }
    
    void attach(int pid)
    {
        process = adbg_debugger_attach(pid, 0);
        if (process == null)
            throw new AlicedbgException();
    }
    
    void continue_()
    {
        enforceActiveProcess();
        if (adbg_debugger_continue(process))
            throw new AlicedbgException();
    }
    
    void terminate()
    {
        enforceActiveProcess();
        if (adbg_debugger_terminate(process))
            throw new AlicedbgException();
        process = null;
    }
    
    void detach()
    {
        enforceActiveProcess();
        if (adbg_debugger_detach(process))
            throw new AlicedbgException();
        process = null;
    }
    
    AdapterEvent wait()
    {
        enforceActiveProcess();
        AdapterEvent event = void;
        if (adbg_debugger_wait(process, &handleAdbgEvent, &event))
            throw new AlicedbgException();
        return event;
    }
    
private:
    /// Current process.
    adbg_process_t *process;
    
    // Actively check if we have an active process.
    // Otherwise, Alicedbg would complain about an invalid handle, which
    // could be confusing.
    void enforceActiveProcess()
    {
        if (process == null)
            throw new Exception("No process attached.");
    }
}

private:

// Get a short text name from an Alicedbg exception
string adbgExceptionName(adbg_exception_t *ex)
{
    switch (ex.type) with (AdbgException) {
    case Exit:              return "Exit";
    case Breakpoint:        return "Breakpoint";
    case Step:              return "Step";
    case Fault:             return "Fault";
    case BoundExceeded:     return "Bound Exceeded";
    case Misalignment:      return "Misalignment";
    case IllegalInstruction:return "Illegal Instruction";
    case ZeroDivision:      return "Zero Division";
    case PageError:         return "Page Error";
    case IntOverflow:       return "Int Overflow";
    case StackOverflow:     return "Stack Overflow";
    case PrivilegedOpcode:  return "Privileged Opcode";
    case FPUDenormal:       return "FPU Denormal";
    case FPUZeroDivision:   return "FPU ZeroDivision";
    case FPUInexact:        return "FPU Inexact";
    case FPUIllegal:        return "FPU Illegal";
    case FPUOverflow:       return "FPU Overflow";
    case FPUUnderflow:      return "FPU Underflow";
    case FPUStackOverflow:  return "FPU StackOverflow";
    case Disposition:       return "Disposition";
    case NoContinue:        return "No Continue";
    default:                return null;
    }
}

// Translate Alicedbg exception type to adapter stop reason
AdapterEventStoppedReason adbgExceptionReason(adbg_exception_t *ex) {
    switch (ex.type) with (AdbgException) {
    case Breakpoint:    return AdapterEventStoppedReason.breakpoint;
    case Step:  return AdapterEventStoppedReason.step;
    default:    return AdapterEventStoppedReason.exception;
    }
}

// Handle Alicedbg events
extern (C)
void handleAdbgEvent(adbg_process_t *proc, int type, void *edata, void *udata)
{
    AdapterEvent *event = cast(AdapterEvent*)udata;
    switch (type) {
    case AdbgEvent.exception:
        event.type = AdapterEventType.stopped;
        adbg_exception_t *ex = cast(adbg_exception_t*)edata;
        event.stopped.reason = adbgExceptionReason(ex);
        event.stopped.text = adbgExceptionName(ex);
        event.stopped.description = "Exception";
        // TODO: Assign Thread ID once Alicedbg gets TID association
        event.stopped.threadId = 0;
        return;
    case AdbgEvent.processExit:
        event.type = AdapterEventType.exited;
        int *code = cast(int*)edata;
        event.exited.code = *code;
        return;
    default:
        // ...
    }
}