/// Mock implementations of ITransport and IDebugger for unit testing.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module testing;

import transport : ITransport;
import debugger;

/// Mock transport that records sent data and provides canned input.
///
/// Feed input via `feedLine()` and `feedBytes()`. Read what the adapter
/// sent via `sent[]`.
class MockTransport : ITransport
{
    string name() { return "mock"; }

    /// Queue a line to be returned by `readline()`.
    /// The `\r\n` terminator is appended automatically.
    void feedLine(string line)
    {
        queuedLines ~= line;
    }

    /// Queue raw bytes to be returned by `read()`.
    void feedBytes(ubyte[] data)
    {
        queuedBytes ~= data;
    }

    ubyte[] readline()
    {
        if (lineIdx < queuedLines.length)
        {
            string line = queuedLines[lineIdx++];
            return cast(ubyte[])(line ~ "\r\n");
        }
        // Return empty line (header terminator for DAP)
        return cast(ubyte[])"\r\n";
    }

    ubyte[] read(size_t size)
    {
        if (queuedBytes.length >= size)
        {
            ubyte[] result = queuedBytes[0 .. size].dup;
            queuedBytes = queuedBytes[size .. $];
            return result;
        }
        // Return whatever is available
        ubyte[] result = queuedBytes.dup;
        queuedBytes = null;
        return result;
    }

    void send(ubyte[] data)
    {
        sent ~= cast(string)data.idup;
    }

    bool hasData()
    {
        return lineIdx < queuedLines.length || queuedBytes.length > 0;
    }

    /// All data sent by the adapter, as strings, in order.
    string[] sent;

    /// Concatenated sent data.
    string sentData()
    {
        string result;
        foreach (s; sent)
            result ~= s;
        return result;
    }

private:
    string[] queuedLines;
    size_t lineIdx;
    ubyte[] queuedBytes;
}

unittest
{
    auto t = new MockTransport();
    t.feedLine("Content-Length: 5");
    assert(cast(string)t.readline() == "Content-Length: 5\r\n");
    // Next readline returns empty (header terminator)
    assert(cast(string)t.readline() == "\r\n");

    t.feedBytes(cast(ubyte[])"hello");
    assert(cast(string)t.read(5) == "hello");

    t.send(cast(ubyte[])"world");
    assert(t.sent[0] == "world");
}

/// Mock debugger that records method calls and provides configurable responses.
class MockDebugger : IDebugger
{
    /// Record of a method call made to the mock.
    struct Call
    {
        string method;
        string[] args;
    }

    /// All calls recorded, in order.
    Call[] calls;

    // --- Configurable responses ---
    bool attachedValue = false;
    int[] threadsValue;
    DebuggerFrameInfo frameValue;
    DebuggerEvent[] eventsValue;

    void launch(string exec, string[] args, string cwd)
    {
        calls ~= Call("launch", [exec]);
    }

    void attach(int pid)
    {
        import std.conv : text;
        calls ~= Call("attach", [text(pid)]);
    }

    bool attached()
    {
        calls ~= Call("attached");
        return attachedValue;
    }

    void terminate()
    {
        calls ~= Call("terminate");
    }

    void detach()
    {
        calls ~= Call("detach");
    }

    void pause()
    {
        calls ~= Call("pause");
    }

    void continueThread(int tid)
    {
        import std.conv : text;
        calls ~= Call("continueThread", [text(tid)]);
    }

    int[] threads()
    {
        calls ~= Call("threads");
        return threadsValue;
    }

    DebuggerFrameInfo frame(int tid)
    {
        import std.conv : text;
        calls ~= Call("frame", [text(tid)]);
        return frameValue;
    }

    DebuggerEvent[] pollEvents()
    {
        calls ~= Call("pollEvents");
        return eventsValue;
    }

    /// Check if a method was called at least once.
    bool wasCalled(string method)
    {
        foreach (c; calls)
            if (c.method == method)
                return true;
        return false;
    }
}

unittest
{
    auto d = new MockDebugger();
    d.launch("/bin/test", null, null);
    assert(d.calls.length == 1);
    assert(d.calls[0].method == "launch");
    assert(d.calls[0].args == ["/bin/test"]);
    assert(d.wasCalled("launch"));
    assert(!d.wasCalled("attach"));
}
