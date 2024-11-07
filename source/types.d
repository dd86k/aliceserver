/// Server types.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module types;

enum MachineArchitecture
{
    i386,
    x86_64,
    AArch32,
    AArch64,
}

//
// Request types
//

enum AdapterRequestType
{
    unknown,
    
    initializaton,
    
    /// Spawn process via debugger
    launch,
    /// Attach debugger to process
    attach,
    
    /// Explicitly start the process if it was not running.
    run,
    
    /// Set current working directory of debugger.
    currentWorkingDirectory,
    
    /// Continue
    continue_,
    
    /// If attached, detaches the debuggee. No effect if launched.
    detach,
    /// Kill process.
    terminate,
    
    /// Close debugger and close debuggee if still running.
    close,
}

// Stuff like if lines starts at 1, etc.
enum OptionType
{
    reserved
}

struct AdapterRequest
{
    /// Request type.
    AdapterRequestType type;
    /// Request ID. Must be non-zero.
    int id;
    
    union
    {
        struct RequestAttachOptions
        {
            int pid;
            bool run;
        }
        RequestAttachOptions attachOptions;
        
        struct RequestLaunchOptions
        {
            string path;
            bool run;
        }
        RequestLaunchOptions launchOptions;
        
        struct RequestContinueOptions
        {
            int tid; /// Thread ID
        }
        RequestContinueOptions continueOptions;
        
        struct RequestCloseOptions
        {
            bool terminate; /// Optional: If launched, terminate process.
        }
        RequestCloseOptions closeOptions;
    }
}

//
// Reply types
//

/// Used to reply that the command was successfully executed
/// by the server.
struct AdapterReply
{
    string details;
}

/// Used to reply an error back to the client, that the request
/// has failed.
struct AdapterError
{
    string message;
}

//
// Event types
//

enum AdapterEventType
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

// DAP: 'step', 'breakpoint', 'exception', 'pause', 'entry', 'goto'
//      'function breakpoint', 'data breakpoint', 'instruction breakpoint', etc.
enum AdapterEventStoppedReason
{
    /// Source or instruction step.
    step,
    /// Source breakpoint.
    breakpoint,
    /// Exception.
    exception,
    /// Process paused.
    pause,
    /// Function or scope entry.
    entry,
    /// Source or instruction goto.
    goto_,
    /// Function breakpoint. (function entry breakpoint?)
    functionBreakpoint,
    /// Data watcher breakpoint.
    dataBreakpoint,
    /// Instruction-level breakpoint.
    instructionBreakpoint,
}

// DAP has these output message types:
// - console  : Client UI debug console, informative only
// - important: Important message from debugger
// - stdout   : Debuggee stdout message
// - stderr   : Debuggee stderr message
// - telemetry: Sent to a telemetry server instead of client
//
// MI has these output message types:
// - ~ : Stdout output
// - & : Command echo
enum EventMessageType
{
    stdout,
    stderr,
    
}

struct AdapterFrame
{
    ulong address;
    string func;
    string[] args;
    MachineArchitecture arch;
}

struct AdapterEvent
{
    AdapterEventType type;
    
    union
    {
        struct AdapterEventStopped
        {
            /// The reason for the event.
            /// 
            /// DAP:
            /// For backward compatibility this string is shown in the UI if the
            /// `description` attribute is missing (but it must not be translated).
            /// Values: 'step', 'breakpoint', 'exception', 'pause', 'entry', 'goto',
            /// 'function breakpoint', 'data breakpoint', 'instruction breakpoint', etc.
            AdapterEventStoppedReason reason;
            /// Thread ID that caused the stop.
            int threadId;
            /// DAP:
            /// The full reason for the event. E.g. 'Paused on exception'.
            /// This string is shown in the UI as is and can be translated.
            string description;
            /// DAP:
            /// Additional information. E.g. If reason is `exception`,
            /// text contains the exception name. This string is shown in the UI.
            string text;
            /// MI: Describes the frame where the stop event happened.
            AdapterFrame frame;
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
