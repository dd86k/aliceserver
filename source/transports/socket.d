/// Socket transport for connected TCP or Unix sockets.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module transports.socket;

public import std.socket;
import transport : ITransport;
import core.time : Duration;

/// Wraps an already-connected socket as an ITransport.
class SocketTransport : ITransport
{
    /// Takes an already-connected socket (e.g. from accept()).
    this(Socket sock)
    {
        socket = sock;
        set = new SocketSet(4); // defaults to FD_SETSIZE=64 (Windows
    }

    string name() { return "socket"; }

    ubyte[] readline()
    {
        // Scan for newline in buffered data, fetching more as needed
        while (true)
        {
            // Search existing buffered data for a newline
            foreach (i, b; buf[consumed .. fill])
            {
                if (b == '\n')
                {
                    size_t lineEnd = consumed + i; // index of '\n'
                    ubyte[] line = buf[consumed .. lineEnd];
                    consumed = lineEnd + 1; // skip past '\n'
                    compactBuffer();
                    return line;
                }
            }
            // No newline found yet — read more data
            fillBuffer();
        }
    }

    ubyte[] read(size_t size)
    {
        ensureAvailable(size);
        ubyte[] result = buf[consumed .. consumed + size];
        consumed += size;
        compactBuffer();
        return result;
    }

    void send(ubyte[] data)
    {
        socket.send(data);
    }

    bool hasData()
    {
        // If we have unconsumed data, no need to check the socket
        if (consumed < fill)
            return true;
        // reset+add is cheaper than re-creating SocketSet due to .length=size
        set.reset();
        set.add(socket);
        return Socket.select(set, null, null, Duration.zero) > 0;
    }

private:
    Socket socket;
    SocketSet set;

    ubyte[] buf;
    size_t consumed; // start of unread data
    size_t fill;     // end of valid data

    void ensureAvailable(size_t needed)
    {
        while (fill - consumed < needed)
            fillBuffer();
    }

    void fillBuffer()
    {
        enum CHUNK = 4096;
        if (fill + CHUNK > buf.length)
            buf.length = fill + CHUNK;

        ptrdiff_t n = socket.receive(buf[fill .. fill + CHUNK]);
        if (n == 0)
            throw new Exception("Socket closed by remote end");
        if (n == Socket.ERROR)
            throw new Exception("Socket receive error");
        fill += n;
    }

    void compactBuffer()
    {
        if (consumed == 0)
            return;
        if (consumed == fill)
        {
            consumed = 0;
            fill = 0;
        }
        else if (consumed > 4096)
        {
            // Shift remaining data to front to avoid unbounded growth
            import core.stdc.string : memmove;
            size_t remaining = fill - consumed;
            memmove(buf.ptr, buf.ptr + consumed, remaining);
            fill = remaining;
            consumed = 0;
        }
    }
}
