/// Server core.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module aliceserver;

import adapter;
import adapters.dap : DAPAdapter;
import adapters.mi  : MIAdapter;
import core.thread : Thread;
import core.time : msecs;
import ddlogger;
import debugger : IDebugger;
import debuggers.alicedbg : AliceDebugger;
import transport : ITransport;
import transports.socket : SocketTransport;
import transports.stdio  : StdioTransport;

/// Aliceserver version
immutable string PROJECT_VERSION   = "0.0.0";
/// Aliceserver license
immutable string PROJECT_LICENSE   = "BSD-3-Clause-Clear";
/// Aliceserver copyrights
immutable string PROJECT_COPYRIGHT = "Copyright (c) 2024-2026 github.com/dd86k <dd@dax.moe>";

/// Adapter type, defaults to dap.
enum AdapterType
{
    dap,    /// Debugging Adapter Protocol
    mi,     /// GDB/MI, latest version
    mi2,    /// GDB/MI version 2
    mi3,    /// GDB/MI version 3
    mi4,    /// GDB/MI version 4
}
/// Debugger type, defaults to alicedbg.
enum DebuggerType
{
    alicedbg,   /// Alicedbg
}
/// Transport type, defaults to stdio,
enum TransportType
{
    stdio,  /// Standard streams
    tcp,    /// TCP, for multisessions
    pipe,   /// UNIX socket or Windows NamedPipe, for multisessons
}

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
    DebuggerType debugger;
    AdapterType  adapter;
    TransportType transport;

    bool multi; /// Multisession support

    ushort port; // GraalVM uses 4711, but only does TCP
    string host;
}

// transport handler
void startServer(ServerSettings settings)
{
    // Only DAP supports multisession
    // Or if we init adapter with AdapterSettings... Make the adapter throw?
    if (settings.multi && settings.adapter != AdapterType.dap)
        throw new Exception("Only DAP supports multisession");
    
    // Create transport
    ITransport transport = void;
    final switch (settings.transport) {
    case TransportType.stdio:
        transport = new StdioTransport();
        break;
    case TransportType.tcp:
        transport = new SocketTransport(settings.host, settings.port);
        break;
    case TransportType.pipe:
        version (Windows)
            throw new Exception("TODO: NamedPipeTransport");
        else
            transport = new SocketTransport(settings.host);
        break;
    }
    
    // Create adapter
    logDebugging("adapter=%s", settings.adapter);
    IAdapter adapter = void;
    final switch (settings.adapter) with (AdapterType) {
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
    
    // Create debugger instance for adapter
    IDebugger debugger = new AliceDebugger();
    
    // Let the adapter perform any initial handshaking
    adapter.init(transport);

    // Server-owned poll loop
    Lmain: while (true)
    {
        if (transport.hasData())
        {
            switch (adapter.handleRequest(debugger, transport)) {
            case ADAPTER_QUIT: break Lmain;
            default:
            }
        }

        foreach (event; debugger.pollEvents())
            adapter.sendEvent(event, transport);

        Thread.sleep(1.msecs);
    }
    if (debugger.attached()) debugger.terminate();
}
