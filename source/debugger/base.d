/// Base objects to implement a debugger and intermediate representation of debugging information.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module debugger.base;

import adapter.types : AdapterEvent;

// TODO: BridgeDebugger
//       Basically just passes DAP/MI requests to debugger via transport.

struct ThreadInfo
{
    int id;
    string name;
}

interface IDebugger
{
    void launch(string exec, string[] args, string cwd);
    void attach(int pid);
    
    AdapterEvent wait();
}