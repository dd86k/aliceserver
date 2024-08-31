/// Basics for defining an adapter.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapters.base;

public import transports.base : ITransport;
import core.thread : Thread;
import std.datetime : Duration, dur;
import ddlogger;

// NOTE: Rationale for structure messaging
//
//       Structures are used for messaging between the server and the client internally.
//
//       They allow to:
//       - Be used in message passing concurrency.
//       - Add additional details when necessary.

//
// Request types
//

enum RequestType
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
    RequestType type;
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
    EventType type;
    
    union
    {
        
    }
}

/// Abstract Adapter class used to interface a protocol.
///
/// This class alone is incapable to interface with the server.
abstract class Adapter
{
    this(ITransport t)
    {
        assert(t);
        transport = t;
    }
    
    // TODO: Consider mutex *if* data starts getting mangled
    
    // Send data to client.
    void send(ubyte[] data)
    {
        logTrace("Sending %u bytes", data.length);
        transport.send(data);
    }
    void send(const(char)[] data)
    {
        send(cast(ubyte[])data);
    }
    
    // Receive request from client.
    ubyte[] receive()
    {
        static immutable Duration sleepTime = dur!"msecs"(2000);
    Lread:
        ubyte[] data = transport.receive();
        if (data is null)
        {
            logInfo("Got empty buffer, sleeping for %s", sleepTime);
            Thread.sleep(sleepTime);
            goto Lread;
        }
        // NOTE: So far, only two adapters are available, and are text-based
        logTrace("Received %u bytes: %s", data.length, cast(string)data);
        return data;
    }
    
    // Listen for requests.
    AdapterRequest listen();
    // Send a successful reply to request.
    void reply(AdapterReply msg);
    // Send an error reply to request.
    void reply(AdapterError msg);
    // Send an event.
    void event(AdapterEvent msg);
    // Close adapter.
    void close();

private:
    ITransport transport;
}