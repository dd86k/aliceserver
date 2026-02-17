/// Simple line-based transport.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module transports.stdio;

import std.stdio;
import transport : ITransport;

// NOTE: stdio streams in std.stdio are already synchronized
class StdioTransport : ITransport
{
    string name()
    {
        return "stdio";
    }

    ubyte[] readline()
    {
        return cast(ubyte[])stdin.readln();
    }

    ubyte[] read(size_t size)
    {
        if (size > buffer.length)
            buffer.length = size;
        return stdin.rawRead(buffer[0..size]);
    }

    void send(ubyte[] data)
    {
        // NOTE: rawWrite automatically sets stdout to _O_BINARY on Windows
        stdout.rawWrite(data);
        stdout.flush();
    }

    bool hasData()
    {
        version (Posix)
        {
            import core.sys.posix.poll : poll, pollfd, POLLIN;
            pollfd pfd;
            pfd.fd = stdin.fileno;
            pfd.events = POLLIN;
            return poll(&pfd, 1, 0) > 0;
        }
        else version (Windows)
        {
            import core.sys.windows.wincon : GetNumberOfConsoleInputEvents;
            import core.sys.windows.winbase : GetStdHandle, STD_INPUT_HANDLE;
            DWORD events;
            cast(void)GetNumberOfConsoleInputEvents(GetStdHandle(STD_INPUT_HANDLE), &events);
            return events > 0;
        }
        else
        {
            // Fallback: assume data is available (blocking behavior)
            return true;
        }
    }

private:
    ubyte[] buffer;
}
