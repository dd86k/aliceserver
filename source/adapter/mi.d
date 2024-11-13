/// GDB/MI adapter.
///
/// Reference:
/// - https://ftp.gnu.org/old-gnu/Manuals/gdb/html_chapter/gdb_22.html
/// - https://sourceware.org/gdb/current/onlinedocs/gdb.html/GDB_002fMI.html
/// - https://github.com/lldb-tools/lldb-mi
/// - gdb: gdb/mi
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapter.mi;

import adapters;
import config;
import logging;
import server : AdapterType;
import std.array : replace;
import std.ascii;
import std.conv : to;
import std.format : format;
import std.string : indexOf;
import std.outbuffer : OutBuffer;
import std.string : stripRight;
import util.shell : shellArgs;

// NOTE: GDB/MI versions and commmands
//
//       The most important aspect to be as close to GDB as possible, since LLVM
//       does not distribute compiled llvm-mi binaries anymore, I believe many either
//       switched to gdb-mi or llvm-vscode.
//
//       Handling version variants is currently a work in progress. But right now,
//       it has no significance of its own. When "mi" is specified, GDB defaults to
//       the latest version: "Since --interpreter=mi always points to the latest MI version,"
//       And since there is no way to specify MI version 1, it will not be implemented.
//
//       MI   GDB  Breaking changes
//        1   5.1
//        2   6.0  - -environment-pwd, -environment-directory and -environment-path
//                   commands now returns values using the MI output syntax, rather
//                   than CLI output syntax.
//                 - -var-list-children's children result field is now a list,
//                   rather than a tuple.
//                 - -var-update's changelist result field is now a list,
//                   rather than a tuple. 
//        3   9.1  - The output of information about multi-location breakpoints has
//                   changed in the responses to the -break-insert and -break-info
//                   commands, as well as in the =breakpoint-created and =breakpoint-modified
//                   events. The multiple locations are now placed in a locations field,
//                   whose value is a list. 
//        4  13.1  - The syntax of the "script" field in breakpoint output has changed
//                   in the responses to the -break-insert and -break-info commands,
//                   as well as the =breakpoint-created and =breakpoint-modified events.
//                   The previous output was syntactically invalid. The new output is a list.
//
//       mi-async 1 (target-async in <= gdb 7.7)
//
//       Distro      GDBVer  MIVer
//       Debian  6      7.0      2
//       Debian  7      7.4      2
//       Debian  8      7.7      2
//       Debian  9     7.12      2
//       Debian 10      8.2      2
//       Debian 11     10.1      3
//       Debian 12     13.1      4

// NOTE: code-debug
//
//       Launching GDB
//         On Win32 platforms:
//           - `file-exec-and-symbols` for file path and symbols (?)
//           - if separateConsole is defined: `gdb-set new-console on`.
//           - `exec-run` (+ `--start`)
//
//       On Linux, if separateConsole is defined, `inferior-tty-set TTY` is executed.

/*enum MIKind : char
{
    // Replies
    // "running" (exec running), "done" (task performed successfully),
    result = '^',
    
    // Events (Async record types)
    exec = '*', // execution state changed: "stopped" or other message
    notify = '=', // notification: "stopped" or other message
    asyncStatus = '+', // async status: "stopped" or other message
    
    // Stream record (informative)
    // "exit" (quit), "error" (task failed), "connected" (?),
    console = '~', // terminal output
    targetStream = '@', // 
    logStream = '&', // echoes commands
    
    // Input
    command = '-',
}*/

private immutable string gdbPrompt = "(gdb)\n";
private immutable string msgDone = "^done\n";
private immutable string msgRunning = "^running\n";

/*
private
string parseCString(string cstr)
{
    return "";
}
*/

// TODO: To 7-bit ASCII, so special chars/bytes should be escaped
private
string formatCString(A...)(string fmt, A args)
{
    return format(fmt, args)
        .replace(`"`, `\"`)
        .replace("\n", `\n`);
}
unittest
{
    assert(formatCString("Thing: \"hi\"\n") == `Thing: \"hi\"\n`);
}

final class MIAdapter : IAdapter
{
    private enum
    {
        CONTINUE,
        QUIT,
    }
    
    this(AdapterType miver)
    {
        switch (miver) with (AdapterType) {
        case mi:  goto case mi4;
        case mi2: miversion = 2; break;
        case mi3: miversion = 3; break;
        case mi4: miversion = 4; break;
        default:
            throw new Exception("Unsupported MI version");
        }
        
        // TODO: Implement these commands
        //       - -exec-finish: functionOut
        //       - -exec-next: nextLine
        //       - -exec-interrupt: pause
        //       - -exec-step: instructionStep
        //       - -exec-continue: continue
        //       - -exec-interrupt [--all|--thread-group N]: pause
        //       - -exec-jump LOCSPEC: continue example.c:10
        //       - -exec-show-arguments
        //       - mi-async
        //       - gdb-set: For example, "gdb-set target-async on"
        //       - break-insert: insert breakpoint
        //       - break-condition: change condition to breakpoint
        //       - file-exec-and-symbols: set exec and symbols
        //       - goto: break-insert -t TARGET or exec-jump TARGET
        // Command list: gdb/mi/mi-cmds.c
        
        // -exec-run [ --all | --thread-group N ] [ --start ]
        // Start execution of target process.
        //   --all: Start all target subprocesses
        //   --thread-group: Start only thread group (of type process) for target process
        //   --start: Stop at target's main function.
        commands["exec-run"] =
        commands["exec"] =
        (string[] args) {
            // TODO: run events
            success(`^running`);
            return CONTINUE;
        };
        // Resume process execution from a stopped state.
        commands["exec-continue"] =
        commands["continue"] =
        (string[] args) {
            debugger.continue_(current_tid);
            return CONTINUE;
        };
        // Terminate process.
        commands["exec-abort"] =
        (string[] args) {
            debugger.terminate();
            return QUIT;
        };
        // attach PID
        // Attach debugger to process by its ID.
        commands["target-attach"] =
        commands["attach"] =
        (string[] args) {
            if (args.length < 1)
            {
                error("Missing process-id argument.");
                return CONTINUE;
            }
            
            string pidstr = args[0];
            int pid = void;
            try pid = to!int(pidstr);
            catch (Exception ex)
            {
                error(text("Illegal process id: '", pidstr, "'."));
                return CONTINUE;
            }
            
            debugger.attach(pid);
            // TODO: run events
            success(`^running`);
            return CONTINUE;
        };
        // -gdb-detach [ pid | gid ]
        // Detach debugger from process, keeping its execution alive.
        commands["target-detach"] =
        commands["gdb-detach"] =
        commands["detach"] =
        (string[] args) {
            debugger.detach();
            return CONTINUE;
        };
        // -target-disconnect
        // Disconnect from remote target.
        commands["target-disconnect"] =
        (string[] args) {
            debugger.detach();
            return CONTINUE;
        };
        // target TYPE [OPTIONS]
        // Set target parameters.
        commands["target"] =
        (string[] args) {
            if (args.length < 1)
            {
                error("Need target type");
                return CONTINUE;
            }
            
            string targetType = args[0];
            switch (targetType) {
            case "exec":
                if (args.length < 2)
                {
                    error("Need target executable path");
                    return CONTINUE;
                }
                
                exec_path = args[1].dup;
                success();
                break;
            default:
                error(text("Invalid target type: ", targetType));
            }
            return CONTINUE;
        };
        // file-exec-and-symbols PATH
        // (gdb, lldb) Set target path and symbols as the same
        commands["file-exec-and-symbols"] =
        (string[] args) {
            if (args.length < 1)
            {
                error("Need target executable path");
                return CONTINUE;
            }
            
            exec_path = args[0].dup;
            success();
            return CONTINUE;
        };
        // -exec-arguments ARGS
        // Set target arguments.
        commands["exec-arguments"] =
        (string[] args) {
            // If arguments given, set, otherwise, clear.
            exec_args = args.length > 0 ? args[0..$].dup : null;
            success();
            return CONTINUE;
        };
        // -environment-cd PATH
        // Set debugger directory.
        commands["exec-arguments"] =
        (string[] args) {
            if (args.length < 1)
            {
                error("Missing directory path.");
                return CONTINUE;
            }
            
            // NOTE: Ultimately, the server should be the one controlling these requests
            /* TODO: -environment-cd
            try chdir(args[0]);
            catch (Exception ex)
            {
                reply(AdapterError(ex.msg));
                return SKIP;
            }
            */
            
            success();
            return CONTINUE;
        };
        // -thread-info [TID]
        // Get a list of thread and information associated with each thread.
        // Or only a single thread.
        // Example:
        // -thread-info
        // ^done,threads=[
        // {id="2",target-id="Thread 0xb7e14b90 (LWP 21257)",
        //    frame={level="0",addr="0xffffe410",func="__kernel_vsyscall",
        //            args=[]},state="running"},
        // {id="1",target-id="Thread 0xb7e156b0 (LWP 21254)",
        //    frame={level="0",addr="0x0804891f",func="foo",
        //            args=[{name="i",value="10"}],
        //            file="/tmp/a.c",fullname="/tmp/a.c",line="158",arch="i386:x86_64"},
        //            state="running"}],
        // current-thread-id="1"
        // https://sourceware.org/gdb/current/onlinedocs/gdb.html/GDB_002fMI-Thread-Information.html
        // Thread Information:
        // - id: The global numeric id assigned to the thread by GDB.
        // - target-id: The target-specific string identifying the thread.
        // - details: Additional information about the thread provided by the target.
        //   It is supposed to be human-readable and not interpreted by the frontend.
        //   This field is optional.
        // - name: The name of the thread.
        //   If the user specified a name using the thread name command, then
        //   this name is given. Otherwise, if GDB can extract the thread name
        //   from the target, then that name is given. If GDB cannot find the
        //   thread name, then this field is omitted.
        // - state: The execution state of the thread, either ‘stopped’ or ‘running’,
        //   depending on whether the thread is presently running.
        // - frame: Frame information
        // - core: The value of this field is an integer number of the processor
        //   core the thread was last seen on. This field is optional.
        commands["thread-info"] =
        (string[] args) {
            assert(false, "todo");
        };
        // show [INFO]
        // Show information about session.
        // Without an argument, GDB shows everything as stream output and
        // quits without sending a reply nor the prompt.
        commands["show"] =
        (string[] args) {
            if (args.length < 1)
            {
                success();
                return CONTINUE;
            }
            
            string showCommand = args[0];
            switch (showCommand) {
            case "version":
                static immutable string APPVERSION = "~\"Aliceserver "~PROJECT_VERSION~"\\n\"\n";
                transport.send(cast(ubyte[])APPVERSION);
                success();
                return CONTINUE;
            default:
            }
            
            error(text(`Unknown show command: '`, showCommand, `'`));
            return CONTINUE;
        };
        // -info-gdb-mi-command COMMAND
        // Sends information about the MI command, if it exists.
        // Example:
        //   -info-gdb-mi-command show
        //   ^done,command={exists="false"} 
        // NOTE: While regular commands work in MI, these will "not exist" in the MI sense
        //       In anyway, saying that the commands exist is not GDB/MI compliant, but
        //       at least removes some hurdles.
        commands["info-gdb-mi-command"] =
        (string[] args) {
            if (args.length < 1)
            {
                error("Usage: -info-gdb-mi-command MI_COMMAND_NAME");
                return CONTINUE;
            }
            MIValue command;
            command["exists"] = cast(bool)((args[0] in commands) != null);
            MIValue m;
            m["command"] = command;
            success(m);
            return CONTINUE;
        };
        // -list-features
        // List debugger features
        // gdb 13.1 example: ^done,features=["example","python"]
        // Features (noted 2024-11-13, see §27.23 GDB/MI Support Commands):
        // frozen-varobjs
        //   Indicates support for the -var-set-frozen command, as well as
        //   possible presence of the frozen field in the output of -varobj-create.
        // pending-breakpoints
        //   Indicates support for the -f option to the -break-insert command.
        // python
        //   Indicates Python scripting support, Python-based pretty-printing
        //   commands, and possible presence of the ‘display_hint’ field in the
        //   output of -var-list-children 
        // thread-info
        //   Indicates support for the -thread-info command. 
        // data-read-memory-bytes
        //   Indicates support for the -data-read-memory-bytes and the
        //   -data-write-memory-bytes commands.
        // breakpoint-notifications
        //   Indicates that changes to breakpoints and breakpoints created
        //   via the CLI will be announced via async records.
        // ada-task-info
        //   Indicates support for the -ada-task-info command. 
        // language-option
        //   Indicates that all GDB/MI commands accept the --language option.
        // info-gdb-mi-command
        //   Indicates support for the -info-gdb-mi-command command.
        // undefined-command-error-code
        //   Indicates support for the "undefined-command" error code in error
        //   result records, produced when trying to execute an undefined GDB/MI
        //   command (see GDB/MI Result Records). 
        // exec-run-start-option
        //   Indicates that the -exec-run command supports the --start option
        //   (see GDB/MI Program Execution).
        // data-disassemble-a-option
        //   Indicates that the -data-disassemble command supports the -a option
        //   (see GDB/MI Data Manipulation). 
        // simple-values-ref-types
        //   Indicates that the --simple-values argument to the -stack-list-arguments,
        //   -stack-list-locals, -stack-list-variables, and -var-list-children commands
        //   takes reference types into account: that is, a value is considered simple
        //   if it is neither an array, structure, or union, nor a reference to an
        //   array, structure, or union. 
        commands["list-features"] =
        (string[] args) {
            transport.send(cast(ubyte[])"^done,features=[]\n");
            return CONTINUE;
        };
        // Ignore list
        commands["gdb-set"] =
        commands["inferior-tty-set"] =
        (string[] args) { return CONTINUE; };
        // Close debugger instance
        commands["gdb-exit"] =
        commands["quit"] =
        commands["q"] =
        (string[] args) {
            // NOTE: gdb-mi when attached does not terminate.
            //       Therefore, the preference is not to terminate.
            return QUIT;
        };
    }
    
    // Return short name of this adapter
    string name()
    {
        final switch (miversion) {
        case 4: return "mi4";
        case 3: return "mi3";
        case 2: return "mi2";
        }
    }
    
    void loop(IDebugger d, ITransport t)
    {
        debugger = d;
        transport = t;
        
        debugger.hook(&event);
        
        // OutBufer .clear() sets offset to 0
        // Appender .clear() clears all data
        scope OutBuffer tracebuf = new OutBuffer();
        tracebuf.reserve(512);
        
        outbuf = new OutBuffer();
        outbuf.reserve(1024);
        errbuf = new OutBuffer();
        errbuf.reserve(1024);
        
    Lread:
        sendPrompt(); // Ready!
        string fullrequest = cast(string)transport.readline();
        
        // Parse request
        request = parseMIRequest(fullrequest);
        
        // GDB sends the trace of the command as an event
        // NOTE: GDB behavior on traces
        //       Seem to be on "shell" commands (and not MI commands)
        //       Does:    "q", "quit", "i-dont-exist"
        //       Doesn't: "-gdb-exit", "-info-gdb-mi-command", "-i-dont-exist"
        if (request.line && request.line[0] != '-')
        {
            tracebuf.clear();
            tracebuf.write("&\"");
            tracebuf.write( formatCString(request.line) );
            tracebuf.write("\"\n");
            transport.send(tracebuf.toBytes());
        }
        
        // GDB behavior:
        // - "":    valid
        // - "-":   invalid (not found)
        // - "22":  valid
        // - "22-": invalid (not found)
        // - "22 help": valid
        if (request.name == "\n") // command parser removes "-"
        {
            success();
            goto Lread;
        }
        
        // Command exists, get request out of that
        int delegate(string[])* fq = request.name in commands;
        if (fq == null)
        {
            error(text(`Unknown request: "`, request.name, `"`));
            goto Lread;
        }
        
        try if ((*fq)(request.args) == QUIT)
            return;
        catch (Exception ex)
            error(ex.msg);
        goto Lread;
    }
    
    void event(ref DebuggerEvent event)
    {
        switch (event.type) with (DebuggerEventType) {
        // - ~"Starting program: example.exe \n"
        // - =library-loaded,id="C:\\WINDOWS\\SYSTEM32\\ntdll.dll",
        //   target-name="C:\\WINDOWS\\SYSTEM32\\ntdll.dll",
        //   host-name="C:\\WINDOWS\\SYSTEM32\\ntdll.dll",
        //   symbols-loaded="0",
        //   thread-group="i1",
        //   ranges=[{from="0x00007ff8f8731000",to="0x00007ff8f8946628"}]
        /*case output:
            send(format("~\"%s\"\n", formatCString( msg. )));
            break;*/
        // - *running,thread-id="all"
        case continued:
            transport.send(cast(ubyte[])"*running\n");
            break;
        // - *stopped,reason="breakpoint-hit",disp="keep",bkptno="1",thread-id="0",
        //   frame={addr="0x08048564",func="main",
        //   args=[{name="argc",value="1"},{name="argv",value="0xbfc4d4d4"}],
        //   file="myprog.c",fullname="/home/nickrob/myprog.c",line="68",
        //   arch="i386:x86_64"}
        // - *stopped,reason="signal-received",signal-name="SIGSEGV",
        //   signal-meaning="Segmentation fault",frame={addr="0x0000000000000000",
        //   func="??",args=[],arch="i386:x86-64"},thread-id="1",stopped-threads="all"
        // - *stopped,reason="exited-signalled",signal-name="SIGINT",signal-meaning="Interrupt"
        case stopped:
            MIValue miframe;
            try
            {
                DebuggerFrameInfo frame = debugger.frame(event.stopped.threadId);
                miframe["addr"] = format("%#x", frame.address);
                miframe["func"] = frame.funcname ? frame.funcname : "??";
                miframe["args"] = frame.funcargs;
                miframe["arch"] = toMIArch(frame.arch);
            }
            catch (Exception ex)
            {
                // Frame info unavailable, but MI requires it
                miframe["addr"] = "0x0";
                miframe["func"] = "??";
                miframe["args"] = [];
                miframe["arch"] = toMIArch( TARGET_ARCH );
            }
            
            MIValue mi;
            mi["reason"] = toMIStoppedReason(event.stopped.reason);
            mi["signal-name"] = toMISignalName(event.stopped.fault);
            mi["signal-meaning"] = toMISignalDesc(event.stopped.fault);
            mi["frame"] = miframe;
            mi["thread-id"] = event.stopped.threadId;
            mi["stopped-threads"] = "all";
            transport.send(cast(ubyte[])mi.toMessage("*stopped"));
            break;
        // - *stopped,reason="exited-normally"
        // - *stopped,reason="exited",exit-code="01"
        case exited:
            MIValue m;
            if (event.exited.code)
            {
                m["reason"] = "exited";
                // TODO: Check if exit-code is octal since it has a 0 prefix
                m["exit-code"] = event.exited.code;
            }
            else
                m["reason"] = "exited-normally";
            
            transport.send(cast(ubyte[])m.toMessage("*stopped"));
            break;
        default:
            logWarn("Unimplemented event type: %s", event.type);
        }
    }
    
private:
    ITransport transport;
    IDebugger debugger;
    // NOTE: Virtual functions inside a constructor may lead to unexpected results
    //       in the derived classes - At leat marking the class as final prevents this
    /// AA of implemented commands
    int delegate(string[] args)[string] commands;
    /// Current request
    MIRequest request;
    /// 
    int current_tid;
    /// Current MI version in use
    int miversion;
    
    string exec_path;
    string[] exec_args;
    string exec_dir;
    
    OutBuffer outbuf;
    OutBuffer errbuf;
    
    void sendPrompt()
    {
        transport.send(cast(ubyte[])"(gdb)\n");
    }
    
    void success(string prefix = null)
    {
        outbuf.clear();
        
        // Attach token id to result record
        if (request.id)
            outbuf.write(text(request.id));
        
        // launch and attach requests have "^running" instead of "^done"
        outbuf.write(prefix ? prefix : "^done");
        outbuf.write('\n');
        
        transport.send(outbuf.toBytes());
    }
    
    void success(ref MIValue m)
    {
        outbuf.clear();
        
        // Attach token id to result record
        if (request.id)
            outbuf.write(text(request.id));
        
        outbuf.write("^done,");
        outbuf.write(m.toString());
        outbuf.write('\n');
        
        transport.send(outbuf.toBytes());
    }
    
    void error(string message)
    {
        logError(message);
        
        errbuf.clear();
        
        // 123^error,msg="Undefined command: \"test\"."\n
        if (request.id) errbuf.write(text(request.id));
        errbuf.write("^error,msg=\"");
        errbuf.write( formatCString(message) );
        errbuf.write("\"\n");
        
        transport.send(errbuf.toBytes());
    }
}

private:

deprecated
string toMessage(string prefix, MIValue miobj)
{
    return prefix~","~miobj.toString()~"\n";
}

string toMIArch(Architecture arch)
{
    // objdump: supported architectures: i386 i386:x86-64 i386:x64-32 i8086 i386:intel
    // i386:x86-64:intel i386:x64-32:intel iamcu iamcu:intel aarch64 aarch64:llp64
    // aarch64:ilp32 aarch64:armv8-r arm armv2 armv2a armv3 armv3m armv4 armv4t armv5
    // armv5t armv5te xscale ep9312 iwmmxt iwmmxt2 armv5tej armv6 armv6kz armv6t2 armv6k
    // armv7 armv6-m armv6s-m armv7e-m armv8-a armv8-r armv8-m.base armv8-m.main
    // armv8.1-m.main armv9-a arm_any
    final switch (arch) {
    case Architecture.i386:     return "i386";
    case Architecture.x86_64:   return "i386:x86_64";
    case Architecture.AArch32:  return "arm";
    case Architecture.AArch64:  return "aarch64";
    }
}

string toMIStoppedReason(DebuggerStopReason reason)
{
    final switch (reason) with (DebuggerStopReason) {
    case step:
        return "step";
    case breakpoint:
        return "breakpoint-hit";
    case exception:
        return "signal-received";
    case pause:
    case entry:
    case goto_:
    case functionBreakpoint:
    case dataBreakpoint:
    case instructionBreakpoint:
        return "unknown";
    }
}

string toMISignalName(DebuggerExceptionType ex)
{
    switch (ex) with (DebuggerExceptionType) {
    case accessViolation:
        return "SIGSEGV";
    default:
        return "unknown";
    }
}

string toMISignalDesc(DebuggerExceptionType ex)
{
    switch (ex) with (DebuggerExceptionType) {
    case accessViolation:
        return "Segmentation fault";
    default:
        return "unknown";
    }
}

struct MIRequest
{
    uint id;        /// Request ID
    
    // I don't know why I separated command name from the list of arguments,
    // maybe I saw some sort of appeal as a name of a function with its
    // parameters?
    string name;    /// Command name
    string[] args;  /// Command arguments
    
    string line;    /// Full command line, without request ID
}

/// Parse the command 
// Throws: ConvOverflowException from `to` template
MIRequest parseMIRequest(string command)
{
    MIRequest mi;
    
    // TODO: Background syntax
    //       "example&"
    //       bool background;
    
    // Skip space characters
    
    // Attempt to get ID from command
    // Examples:
    // - "0e" -> 0 (but probably not a good idea)
    // - "123abc" -> 123
    // - "1-do-thing" -> 1
    size_t i;               // ID buffer index
    char[10] idbuf = void;  // ID buffer
    while (i < command.length && i < idbuf.sizeof && isDigit(command[i]))
    {
        idbuf[i] = command[i]; i++;
    }
    
    // Parse id if there is one in the buffer
    if (i)
    {
        mi.id      = to!int(idbuf[0..i]);
        command    = command[i..$];
    }
    
    // GDB/MI §27.23: "Note that the dash (-) starting all GDB/MI commands is
    //                 technically not part of the command name"
    if (command.length && command[0] == '-')
        command = command[1..$];
    
    // Full command line excludes request id
    mi.line = command;
    
    // Split arguments, if there are any
    string[] args = shellArgs(command);
    if (args)
    {
        mi.name = args[0];
        mi.args = args[1..$];
    }
    else // Could not split arguments
    {
        mi.name = command;
        mi.args = [];
    }
    
    // Newline must be in full line, but not in last argument...
    if (mi.args.length)
        mi.args[$-1] = mi.args[$-1].stripRight();
    
    return mi;
}
unittest
{
    MIRequest mi = parseMIRequest(`example`);
    assert(mi.id   == 0);
    assert(mi.name == "example");
    assert(mi.args == []);
    assert(mi.line == "example");
    
    mi = parseMIRequest(`-file-exec-and-symbols`);
    assert(mi.id   == 0);
    assert(mi.name == "file-exec-and-symbols");
    assert(mi.args == []);
    assert(mi.line == "file-exec-and-symbols");
    
    mi = parseMIRequest(`123example`);
    assert(mi.id   == 123);
    assert(mi.name == "example");
    assert(mi.args == []);
    assert(mi.line == "example");
    
    mi = parseMIRequest(`1-file-exec-and-symbols`);
    assert(mi.id   == 1);
    assert(mi.name == "file-exec-and-symbols");
    assert(mi.args == []);
    assert(mi.line == "file-exec-and-symbols");
    
    mi = parseMIRequest(`2-command argument`);
    assert(mi.id   == 2);
    assert(mi.name == "command");
    assert(mi.args == [ "argument" ]);
    assert(mi.line == "command argument");
    
    mi = parseMIRequest(`3-command argument "big argument"`);
    assert(mi.id   == 3);
    assert(mi.name == "command");
    assert(mi.args == [ "argument", "big argument" ]);
    assert(mi.line == `command argument "big argument"`);
    
    // Test malformed requests
    //
    // Currently, supporting commands with whitespaces before the command name
    // is not a priority.
    
    mi = parseMIRequest(``);
    assert(mi.id   == 0);
    assert(mi.name == "");
    assert(mi.args == []);
    assert(mi.line == "");
    
    /*
    mi = parseMIRequest(`    uh oh`);
    assert(mi.id   == 0);
    assert(mi.name == "uh");
    assert(mi.args == [ "oh" ]);
    assert(mi.line == "uh oh");
    
    mi = parseMIRequest(` -oh no`);
    assert(mi.id   == 0);
    assert(mi.name == "oh");
    assert(mi.args == [ "no" ]);
    assert(mi.line == "oh no");
    
    mi = parseMIRequest(`44- uh oh`);
    assert(mi.id   == 44);
    assert(mi.name == "");
    assert(mi.args is null);
    */
    
    mi = parseMIRequest(`-`);
    assert(mi.id   == 0);
    assert(mi.name == "");
    assert(mi.args == []);
    assert(mi.line == "");
    
    mi = parseMIRequest(`22`);
    assert(mi.id   == 22);
    assert(mi.name == "");
    assert(mi.args is null);
    
    mi = parseMIRequest(`33-`);
    assert(mi.id   == 33);
    assert(mi.name == "");
    assert(mi.args is null);
}

import std.array : Appender, appender; // std.json uses this for toString()
import std.conv : text;
import std.traits : isArray;

enum MIType : ubyte
{
    null_,
    string_,
    boolean_,
    
    integer,
    uinteger,
    floating,
    
    object_,
    array,
}

struct MIValue
{
    string str()
    {
        if (type != MIType.string_)
            throw new Exception(text("Not a string, it is ", type));
        return store.string_;
    }
    string str(string v)
    {
        type = MIType.string_;
        return store.string_ = v;
    }
    
    bool boolean()
    {
        if (type != MIType.boolean_)
            throw new Exception(text("Not a boolean, it is ", type));
        return store.boolean;
    }
    bool boolean(bool v)
    {
        type = MIType.boolean_;
        return store.boolean = v;
    }
    
    long integer()
    {
        if (type != MIType.integer)
            throw new Exception(text("Not an integer, it is ", type));
        return store.integer;
    }
    long integer(long v)
    {
        type = MIType.integer;
        return store.integer = v;
    }
    
    // Get value by index
    ref typeof(this) opIndex(return scope string key)
    {
        if (type != MIType.object_)
            throw new Exception(text("Attempted to index non-object, it is ", type));
        
        if ((key in store.object_) is null)
            throw new Exception(text("Value not found with key '", key, "'"));
        
        return store.object_[key];
    }
    
    // Set value by key index
    void opIndexAssign(T)(auto ref T value, string key)
    {
        // Only objects can have properties set in them
        switch (type) with (MIType) {
        case object_, null_: break;
        default: throw new Exception(text("MIValue must be object or null, it is ", type));
        }
        
        MIValue mi = void;
        
        static if (is(T : typeof(null)))
        {
            mi.type = MIType.null_;
        }
        else static if (is(T : string))
        {
            mi.type = MIType.string_;
            mi.store.string_ = value;
        }
        else static if (is(T : bool)) // Avoid int-promotion stunts
        {
            mi.type = MIType.boolean_;
            mi.store.boolean = value;
        }
        else static if (is(T : int) || is(T : long))
        {
            mi.type = MIType.integer;
            mi.store.integer = value;
        }
        else static if (is(T : uint) || is(T : ulong))
        {
            mi.type = MIType.uinteger;
            mi.store.uinteger = value;
        }
        else static if (is(T : float) || is(T : double))
        {
            mi.type = MIType.floating;
            mi.store.floating = value;
        }
        else static if (isArray!T)
        {
            mi.type = MIType.array;
            static if (is(T : void[]))
            {
                mi.store.array = []; // empty MIValue[]
            }
            else
            {
                MIValue[] values = new MIValue[value.length];
                foreach (i, v; value)
                {
                    values[i] = v;
                }
                mi.store.array = values;
            }
        }
        else static if (is(T : MIValue))
        {
            mi = value;
        }
        else static assert(false, "Not implemented for type "~T.stringof);
        
        type = MIType.object_;
        store.object_[key] = mi;
    }
    
    string toString() const
    {
        // NOTE: Formatting MI is similar to JSON, except:
        //       - Field names are not surrounded by quotes
        //       - All values are string-formatted
        //       - Root level has no base type
        switch (type) with (MIType) {
        case string_:
            return store.string_;
        case boolean_:
            return store.boolean ? "true" : "false";
        case integer:
            return text( store.integer );
        case array:
            Appender!string str = appender!string;
            
            size_t count;
            foreach (value; store.array)
            {
                if (count++)
                    str.put(`,`);
                
                str.put(`"`);
                str.put(value.toString());
                str.put(`"`);
            }
            
            return str.data();
        case object_:
            Appender!string str = appender!string;
            
            size_t count;
            foreach (key, value; store.object_)
            {
                if (count++)
                    str.put(`,`);
                
                char schar = void, echar = void; // start and ending chars
                switch (value.type) with (MIType) {
                case object_:
                    schar = '{';
                    echar = '}';
                    break;
                case array:
                    schar = '[';
                    echar = ']';
                    break;
                default:
                    schar = echar = '"';
                    break;
                }
                
                str.put(key);
                str.put('=');
                str.put(schar);
                str.put(value.toString());
                str.put(echar);
            }
            
            return str.data();
        default:
            throw new Exception(text("toString type unimplemented for: ", type));
        }
    }
    
    string toMessage(string prefix)
    {
        return prefix~","~toString()~"\n";
    }
    
private:
    union Store
    {
        string string_;
        long integer;
        ulong uinteger;
        double floating;
        bool boolean;
        MIValue[string] object_;
        MIValue[] array;
    }
    Store store;
    MIType type;
}
unittest
{
    // Type testing
    {
        MIValue mistring;
        mistring["key"] = "value";
        assert(mistring["key"].str == "value");
        assert(mistring.toString() == `key="value"`);
    }
    {
        MIValue mibool;
        mibool["boolean"] = true;
        assert(mibool["boolean"].boolean == true);
        assert(mibool.toString() == `boolean="true"`);
    }
    {
        MIValue miint;
        miint["int"] = 2;
        assert(miint["int"].integer == 2);
        assert(miint.toString() == `int="2"`);
    }
    
    /*
    ^done,threads=[
    {id="2",target-id="Thread 0xb7e14b90 (LWP 21257)",
    frame={level="0",addr="0xffffe410",func="__kernel_vsyscall",
            args=[]},state="running"},
    {id="1",target-id="Thread 0xb7e156b0 (LWP 21254)",
    frame={level="0",addr="0x0804891f",func="foo",
            args=[{name="i",value="10"}],
            file="/tmp/a.c",fullname="/tmp/a.c",line="158",arch="i386:x86_64"},
            state="running"}],
    current-thread-id="1"
    */
    
    import std.algorithm.searching : canFind, count, startsWith, endsWith; // Lazy & AA will sort keys
    
    MIValue t2;
    t2["id"] = 2;
    t2["thread-id"] = "Thread 0xb7e14b90 (LWP 21257)";
    t2["state"] = "running";
    
    // id="2",target-id="Thread 0xb7e14b90 (LWP 21257)",state="running"
    string t2string = t2.toString();
    assert(t2string.canFind(`id="2"`));
    assert(t2string.canFind(`thread-id="Thread 0xb7e14b90 (LWP 21257)"`));
    assert(t2string.canFind(`state="running"`));
    assert(t2string.count(`,`) == 2);
    
    MIValue t2frame;
    t2frame["level"] = 0;
    t2frame["addr"]  = "0xffffe410";
    t2frame["func"]  = "__kernel_vsyscall";
    t2frame["args"]  = [];

    // Test objects in objects
    MIValue t2t;
    t2t["frame"] = t2frame;
    // frame={level="0",addr="0xffffe410",func="__kernel_vsyscall",args=[]}
    string t2tstring = t2t.toString();
    assert(t2tstring.canFind(`level="0"`));
    assert(t2tstring.canFind(`addr="0xffffe410"`));
    assert(t2tstring.canFind(`func="__kernel_vsyscall"`));
    assert(t2tstring.canFind(`args=[]`));
    assert(t2tstring.count(`,`) == 3);
    assert(t2tstring.startsWith(`frame={`));
    assert(t2tstring.endsWith(`}`));
    
    // Test all
    t2["frame"] = t2frame;
    string t2final = t2.toString();
    assert(t2final.canFind(`id="2"`));
    assert(t2final.canFind(`thread-id="Thread 0xb7e14b90 (LWP 21257)"`));
    assert(t2final.canFind(`state="running"`));
    assert(t2final.canFind(`level="0"`));
    assert(t2final.canFind(`addr="0xffffe410"`));
    assert(t2final.canFind(`func="__kernel_vsyscall"`));
    assert(t2final.canFind(`args=[]`));
}