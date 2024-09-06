/// Simple line-based transport.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module transport.stdio;

import std.stdio;
import transport.base;

class StdioTransport : ITransport
{
    this()
    {
        
    }
    
    string name()
    {
        return "stdio";
    }
    
    void send(ubyte[] data)
    {
        // NOTE: rawWrite sets stdout to _O_BINARY on Windows
        stdout.rawWrite(data);
        stdout.flush();
    }
    
    ubyte[] receive()
    {
        return cast(ubyte[])readln();
    }
}