/// Server core.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module aliceserver;

import std.stdio;
import std.socket;
import std.concurrency;
import std.conv;
import std.string;
import core.thread;
import core.time : msecs;
import ddlogger;
import adapter;
import adapters.dap : DAPAdapter;
import adapters.mi  : MIAdapter;
import debugger;
import debuggers.alicedbg : AliceDebugger;
import transport;
import transports.stdio : StdioTransport;

/// Aliceserver version
immutable string PROJECT_VERSION   = "0.0.0";
/// Aliceserver license
immutable string PROJECT_LICENSE   = "BSD-3-Clause-Clear";
/// Aliceserver copyrights
immutable string PROJECT_COPYRIGHT = "Copyright (c) 2024 github.com/dd86k <dd@dax.moe>";

// NOTE: Structure
//
//       The server can ultimately handle one adapter protocol, and if the
//       adapter allows it, the server can handle multiple debugger sessions,
//       often called "multi-session" servers, at the request of the adapter.
//
//       In general, the server understands close requests, but debuggers do not
//       (their UI do, though). Debuggers only understand detach and terminate
//       requests.

// NOTE: Threading
//
//       The main thread handles the adapter instance, and one or
//       more threads are spun on new debugger session requests.
//
//       Child thread handle their own debugger instance.
//       (TODO) Attach debugger ID to requests.

debug enum LogLevel DEFAULT_LOGLEVEL = LogLevel.trace;
else  enum LogLevel DEFAULT_LOGLEVEL = LogLevel.info;

/// Adapter type.
enum AdapterType { dap, mi, mi2, mi3, mi4 }
/// 
enum DebuggerType { alicedbg }

struct DebuggerSettings
{
    DebuggerType type;
}

struct AdapterSettings
{
    AdapterType type;
}

struct ServerSettings
{
    DebuggerSettings debugger;
    AdapterSettings adapter;
    
    ushort listenPort;
    string listenHost = "localhost";
    
    bool logStderr;
    string logFile;
    LogLevel logLevel = DEFAULT_LOGLEVEL;
}

// transport handler
void startServer(ServerSettings settings)
{
    // Create adapter
    logDebugging("adapter=%s", settings.adapter.type);
    IAdapter adapter = void;
    final switch (settings.adapter.type) with (AdapterType) {
    case dap:
        adapter = new DAPAdapter();
        break;
    case mi:
        adapter = new MIAdapter(1);
        break;
    case mi2:
        adapter = new MIAdapter(2);
        break;
    case mi3:
        adapter = new MIAdapter(3);
        break;
    case mi4:
        adapter = new MIAdapter(4);
        break;
    }
    
    // Create transport for adapter
    // Right now, only single-session is supported, via stdio
    ITransport transport = new StdioTransport();
    
    // Create debugger instance for adapter
    IDebugger debugger = new AliceDebugger();
    
    // Server-owned poll loop
    while (true)
    {
        if (transport.hasData())
        {
            if (adapter.handleRequest(debugger, transport) == ADAPTER_QUIT)
                break;
        }

        foreach (event; debugger.pollEvents())
            adapter.sendEvent(event, transport);

        Thread.sleep(1.msecs);
    }
    if (debugger.attached()) debugger.terminate();
}
