/// Implements a debugger using Alicedbg.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module debuggers.alicedbg;

import core.thread;
import core.sync.mutex;
import std.string : toStringz, fromStringz;
import ddlogger;
import debugger;
import adbg.debugger;
import adbg.error;
import adbg.machines;
import adbg.process.exception;
import adbg.process.frame;
import adbg.process.thread;
import adbg.easy;

class AlicedbgException : Exception
{
    this(
        string file_ = __FILE__, size_t line_ = __LINE__)
    {
        super(
            cast(string)fromStringz(adbg_error_message()),
            file_, line_
        );
    }
}

private
struct AliceDebuggerState
{
    DebuggerEvent event;
    AliceDebugger debugger;
}

class AliceDebugger : IDebugger
{
    this()
    {
        eventMutex = new Mutex();
        ez = adbg_easy_create();
        if (ez == null)
            throw new AlicedbgException();
        adbg_easy_set_event_handler(ez, &adbgEventHandler);
        state.debugger = this;
        adbg_easy_set_user_data(ez, &state);
    }

    void launch(string exec, string[] args, string dir)
    {
        logTrace("exec=%s args=%s dir=%s", exec, args, dir);
        int rc = adbg_easy_spawn(ez, exec.toStringz());
        if (rc < 0)
            throw new AlicedbgException();
        attached_ = true;
    }

    void attach(int pid)
    {
        logTrace("pid=%d", pid);
        int rc = adbg_easy_attach(ez, pid);
        if (rc < 0)
            throw new AlicedbgException();
        attached_ = true;
    }

    bool attached()
    {
        return attached_;
    }

    void pause()
    {
        enforceActiveProcess();
        int rc = adbg_easy_pause(ez);
        if (rc < 0)
            throw new AlicedbgException();
    }

    void continueThread(int tid)
    {
        logTrace("tid=%d", tid);
        enforceActiveProcess();
        int rc = adbg_easy_continue(ez, tid);
        if (rc < 0)
            throw new AlicedbgException();
    }

    int[] threads()
    {
        enforceActiveProcess();
        void *tlist = adbg_thread_list_new(ez.process);
        if (tlist == null)
            throw new AlicedbgException();
        scope(exit) adbg_thread_list_close(tlist);
        size_t i;
        adbg_process_thread_t *thread = void;
        int[] threads;
        while ((thread = adbg_thread_list_get(tlist, i++)) != null)
            threads ~= cast(int)adbg_process_thread_id(thread);
        return threads;
    }

    void terminate()
    {
        enforceActiveProcess();
        int rc = adbg_easy_terminate(ez);
        if (rc < 0)
            throw new AlicedbgException();
        attached_ = false;
    }

    void detach()
    {
        enforceActiveProcess();
        int rc = adbg_easy_detach(ez);
        if (rc < 0)
            throw new AlicedbgException();
        attached_ = false;
    }

    DebuggerFrameInfo frame(int tid)
    {
        enforceActiveProcess();

        adbg_process_thread_t *thread = adbg_process_thread_create_from_id(ez.process, tid);
        if (thread == null)
            throw new AlicedbgException();
        scope(exit) adbg_process_thread_close(thread);

        adbg_frames_t *framelist = adbg_frame_list(thread);
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
        frame.arch = adbgMachine( adbg_process_machine(ez.process) );
        return frame;
    }

    /// Push an event onto the queue (called from C callback, thread-safe).
    void pushEvent(DebuggerEvent event)
    {
        eventMutex.lock();
        eventQueue ~= event;
        eventMutex.unlock();
    }

    /// Take all queued events (non-blocking).
    DebuggerEvent[] pollEvents()
    {
        eventMutex.lock();
        DebuggerEvent[] events = eventQueue;
        eventQueue = null;
        eventMutex.unlock();
        return events;
    }

private:
    ///
    adbg_easy_t *ez;

    AliceDebuggerState state;

    bool attached_;

    Mutex eventMutex;
    DebuggerEvent[] eventQueue;

    /// Throw if debugger is not attached to a process.
    void enforceActiveProcess()
    {
        if (attached_ == false)
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

extern (C)
void adbgEventHandler(adbg_easy_t *ez, adbg_process_t *aprocess, adbg_event_t *aevent, void *adata)
{
    AliceDebuggerState *state = cast(AliceDebuggerState*)adata;

    DebuggerEvent event;

    final switch (aevent.type) {
    case AdbgEvent.exception:
        event.type = DebuggerEventType.stopped;
        event.stopped.reason = adbgStoppedReason(&aevent.exception);
        event.stopped.threadId = cast(int)adbg_process_thread_id(&aevent.exception.thread);
        break;
    case AdbgEvent.processCreated:
        event.type = DebuggerEventType.process;
        break;
    case AdbgEvent.processContinue:
        event.type = DebuggerEventType.continued;
        break;
    case AdbgEvent.processExit:
        event.type = DebuggerEventType.exited;
        // TODO: event.exited.code from aevent
        break;
    case AdbgEvent.processPaused:
        event.type = DebuggerEventType.stopped;
        event.stopped.reason = DebuggerStoppedReason.pause;
        break;
    }

    state.debugger.pushEvent(event);
}
