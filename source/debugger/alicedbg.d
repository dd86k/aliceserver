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
        _configure();
    }
    
    void attach(int pid)
    {
        process = adbg_debugger_attach(pid, 0);
        if (process == null)
            throw new AlicedbgException();
        _configure();
    }
    
    private
    void _configure()
    {
        adbg_debugger_on(process, AdbgEvent.exception, &adbgEventException);
        adbg_debugger_on(process, AdbgEvent.processExit, &adbgEventExited);
        adbg_debugger_on(process, AdbgEvent.processContinue, &adbgEventContinued);
        adbg_debugger_udata(process, &event);
    }
    
    void continue_()
    {
        enforceActiveProcess();
        // HACK: To allow continuing from a previous event
        switch (event.type) {
        case AdapterEventType.stopped:
            if (adbg_debugger_continue(process, event.stopped.threadId))
                throw new AlicedbgException();
            break;
        default:
            throw new Exception("Not in a stopped state");
        }
        _configure();
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
        if (adbg_debugger_wait(process))
            throw new AlicedbgException();
        return event;
    }
    
private:
    /// Current process.
    adbg_process_t *process;
    /// Last adapter event.
    AdapterEvent event;
    
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
    case Breakpoint:        return "Breakpoint";
    case Step:              return "Step";
    case AccessViolation:   return "Access Violation";
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

// Handle exceptions
extern (C)
void adbgEventException(adbg_process_t *proc, void *udata, adbg_exception_t *exception)
{
    AdapterEvent *event = cast(AdapterEvent*)udata;
    event.type = AdapterEventType.stopped;
    event.stopped.reason = adbgExceptionReason(exception);
    event.stopped.text = adbgExceptionName(exception);
    event.stopped.description = "Exception";
    event.stopped.threadId = cast(int)adbg_exception_tid(exception);
}

// Handle continuations
extern (C)
void adbgEventContinued(adbg_process_t *proc, void *udata)
{
    AdapterEvent *event = cast(AdapterEvent*)udata;
    event.type = AdapterEventType.continued;
    // TODO: Assign Thread ID once Alicedbg gets better TID association
    event.continued.threadId = adbg_process_id(proc);
}

// Handle exits
extern (C)
void adbgEventExited(adbg_process_t *proc, void *udata, int code)
{
    AdapterEvent *event = cast(AdapterEvent*)udata;
    event.type = AdapterEventType.exited;
    event.exited.code = code;
}
