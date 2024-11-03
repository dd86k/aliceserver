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

import adapter.base, adapter.types;
import config;
import logging;
import server : AdapterType, targetExec, targetExecArgs;
import std.array : replace;
import std.ascii;
import std.conv : to;
import std.file : chdir;
import std.format : format;
import std.string : indexOf;
import std.outbuffer : OutBuffer;
import std.string : stripRight;
import util.shell : shellArgs;
import util.mi;

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

enum MIType : char
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
}

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

final class MIAdapter : Adapter
{
    private enum {
        RETURN, /// Request is ready to be returned
        SKIP,   /// Skip request
    }
    
    this(ITransport t, int version_ = 2)
    {
        super(t);
        
        // Right now, all versions do the same things, for now
        switch (version_) {
        case 1: version_ = 4; goto case 4;
        case 2: break; // TODO: MI version 2 specific command behavior
        case 3: break; // TODO: MI version 3 specific command behavior
        case 4: break; // TODO: MI version 4 specific command behavior
        default:
            throw new Exception("Unsupported MI version");
        }
        
        miversion = version_;
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
            request.type = AdapterRequestType.run;
            return RETURN;
        };
        // Resume process execution from a stopped state.
        commands["exec-continue"] =
        commands["continue"] =
        (string[] args) {
            request.type = AdapterRequestType.continue_;
            return RETURN;
        };
        // Terminate process.
        commands["exec-abort"] =
        (string[] args) {
            request.type = AdapterRequestType.terminate;
            return RETURN;
        };
        // attach PID
        // Attach debugger to process by its ID.
        commands["target-attach"] =
        commands["attach"] =
        (string[] args) {
            if (args.length < 1)
            {
                reply(AdapterError("Missing process-id argument."));
                return SKIP;
            }
            
            string pidstr = args[0];
            try request.attachOptions.pid = to!uint(pidstr);
            catch (Exception ex)
            {
                reply(AdapterError(format("Illegal process-id: '%s'.", pidstr)));
                return SKIP;
            }
            
            request.type = AdapterRequestType.attach;
            request.attachOptions.run = true;
            return RETURN;
        };
        // -gdb-detach [ pid | gid ]
        // Detach debugger from process, keeping its execution alive.
        commands["target-detach"] =
        commands["gdb-detach"] =
        commands["detach"] =
        (string[] args) {
            request.type = AdapterRequestType.detach;
            return RETURN;
        };
        // -target-disconnect
        // Disconnect from remote target.
        commands["target-disconnect"] =
        (string[] args) {
            request.type = AdapterRequestType.detach;
            return RETURN;
        };
        // target TYPE [OPTIONS]
        // Set target parameters.
        commands["target"] =
        (string[] args) {
            if (args.length < 1)
            {
                reply(AdapterError("Need target type"));
                return SKIP;
            }
            
            string targetType = args[0];
            switch (targetType) {
            case "exec":
                if (args.length < 2)
                {
                    reply(AdapterError("Need target executable path"));
                    return SKIP;
                }
                
                targetExec( args[1].dup );
                reply(AdapterReply());
                break;
            default:
                reply(AdapterError(format("Invalid target type: %s", targetType)));
            }
            return SKIP;
        };
        // file-exec-and-symbols PATH
        // (gdb, lldb) Set target path and symbols as the same
        commands["file-exec-and-symbols"] =
        (string[] args) {
            if (args.length < 1)
            {
                reply(AdapterError("Need target executable path"));
                return SKIP;
            }
            
            targetExec( args[0].dup );
            reply(AdapterReply());
            return SKIP;
        };
        // -exec-arguments ARGS
        // Set target arguments.
        commands["exec-arguments"] =
        (string[] args) {
            // If arguments given, set, otherwise, clear.
            targetExecArgs(args.length > 0 ? args[0..$].dup : null);
            reply(AdapterReply());
            return SKIP;
        };
        // -environment-cd PATH
        // Set debugger directory.
        commands["exec-arguments"] =
        (string[] args) {
            if (args.length < 1)
            {
                reply(AdapterError("Missing PATH directory."));
                return SKIP;
            }
            
            // NOTE: Ultimately, the server should be the one controlling these requests
            try chdir(args[0]);
            catch (Exception ex)
            {
                reply(AdapterError(ex.msg));
                return SKIP;
            }
            
            reply(AdapterReply());
            return SKIP;
        };
        // show [INFO]
        // Show information about session.
        // Without an argument, GDB shows everything as stream output and
        // quits without sending a reply nor the prompt.
        commands["show"] =
        (string[] args) {
            if (args.length < 1)
            {
                reply(AdapterReply());
                return SKIP;
            }
            
            string showCommand = args[0];
            switch (showCommand) {
            case "version":
                static immutable string APPVERSION = "~\"Aliceserver "~PROJECT_VERSION~"\\n\"\n";
                send(APPVERSION);
                send(msgDone);
                send(gdbPrompt);
                return SKIP;
            default:
            }
            
            reply(AdapterError(format(`Unknown show command: "%s"`, showCommand)));
            return SKIP;
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
                reply(AdapterError("Usage: -info-gdb-mi-command MI_COMMAND_NAME"));
                return SKIP;
            }
            MIValue command;
            command["exists"] = cast(bool)((args[0] in commands) != null);
            MIValue r;
            r["command"] = command;
            reply(AdapterReply(r.toString()));
            return SKIP;
        };
        // List debugger features
        // gdb 13.1 example: ^done,features=["example","python"]
        commands["list-features"] =
        (string[] args) {
            // See §27.23 GDB/MI Support Commands for list.
            send("^done,features=[]\n");
            send(gdbPrompt);
            return SKIP;
        };
        // Ignore list
        commands["gdb-set"] =
        commands["inferior-tty-set"] =
        (string[] args) { return SKIP; };
        // Close debugger instance
        commands["gdb-exit"] =
        commands["quit"] =
        commands["q"] =
        (string[] args) {
            request.type = AdapterRequestType.close;
            // NOTE: gdb-mi when attached does not terminate.
            //       Therefore, the preference is not to terminate.
            request.closeOptions.terminate = false;
            return RETURN;
        };
        
        send(gdbPrompt); // Ready!
    }
    
    // Return short name of this adapter
    override
    string name()
    {
        final switch (miversion) {
        case 4: return "mi4";
        case 3: return "mi3";
        case 2: return "mi2";
        }
    }
    
    override
    AdapterRequest listen()
    {
    Lread:
        ubyte[] buffer = receive();
        string fullrequest = cast(immutable(char)[])buffer;
        
        // Parse request
        MIRequest command = parseMIRequest(fullrequest);
        
        // GDB sends the trace of the command as an event
        // NOTE: GDB does not echo commands when they aren't MI-related
        //       Examples that do emit trace: "q", not found commands
        //       Examples that don't: "-info-gdb-mi-command"
        {
            scope OutBuffer tracebuf = new OutBuffer();
            tracebuf.write("&\"");
            tracebuf.write(formatCString(command.line));
            tracebuf.write("\"\n");
            send(tracebuf.toBytes());
        }
        
        // GDB behavior:
        // - "":    valid
        // - "-":   invalid (not found)
        // - "22":  valid
        // - "22-": invalid (not found)
        // - "22 help": valid
        if (command.name == "") // note: "-" -> "" by command parser
        {
            reply(AdapterReply());
            goto Lread;
        }
        
        // Command exists, get request out of that
        if (int delegate(string[])* fq = command.name in commands)
        {
            request = AdapterRequest.init;
            request.id = command.id;
            if ((*fq)(command.args))
                goto Lread;
            return request;
        }
        
        reply(AdapterError(format(`Unknown request: "%s"`, command.name)));
        goto Lread;
    }
    
    override
    void reply(AdapterReply msg)
    {
        // NOTE: stdio transport flushes on each send
        //       clients are expected to read until newlines, so emulate that
        
        scope OutBuffer buffer = new OutBuffer();
        buffer.reserve(2048);
        
        // Attach token id to result record
        if (request.id)
            buffer.writef("%u", request.id);
        
        // Some requests may emit different result words
        switch (request.type) {
        case AdapterRequestType.launch: // Compability
        case AdapterRequestType.run: // Compability
            buffer.write("^running");
            break;
        default:
            buffer.write("^done");
        }
        
        if (msg.details)
        {
            buffer.write(',');
            buffer.write(msg.details);
        }
        
        buffer.write('\n');
        
        send(buffer.toBytes());
        send(gdbPrompt); // Ready
    }
    
    override
    void reply(AdapterError msg)
    {
        logError(msg.message);
        string cmsg = formatCString( msg.message );
        // ^error,msg="Undefined command: \"%s\"."\n
        send(request.id ?
            format("%d^error,msg=\"%s\"\n", request.id, cmsg) :
            format("^error,msg=\"%s\"\n", cmsg)
        );
        send(gdbPrompt);
    }
    
    override
    void event(AdapterEvent msg)
    {
        switch (msg.type) with (AdapterEventType) {
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
            break;
        // - *stopped,reason="breakpoint-hit",disp="keep",bkptno="1",thread-id="0",
        //   frame={addr="0x08048564",func="main",
        //   args=[{name="argc",value="1"},{name="argv",value="0xbfc4d4d4"}],
        //   file="myprog.c",fullname="/home/nickrob/myprog.c",line="68",
        //   arch="i386:x86_64"}
        // - *stopped,reason="signal-received",signal-name="SIGSEGV",
        //   signal-meaning="Segmentation fault",frame={addr="0x0000000000000000",
        //   func="??",args=[],arch="i386:x86-64"},thread-id="1",stopped-threads="all"
        case stopped:
            break;
        // - *stopped,reason="exited-normally"
        // - *stopped,reason="exited",exit-code="01"
        // - *stopped,reason="exited-signalled",signal-name="SIGINT",signal-meaning="Interrupt"
        case exited:
            if (msg.exited.code)
                send(format("*stopped,reason=\"exited\",exit-code=\"%d\"\n", msg.exited.code));
            else
                send("*stopped,reason=\"exited-normally\"\n");
            break;
        default:
            logWarn("Unimplemented event type: %s", msg.type);
        }
    }
    
    override
    void close()
    {
        // When a quit request is sent, GDB simply quits without confirming,
        // since the client is supposed to do the confirming part.
        //
        // So, do nothing!
    }
    
private:
    // NOTE: Virtual functions inside a constructor may lead to unexpected results
    //       in the derived classes - At leat marking the class as final prevents this
    /// AA of implemented commands
    int delegate(string[] args)[string] commands;
    /// Current MI version in use
    int miversion;
    /// Current request
    AdapterRequest request;
}

// Check MI version out of adapter type
int miVersion(AdapterType adp)
{
    switch (adp) with (AdapterType) { // same order as gdb
    case mi4, mi:   return 4;
    case mi3:       return 3;
    case mi2:       return 2;
    default:        return 0;
    }
}
unittest
{
    // Valid MI versions
    assert(miVersion(AdapterType.mi2) == 2);
    assert(miVersion(AdapterType.mi3) == 3);
    assert(miVersion(AdapterType.mi4) == 4);
    // Invalid MI verisons
    assert(miVersion(AdapterType.dap) == 0);
}

private
struct MIRequest
{
    uint id;        /// Request ID
    string name;    /// Command name
    string[] args;  /// Command arguments
    
    string line;    /// Full command line
}

/// Parse the command 
// Throws: ConvOverflowException from `to` template
private
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
    
    // NOTE: Supporting commands with whitespaces before the command name is not currently a priority
    
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
