/// Implements a debugger using Alicedbg.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module debuggers.alicedbg;

import core.thread;
import std.string : toStringz, fromStringz;
import ddlogger;
import debugger;
import adbg.debugger;
import adbg.error;
import adbg.machines;
import adbg.process.exception;
import adbg.process.frame;
import adbg.process.thread;

class AlicedbgException : Exception
{
    this()
    {
        super(cast(string)fromStringz(adbg_error_message()));
    }
}

class AliceDebugger : IDebugger
{
    void launch(string exec, string[] args, string dir)
    {
        logTrace("exec=%s args=%s dir=%d", exec, args, dir);
        process = adbg_debugger_spawn(exec.toStringz(), 0);
        if (process == null)
            throw new AlicedbgException();
        _configure();
    }
    
    void attach(int pid)
    {
        logTrace("pid=%d", pid);
        process = adbg_debugger_attach(pid, 0);
        if (process == null)
            throw new AlicedbgException();
        _configure();
    }
    
    bool attached()
    {
        return process != null;
    }
    
    private
    void _configure()
    {
        adbg_debugger_on_exception(process, &adbgEventException);
        adbg_debugger_on_process_exit(process, &adbgEventExited);
        adbg_debugger_on_process_continue(process, &adbgEventContinued);
        adbg_debugger_udata(process, &event);
    }
    
    void continueThread(int tid)
    {
        logTrace("tid=%d", tid);
        enforceActiveProcess();
        if (adbg_debugger_continue(process, tid))
            throw new AlicedbgException();
    }
    
    int[] threads()
    {
        enforceActiveProcess();
        void *tlist = adbg_thread_list_new(process);
        if (tlist == null)
            throw new AlicedbgException();
        size_t i;
        adbg_thread_t *thread = void;
        int[] threads;
        while ((thread = adbg_thread_list_get(tlist, i++)) != null)
            threads ~= cast(int)adbg_thread_id(thread);
        adbg_thread_list_close(tlist);
        return threads;
    }
    
    void terminate()
    {
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
    
    DebuggerEvent wait()
    {
        enforceActiveProcess();
        DebuggerEvent event = void;
        if (adbg_debugger_wait(process))
            throw new AlicedbgException();
        return event;
    }
    
    DebuggerFrameInfo frame(int tid)
    {
        enforceActiveProcess();
        
        adbg_thread_t *thread = adbg_thread_new(tid);
        if (thread == null)
            throw new AlicedbgException();
        scope(exit) adbg_thread_close(thread);
        
        void *framelist = adbg_frame_list(process, thread);
        if (framelist == null)
            throw new AlicedbgException();
        scope(exit) adbg_frame_list_close(framelist);
        
        adbg_stackframe_t *frame0 = adbg_frame_list_at(framelist, 0);
        if (frame0 == null)
            throw new AlicedbgException();
        
        DebuggerFrameInfo frame = void;
        frame.address = frame0.address;
        frame.funcname = null;
        frame.funcargs = null;
        frame.arch = adbgMachine( adbg_process_machine(process) );
        return frame;
    }
    
private:
    /// Current process.
    adbg_process_t *process;
    
    /// Last adapter event.
    DebuggerEvent event;
    
    /// Throw if debugger is not attached to a process.
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
DebuggerStoppedReason adbgStoppedReason(adbg_exception_t *ex)
{
    switch (ex.type) {
    /*
    case 0: return DebuggerStoppedReason.functionBreakpoint;
    case 0: return DebuggerStoppedReason.dataBreakpoint;
    case 0: return DebuggerStoppedReason.instructionBreakpoint;
    */
    case AdbgException.Breakpoint:    return DebuggerStoppedReason.breakpoint;
    case AdbgException.Step:  return DebuggerStoppedReason.step;
    /*
    case 0: return DebuggerStoppedReason.pause;
    case 0: return DebuggerStoppedReason.entry;
    case 0: return DebuggerStoppedReason.goto_;
    */
    default:    return DebuggerStoppedReason.exception;
    }
}

// Translate AdbgMachine to MachineArchitcture
Architecture adbgMachine(AdbgMachine mach)
{
    switch (mach) {
    case AdbgMachine.i386:      return Architecture.i386;
    case AdbgMachine.amd64:     return Architecture.x86_64;
    case AdbgMachine.arm:       return Architecture.AArch32;
    case AdbgMachine.aarch64:   return Architecture.AArch64;
    default:                    return TARGET_ARCH;
    }
}

// Handle exceptions
extern (C)
void adbgEventException(adbg_process_t *proc, void *udata, adbg_exception_t *exception)
{
    DebuggerEvent *event = cast(DebuggerEvent*)udata;
    
    event.type = DebuggerEventType.stopped;
    event.stopped.threadId = cast(int)adbg_exception_tid(exception);
    event.stopped.reason = adbgStoppedReason(exception);
}

// Handle continuations
extern (C)
void adbgEventContinued(adbg_process_t *proc, void *udata, long id)
{
    DebuggerEvent *event = cast(DebuggerEvent*)udata;
    event.type = DebuggerEventType.continued;
    event.continued.threadId = cast(int)id;
}

// Handle exits
extern (C)
void adbgEventExited(adbg_process_t *proc, void *udata, int code)
{
    DebuggerEvent *event = cast(DebuggerEvent*)udata;
    event.type = DebuggerEventType.exited;
    event.exited.code = code;
}
