/// Transport interface.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module transport;

interface ITransport
{
    string name();
    ubyte[] readline();
    ubyte[] read(size_t size);
    void send(ubyte[]);
}
