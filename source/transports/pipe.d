/// Transport using Windows' NamedPipes.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module transports.pipe;

version (Windows):

import transport : ITransport;
import core.sys.windows.windef : HANDLE, DWORD, FALSE;
import core.sys.windows.winbase : ReadFile, WriteFile, PeekNamedPipe;

class NamedPipeTransport : ITransport
{
    /// Takes an already-connected pipe handle (after ConnectNamedPipe).
    this(HANDLE connectedPipe)
    {
        pipe = connectedPipe;
    }

    string name() { return "pipe"; }

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
        DWORD written;
        if (WriteFile(pipe, data.ptr, cast(DWORD)data.length, &written, null) == FALSE)
            throw new Exception("WriteFile error");
    }

    bool hasData()
    {
        // If we have unconsumed data, no need to check the socket
        if (consumed < fill)
            return true;
        DWORD available;
        if (PeekNamedPipe(pipe, null, 0, null, &available, null))
            return available > 0;
        return false;
    }

private:
    HANDLE pipe;

    ubyte[] buf;
    size_t consumed; // start of unread data
    size_t fill;     // end of valid data

    void ensureAvailable(size_t needed)
    {
        while (fill - consumed < needed)
            fillBuffer();
    }

    enum CHUNK = 4096;

    void fillBuffer()
    {
        if (fill + CHUNK > buf.length)
            buf.length = fill + CHUNK;

        DWORD read;
        if (ReadFile(pipe, buf.ptr + fill, CHUNK, &read, null) == FALSE)
            throw new Exception("ReadFile error");
        fill += read;
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
        else if (consumed > CHUNK)
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