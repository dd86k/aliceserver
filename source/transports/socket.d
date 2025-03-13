/// Simple line-based transport.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module transports.socket;

public import std.socket;
import transport : ITransport;
import core.sync.mutex;

// NOTE: Sockets are not synchronized and thus need the mutex
class SocketTransport : ITransport
{
    this(Socket socket)
    {
        sock = socket;
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
        
        ptrdiff_t sz = sock.receive(buffer[0..size]);
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
        
        sock.send(data); // throw allowed
    }

private:
    // Used to synchronize sending messages, avoids breaking messages by waiting
    // until the current message is out when there will eventually multithread
    // support.
    shared Mutex mutex;
    
    ubyte[] buffer;     // Buffer allocated for reading
    size_t bufpointer;  // Buffer pointer
    
    Socket sock;
}