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

// Because DAP is a special boy that needs special treatment :)
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
        stdout.rawWrite(data);
        stdout.flush();
    }

    ubyte[] receive()
    {
        // NOTE: Assuming DAP will only have the Content-Length HTTP field.
        string header = stdin.readln();
        if (header.length == 0)
            throw new Exception("Got empty HTTP header");
        cast(void)stdin.readln();

        // Get field separator (':')
        ptrdiff_t fieldidx = indexOf(header, ':');
        if (fieldidx < 0)
            throw new Exception("HTTP field delimiter not found");

        // Check field name
        string fieldname = header[0..fieldidx];
        if (fieldname != "Content-Length")
            throw new Exception(text(`Expected field "Content-Length", got "`, fieldname, `"`));

        // Check content size
        string contentlength = header[fieldidx + 1..$];
        size_t sz = to!uint(strip(contentlength));
        if (sz < 2) // Enough for "{}"
            throw new Exception(text("Content-Length is too small, got ", sz));
        if (sz >= buffer.length)
            throw new Exception(text("Content-Length (", sz, ") exceeds buffer size"));

        return stdin.rawRead(buffer[0 .. sz]);
    }
}
