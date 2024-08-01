/// Basics for defining an adapter.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapters.base;

import transports.base;

enum RequestType
{
    initializaton,
    spawn,
    launch = spawn, /// alias for launch
    attach,
    
    /// If attached, detaches the debuggee. No effect if launched.
    detach,
    /// Kill process.
    terminate,
    
    /// Close debugger and closes debuggee if running.
    close,
}

enum EventType
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
    /// Debuggee or debugger message.
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

// Stuff like if lines starts at 1, etc.
enum OptionType
{
    reserved
}

/// What should the server do on a closing request?
enum CloseAction
{
    nothing,
    terminate,
    detach,
}

struct AdapterRequest
{
    RequestType type;
    
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

struct AdapterReply
{
    RequestType type;
    
    union
    {
        
    }
}

struct AdapterEvent
{
    EventType type;
    
    union
    {
        
    }
}

struct AdapterError
{
    string message;
}

abstract class Adapter
{
    this(ITransport t)
    {
        assert(t);
        transport = t;
    }
    
    void send(ubyte[] data)
    {
        transport.send(data);
    }
    
    ubyte[] receive()
    {
        return transport.receive();
    }
    
    AdapterRequest listen();
    void reply(AdapterReply msg);
    void reply(AdapterError msg);
    void event(AdapterEvent msg);

private:

    ITransport transport;
}