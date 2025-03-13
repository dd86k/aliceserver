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
    
private:
    ubyte[] buffer;
}