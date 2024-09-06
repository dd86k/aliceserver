/// Basics for defining an adapter.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapter.types;

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
    
    /// Set current working directory of debugger.
    currentWorkingDirectory,
    
    /// Continue
    go,
    
    /// If attached, detaches the debuggee. No effect if launched.
    detach,
    /// Kill process.
    terminate,
    
    /// Close debugger and closes debuggee if running.
    close,
}

// Stuff like if lines starts at 1, etc.
enum OptionType
{
    reserved
}

/// What should the server do on a closing request?
///
/// Used internally.
enum CloseAction
{
    nothing,
    terminate,
    detach,
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
        }
        RequestAttachOptions attachOptions;
        
        struct RequestLaunchOptions
        {
            string path;
        }
        RequestLaunchOptions launchOptions;
        
        struct RequestCloseOptions
        {
            CloseAction action;
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

/*    reason: 'step' | 'breakpoint' | 'exception' | 'pause' | 'entry' | 'goto'
        | 'function breakpoint' | 'data breakpoint' | 'instruction breakpoint'
        | string;*/
enum AdapterEventStoppedReason
{
    step,
    breakpoint,
    exception,
    pause,
    entry,
    goto_,
    function_breakpoint,
    data_breakpoint,
    instruction_breakpoint,
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

struct AdapterEvent
{
    AdapterEventType type;
    
    union
    {
        struct AdapterEventStopped
        {
            AdapterEventStoppedReason reason;
            int threadId;
            /// The full reason for the event. E.g. 'Paused on exception'.
            /// This string is shown in the UI as is and can be translated.
            string description;
            /// Additional information. E.g. If reason is `exception`,
            /// text contains the exception name. This string is shown in the UI.
            string text;
        }
        AdapterEventStopped stopped;
    }
}