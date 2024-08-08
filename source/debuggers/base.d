/// Base objects to implement a debugger.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module debuggers.base;

// TODO: BridgeDebugger
//       Basically just passes DAP/MI requests to debugger.

interface IDebugger
{
    void launch(string exec, string[] args, string cwd);
    void attach(int pid);
    //void attach(string exec);
    
    void go();
}