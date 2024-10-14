/// Transport interface.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module transport.base;

// TODO: Consider moving whole transport folder into adapter

interface ITransport
{
    string name();
    void send(ubyte[]);
    ubyte[] receive();
}
