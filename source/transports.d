/// Transport interface.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module transports;

interface ITransport
{
    string name();
    void send(ubyte[]);
    ubyte[] receive();
}
