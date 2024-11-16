/// Debugger interface and types.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module debugger;

enum Architecture
{
    i386,
    x86_64,
    AArch32,
    AArch64,
}

version (X86)       enum TARGET_ARCH = Architecture.i386;
version (X86_64)    enum TARGET_ARCH = Architecture.x86_64;
version (ARM)       enum TARGET_ARCH = Architecture.AArch32;
version (AArch64)   enum TARGET_ARCH = Architecture.AArch64;

enum DebuggerEventType
{
    /// When a breakpoint's state changes (modified, removed, etc.).
    breakpoint,
    /// When debugger's list of capabilities change, usually after startup.
    capabilities,
    /// Debuggee/tracee has resumed execution.
    continued,
    /// Debuggee/tracee has exited.
    exited,
    /// Debugger server is ready to accept configuration requests.
    initialized,
    /// Debugger server state changed (e.g., setting) and client needs to refresh.
    invalidated,
    /// Source file added, changed, or removed, from loaded sources.
    loadedSource,
    /// Memory range has received an update.
    memory,
    /// Module was (loaded, changed, removed).
    module_,
    /// Debuggee process message.
    output,
    /// A sub-process was spawned, or removed.
    process,
    /// 
    progressEnd,
    /// 
    progressStart,
    /// 
    progressUpdate,
    /// The debuggee stopped.
    stopped,
    /// The debuggee was terminated.
    terminated,
    /// Thread event.
    thread,
}

enum DebuggerStoppedReason
{
    /// Process paused.
    pause,
    /// Function or scope entry.
    entry,
    /// Source or instruction goto.
    goto_,
    /// Exception.
    exception,
    /// Access violation exception
    accessViolationException,
    /// Illegal instruction exception
    illegalInstructionException,
    /// Source or instruction step.
    step,
    /// Source breakpoint.
    breakpoint,
    /// Function breakpoint. (function entry breakpoint?)
    functionBreakpoint,
    /// Data watcher breakpoint.
    dataBreakpoint,
    /// Instruction-level breakpoint.
    instructionBreakpoint,
}

struct DebuggerEvent
{
    DebuggerEventType type;
    
    union
    {
        struct AdapterEventStopped
        {
            /// Thread ID that caused the stop.
            int threadId;
            /// The reason for the event.
            DebuggerStoppedReason reason;
        }
        AdapterEventStopped stopped;
        
        struct AdapterEventContinued
        {
            int threadId;
        }
        AdapterEventContinued continued;
        
        struct AdapterEventExited
        {
            /// The exit code returned from the debugged process.
            int code;
        }
        AdapterEventExited exited;
    }
}

struct DebuggerFrameInfo
{
    ulong address;
    string funcname;
    string[] funcargs;
    Architecture arch;
}

interface IDebugger
{
    /// Launch a new process with the debugger.
    /// Params:
    ///     exec = Path to executable.
    ///     args = Executable arguments.
    ///     cwd = Working directory for executable.
    void launch(string exec, string[] args, string cwd);
    /// Attach to process.
    /// Params: pid = Process ID.
    void attach(int pid);
    
    /// Terminate process.
    void terminate();
    /// Detach debugger from process.
    void detach();
    
    /// Continue thread.
    void continue_(int tid);
    
    /// List threads of process.
    int[] threads();
    
    /// 
    DebuggerFrameInfo frame(int tid);
    
    // Event stuff
    
    /// 
    void hook(void delegate(ref DebuggerEvent));
    /// Run debugger and perform action on events.
    void run();
    /// 
    bool listening();
}