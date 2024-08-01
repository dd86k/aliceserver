/// Line-based "HTTP-like" transport required for DAP.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module transports.httpstdio;

import std.stdio;
import std.conv;
import std.string;
import transports.base;
import logging;

/// Implements the HTTP transport, due to DAP.
class HTTPStdioTransport : ITransport
{
    ubyte[2048] buffer; // Allocated with class instance
    
    this()
    {
    }
    
    string name()
    {
        return "stdio";
    }
    
    void send(ubyte[] data)
    {
        char[64] headbuf = void;
        char[] header = sformat(headbuf[],
            "Content-Length: %u\r\n"~
            "\r\n",
            data.length);
        auto thing = stdout.lockingBinaryWriter();
        thing.rawWrite(header);
        thing.rawWrite(data);
    }
    
    // NOTE: This is written on a "per-line" basis, because stdout is a stream,
    //       the amount of data is not known in advance.
    // NOTE: This implementation assumes DAP will only have the Content-Length HTTP field.
    // TODO: Read multiple field HTTP header
    // TODO: Consider formatted read
    //       Should provide a clearer picture of our intention to parse HTTP fields.
    ubyte[] receive()
    {
        // Read one HTTP field
        string header = stdin.readln();
        if (header is null)
            throw new Exception("Got empty HTTP header");
        
        // Get field separator (':')
        ptrdiff_t fieldidx = indexOf(header, ':');
        if (fieldidx < 0)
            throw new Exception("HTTP field delimiter not found");
        
        // Check field name
        string fieldname = header[0..fieldidx];
        if (fieldname != "Content-Length")
            throw new Exception(text(`Expected field "Content-Length", got "`, fieldname, `"`));

        // Check content size, which is an integer
        size_t bodySize = to!size_t(strip( header[fieldidx + 1..$] ));
        if (bodySize < 2) // Enough for "{}"
            throw new Exception(text("Content-Length is too small, got ", bodySize));
        if (bodySize >= buffer.length)
            throw new Exception(text("Content-Length (", bodySize, ") exceeds buffer size"));
        
        // Read header-body separator line
        cast(void)stdin.readln();
        
        // Read HTTP body into internal buffer
        return stdin.rawRead(buffer[0..bodySize]);
    }
}
