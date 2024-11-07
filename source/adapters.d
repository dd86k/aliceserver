/// Basics for defining an adapter.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapters;

public import transports : ITransport;
import types;
import debuggers;
import core.thread : Thread;
import std.datetime : Duration, dur;
import ddlogger;

/// Abstract Adapter class used to interface a protocol.
///
/// An instance of this class is incapable of interfacing with the server.
abstract class Adapter
{
    this(ITransport t)
    {
        transport = t;
    }
    
    // Get transport name.
    string transportName()
    {
        return transport.name();
    }
    
    // Send a message to client.
    void send(ubyte[] data)
    {
        // TODO: Consider mutex over transport *if* data starts getting mangled
        //       Under Phobos, standard streams have locking implemented, but
        //       when adapters starts with other transport medias, it may be
        //       interesting to use a mutex.
        logTrace("Sending %u bytes", data.length);
        transport.send(data);
    }
    // Send a message to client.
    void send(const(char)[] data)
    {
        send(cast(ubyte[])data);
    }
    
    // Receive request from client.
    ubyte[] receive()
    {
        static immutable Duration sleepTime = dur!"msecs"(2000);
    Lread:
        ubyte[] data = transport.receive();
        if (data is null)
        {
            logInfo("Got empty buffer, sleeping for %s", sleepTime);
            Thread.sleep(sleepTime);
            goto Lread;
        }
        // NOTE: So far, only two adapters are available, and are text-based
        logTrace("Received %u bytes: %s", data.length, cast(string)data);
        return data;
    }
    
    // Short name of the adapter
    abstract string name();
    // Listen for requests.
    abstract AdapterRequest listen();
    // Send a successful reply to request.
    abstract void reply(AdapterReply msg);
    // Send an error reply to request.
    abstract void reply(AdapterError msg);
    // Send an event.
    abstract void event(AdapterEvent msg);
    // Close adapter.
    abstract void close();

private:
    ITransport transport;
}