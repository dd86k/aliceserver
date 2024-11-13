/// Adapter interface.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapters;

public import transports : ITransport;
public import debuggers;

// TODO: string[] capabilities() (for printing purposes)

interface IAdapter
{
    string name();
    void loop(IDebugger, ITransport);
    void event(ref DebuggerEvent);
}
