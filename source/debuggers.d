/// Base objects to implement a debugger and intermediate representation of debugging information.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module debuggers;

import types;

struct ThreadInfo
{
    int id;
    string name;
}

struct FrameInfo
{
    ulong address;
    string functionName;
    int line;
}

interface IDebugger
{
    /// Launch a new process with the debugger.
    /// Params:
    ///     exec = Path to executable.
    ///     args = Executable arguments.
    ///     cwd = Working directory for executable.
    void launch(string exec, string[] args, string cwd);
    /// Attach to process.
    /// Params: pid = Process ID.
    void attach(int pid);
    
    /// Continue debugged process.
    void continue_();
    
    /// Terminate process.
    void terminate();
    /// Detach debugger from process.
    void detach();
    
    /// Wait for debugger events.
    /// Returns: Debugger event.
    AdapterEvent wait();
}