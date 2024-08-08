/// Implements a debugger using Alicedbg.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module debuggers.alicedbg;

import std.string;
import debuggers.base;
import logging;
import adbg.debugger.process;
import adbg.debugger.exception;
import adbg.error;

// TODO: Could be possible to make a "AlicedbgRemote" class for remote sessions
//       Could support multiple protocols (SSH, custom, etc.)

class Alicedbg : IDebugger
{
    void launch(string exec, string[] args, string cwd)
    {
        process = adbg_debugger_spawn(exec.toStringz(), 0);
        if (process == null)
            throw new Exception(errorMessage());
    }
    
    void attach(int pid)
    {
        process = adbg_debugger_attach(pid, 0);
        if (process == null)
            throw new Exception(errorMessage());
    }
    
    void go()
    {
        
    }
    
private:
    adbg_process_t *process;
    
    string errorMessage()
    {
        return cast(string)fromStringz(adbg_error_message());
    }
}