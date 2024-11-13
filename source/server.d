/// Server core.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module server;

import std.stdio;
import std.socket;
import std.concurrency;
import std.conv;
import std.string;
import core.thread;
import ddlogger;
import adapter;
import adapters.dap : DAPAdapter;
import adapters.mi  : MIAdapter;
import debugger;
import debuggers.alicedbg : AliceDebugger;
import transport;
import transports.stdio : StdioTransport;

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
    IAdapter adapter = void;
    final switch (settings.adapter.type) with (AdapterType) {
    case dap:
        adapter = new DAPAdapter();
        break;
    case mi, mi2, mi3, mi4:
        adapter = new MIAdapter(settings.adapter.type);
        break;
    }
    
    ITransport transport = new StdioTransport();
    IDebugger debugger = new AliceDebugger();
    adapter.loop(debugger, transport);
    if (debugger.listening()) debugger.terminate();
}
