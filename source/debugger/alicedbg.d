/// Implements a debugger using Alicedbg.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module debugger.alicedbg;

import core.thread;
import std.string : toStringz, fromStringz;
import logging;
import debuggers;
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
    
    void continue_(int tid)
    {
        enforceActiveProcess();
        if (adbg_debugger_continue(process, tid))
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
    
    DebuggerEvent wait()
    {
        enforceActiveProcess();
        DebuggerEvent event = void;
        if (adbg_debugger_wait(process))
            throw new AlicedbgException();
        return event;
    }
    
    void hook(void delegate(ref DebuggerEvent) send)
    {
        eventThread = new Thread({
        Levent:
            DebuggerEvent event = wait();
            send(event);
            
            switch (event.type) with (DebuggerEventType) {
            case exited: // Process exited, so quit event thread
                return;
            default:
                goto Levent;
            }
        });
    }
    
    void run()
    {
        enforceActiveProcess();
        if (eventThread is null)
            throw new Exception("Event dispatcher unhooked");
        eventThread.start();
    }
    
    bool listening()
    {
        return eventThread && eventThread.isRunning();
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
    
    /// 
    Thread eventThread;
    
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
DebuggerStopReason adbgExceptionReason(adbg_exception_t *ex) {
    switch (ex.type) with (AdbgException) {
    case Breakpoint:    return DebuggerStopReason.breakpoint;
    case Step:  return DebuggerStopReason.step;
    default:    return DebuggerStopReason.exception;
    }
}

// Translate AdbgMachine to MachineArchitcture
Architecture adbgMachine(AdbgMachine mach)
{
    switch (mach)  {
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
    event.stopped.reason = adbgExceptionReason(exception);
    event.stopped.threadId = cast(int)adbg_exception_tid(exception);
}

// Handle continuations
extern (C)
void adbgEventContinued(adbg_process_t *proc, void *udata)
{
    DebuggerEvent *event = cast(DebuggerEvent*)udata;
    event.type = DebuggerEventType.continued;
    // TODO: Assign Thread ID once Alicedbg gets better TID association
    event.continued.threadId = adbg_process_id(proc);
}

// Handle exits
extern (C)
void adbgEventExited(adbg_process_t *proc, void *udata, int code)
{
    DebuggerEvent *event = cast(DebuggerEvent*)udata;
    event.type = DebuggerEventType.exited;
    event.exited.code = code;
}
