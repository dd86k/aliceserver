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
import std.socket;
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
    dap,    /// Debug Adapter Protocol
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
    stdio,  /// Standard streams (single session)
    tcp,    /// TCP (multi session)
    pipe,   /// UNIX socket or Windows NamedPipe (multi session)
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

    ushort port; // GraalVM/VSCode use 4711, but only uses TCP
    string host;
    
    /// When using GDB/MI, do not print version (like GDB does)
    bool quiet;
}

void startServer(ServerSettings settings)
{
    final switch (settings.transport) {
    case TransportType.stdio:
        logDebugging("Listening via stdio...");
        // Single session: stdio is one-shot
        runSession(settings, new StdioTransport());
        break;
    case TransportType.tcp:
        listenTcp(settings);
        break;
    case TransportType.pipe:
        version (Windows)
            listenPipe(settings);
        else
            listenUnix(settings);
        break;
    }
}

private:

/// Run new session on the given transport.
void runSession(ServerSettings settings, ITransport transport)
{
    logDebugging("adapter=%s", settings.adapter);
    IAdapter adapter = void;
    final switch (settings.adapter) with (AdapterType) {
    case dap:   adapter = new DAPAdapter(); break;
    case mi:    adapter = new MIAdapter(1, settings.quiet); break;
    case mi2:   adapter = new MIAdapter(2, settings.quiet); break;
    case mi3:   adapter = new MIAdapter(3, settings.quiet); break;
    case mi4:   adapter = new MIAdapter(4, settings.quiet); break;
    }

    IDebugger debugger = new AliceDebugger();
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

/// Listen on TCP, accepting connections in a loop.
void listenTcp(ServerSettings settings)
{
    string host = settings.host !is null ? settings.host : "localhost";
    if (settings.port == 0)
        throw new Exception("I refuse to listen on port 0");

    auto listener = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
    scope(exit) listener.close();

    listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
    listener.bind(new InternetAddress(host, settings.port));
    listener.listen(1);
    logInfo("Listening on %s:%d", host, settings.port);

    while (true)
    {
        Socket conn = listener.accept();
        logInfo("Accepted connection");
        runSession(settings, new SocketTransport(conn));
        logInfo("Session ended, waiting for next connection");
    }
}

// If string is null or empty (length zero)
bool isEmpty(string s)
{
    return s is null || s.length == 0;
}

/// Listen on a Unix socket, accepting connections in a loop.
version (Posix)
void listenUnix(ServerSettings settings)
{
    import std.file : exists, remove;
    import std.process : environment;
    import std.path : buildPath;

    if (settings.host.isEmpty())
        throw new Exception("Unix socket path is required and cannot be empty");

    if (exists(settings.host))
        remove(settings.host);

    Socket listener = new Socket(AddressFamily.UNIX, SocketType.STREAM);
    scope(exit) listener.close();
    
    // If path separator prefix detected, assume as full path
    // Otherwise, it is just a name
    string sockpath = settings.host[0] == '/' ?
        settings.host :
        buildPath(environment.get("XDG_RUNTIME_DIR", "/tmp"), settings.host);

    listener.bind(new UnixAddress(sockpath));
    listener.listen(1);
    logInfo("Listening on %s", settings.host);

    while (true)
    {
        Socket conn = listener.accept();
        logInfo("Accepted connection");
        runSession(settings, new SocketTransport(conn));
        logInfo("Session ended");
    }
}

version (Windows)
void listenPipe(ServerSettings settings)
{
    import core.sys.windows.windef : HANDLE, DWORD, TRUE, FALSE;
    import core.sys.windows.winbase :
        INVALID_HANDLE_VALUE,
        PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_BYTE, PIPE_WAIT,
        NMPWAIT_USE_DEFAULT_WAIT,
        CreateNamedPipeA, ConnectNamedPipe, DisconnectNamedPipe, CloseHandle;
    import std.string : toStringz;
    import std.algorithm : startsWith;
    import transports.pipe : NamedPipeTransport;

    enum DWORD PIPE_REJECT_REMOTE_CLIENTS = 0x00000008;

    if (settings.host.isEmpty())
        throw new Exception("Pipe name is required and cannot be empty");

    // If UNC prefix detected, assume as full path
    // Otherwise, it is just a name
    string pipeName = settings.host.startsWith(`\\`) ?
        settings.host :
        `\\.\pipe\` ~ settings.host;
    const(char) *pipez = pipeName.toStringz();

    logInfo("Listening on %s", pipeName);

    while (true)
    {
        // Create a new pipe instance for each connection
        HANDLE pipe = CreateNamedPipeA(pipez,
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
            1,
            4096, 4096,
            NMPWAIT_USE_DEFAULT_WAIT,
            null);
        if (pipe == INVALID_HANDLE_VALUE)
            throw new Exception("CreateNamedPipeA failed");

        // Block until a client connects
        if (ConnectNamedPipe(pipe, null) == FALSE)
        {
            CloseHandle(pipe);
            throw new Exception("ConnectNamedPipe failed");
        }

        logInfo("Accepted connection");
        runSession(settings, new NamedPipeTransport(pipe));
        logInfo("Session ended");

        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
    }
}
