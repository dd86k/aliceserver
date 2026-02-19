/// Simple line-based transport.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module transports.socket;

public import std.socket;
import transport : ITransport;
import core.sync.mutex;
import core.time : Duration;

// NOTE: Sockets are not synchronized and thus need the mutex
class SocketTransport : ITransport
{
    // NOTE: socket type implicit from ctor isn't best but this is all internal anyway
    
    // Create a new Socket transport: TCP listener
    this(string interface_, ushort port)
    {
        if (interface_ is null)
            interface_ = "localhost";
        if (port == 0)
            throw new Exception("I refuse to listen to port 0");
        Socket sock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
        sock.bind(new InternetAddress(interface_, port));
        this(sock);
    }
    
    // Create a new Socket transport: UNIX Socket
    this(string path)
    {
        Socket sock = new Socket(AddressFamily.UNIX, SocketType.STREAM);
        sock.bind(new UnixAddress(path));
        this(sock);
    }
    
    this(Socket sock)
    {
        socket = sock;
        // defaults to FD_SETSIZE=64 on Windows, a little too much
        set = new SocketSet(4);
        set.add(socket);
        mutex = new shared Mutex();
    }
    
    string name() { return "socket"; }
    
    ubyte[] readline()
    {
        throw new Exception("Not implemented");
    }
    
    ubyte[] read(size_t size)
    {
        if (size > buffer.length)
        {
            buffer.length = size;
        }
        
        ptrdiff_t sz = socket.receive(buffer[0..size]);
        switch (sz) {
        case 0:
            return null;
        case Socket.ERROR:
            throw new Exception("Socket error");
        default:
        }
        
        throw new Exception("Not implemented");
    }
    
    void send(ubyte[] data)
    {
        mutex.lock_nothrow();
        scope(exit) mutex.unlock_nothrow();

        socket.send(data); // throw allowed
    }

    bool hasData()
    {
        // Select with zero timeout for non-blocking check
        return Socket.select(set, null, null, Duration.zero) > 0;
    }

private:
    // Used to synchronize sending messages, avoids breaking messages by waiting
    // until the current message is out when there will eventually multithread
    // support.
    shared Mutex mutex;
    
    ubyte[] buffer;     // Buffer allocated for reading
    size_t bufpointer;  // Buffer pointer
    
    Socket socket;
    SocketSet set;
}