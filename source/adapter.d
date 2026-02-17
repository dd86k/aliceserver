/// Adapter interface.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapter;

public import transport : ITransport;
public import debugger  : IDebugger, DebuggerEvent;

enum
{
    ADAPTER_CONTINUE,
    ADAPTER_QUIT,
}

interface IAdapter
{
    string name();
    /// Handle one incoming request from transport. Returns ADAPTER_CONTINUE or ADAPTER_QUIT.
    int handleRequest(IDebugger debugger, ITransport transport);
    /// Format a debugger event as protocol output, send via transport.
    void sendEvent(DebuggerEvent event, ITransport transport);
}
