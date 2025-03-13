/// Adapter interface.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapter;

public import transport : ITransport;
public import debugger  : IDebugger, DebuggerEvent;

interface IAdapter
{
    string name();
    void loop(IDebugger, ITransport);
}
