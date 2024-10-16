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
import util.shell : shellArgs;
import util.mi;

// NOTE: GDB/MI versions and commmands
//
//       The most important aspect to be as close to GDB as possible, since LLVM
//       does not distribute compiled llvm-mi binaries anymore, I believe maybe either
//       switched to gdb-mi or llvm-vscode.
//
//       Handling version variants is currently a work in progress. But right now,
//       it has no significance of its own. When "mi" is specified, GDB defaults to
//       the latest version: "Since --interpreter=mi always points to the latest MI version,"
//       Since there is no way to specify MI version 1, it will not be implemented.
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
//       Distro      GDBVer
//       Debian  6      7.0
//       Debian  7      7.4
//       Debian  8      7.7
//       Debian  9     7.12
//       Debian 10      8.2
//       Debian 11     10.1
//       Debian 12     13.1

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

class MIAdapter : Adapter
{
    this(ITransport t, int version_ = 2)
    {
        super(t);
        
        if (version_ < 2 || version_ > 4) // failsafe
            throw new Exception("Wrong MI version specified");
        miversion = version_;
        
        send(gdbPrompt); // Ready!
    }
    
    // Return short name of this adapter
    override
    string name()
    {
        switch (miversion) {
        case 3:     return "mi3";
        case 2:     return "mi2";
        default:    return "mi4";
        }
    }
    
    override
    AdapterRequest listen()
    {
    Lread:
        ubyte[] buffer = receive();
        string fullrequest = cast(immutable(char)[])buffer;
        
        // Parse request and imitate GDB
        MIRequest command = parseMIRequest(fullrequest);
        send(formatCString("&\"%s\"\n", command.line));
        
        // GDB behavior:
        // - "":    valid
        // - "-":   invalid (not found)
        // - "22":  valid
        // - "22-": invalid (not found)
        // - "22 help": valid
        if (command.name == "")
        {
            reply(AdapterReply());
            goto Lread;
        }
        
        request = AdapterRequest.init;
        request.id = command.id;
        
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
        
        // Filtered by recognized requests (Command list: gdb/mi/mi-cmds.c)
        switch (command.name) {
        // -exec-run [ --all | --thread-group N ] [ --start ]
        // Start execution of target process.
        //   --all: Start all target subprocesses
        //   --thread-group: Start only thread group (of type process) for target process
        //   --start: Stop at target's main function.
        case "exec-run":
            request.type = AdapterRequestType.launch;
            
            // If we saved the exec target
            string exec = targetExec();
            if (exec)
            {
                request.launchOptions.path = exec;
                return request;
            }
            
            reply(AdapterError("No executable to run."));
            goto Lread;
        // Resume process execution.
        case "exec-continue":
            request.type = AdapterRequestType.continue_;
            return request;
        // Terminal process.
        case "exec-abort":
            request.type = AdapterRequestType.terminate;
            return request;
        // attach PID
        // Attach debugger to process by its ID.
        case "target-attach", "attach":
            if (command.args.length < 2)
            {
                reply(AdapterError("Missing process-id argument."));
                goto Lread;
            }
            
            try request.attachOptions.pid = to!uint(command.args[1]);
            catch (Exception ex)
            {
                reply(AdapterError(format("Illegal process-id: '%s'.", command.args[1])));
                goto Lread;
            }
            
            request.type = AdapterRequestType.attach;
            return request;
        // -gdb-detach [ pid | gid ]
        // Detach debugger from process, keeping its execution alive.
        case "target-detach", "gdb-detach", "detach":
            request.type = AdapterRequestType.detach;
            return request;
        // -target-disconnect
        // Disconnect from remote target.
        //case "target-disconnect":
        // target TYPE [OPTIONS]
        // Set target parameters.
        case "target":
            if (command.args.length < 2)
            {
                reply(AdapterError("Need target type"));
                goto Lread;
            }
            
            string targetType = command.args[1];
            switch (targetType) {
            case "exec":
                if (command.args.length < 3)
                {
                    reply(AdapterError("Need target executable path"));
                    goto Lread;
                }
                
                targetExec( command.args[2].dup );
                reply(AdapterReply());
                goto Lread;
            default:
                reply(AdapterError(format("Invalid target type: %s", targetType)));
            }
            goto Lread;
        // file-exec-and-symbols PATH
        // (gdb, lldb) Set target path and symbols as the same
        case "file-exec-and-symbols":
            if (command.args.length < 2)
            {
                reply(AdapterError("Need target executable path"));
                goto Lread;
            }
            
            targetExec( command.args[1].dup );
            reply(AdapterReply());
            goto Lread;
        // -exec-arguments ARGS
        // Set target arguments.
        case "exec-arguments":
            // If arguments given, set, otherwise, clear.
            targetExecArgs(command.args.length > 1 ? command.args[1..$].dup : null);
            reply(AdapterReply());
            goto Lread;
        // -environment-cd PATH
        // Set debugger directory.
        case "environment-cd":
            if (command.args.length < 2)
            {
                reply(AdapterError("Missing PATH directory."));
                goto Lread;
            }
            
            // NOTE: Ultimately, the server should be the one controlling cwd
            try chdir(command.args[1]);
            catch (Exception ex)
            {
                reply(AdapterError(ex.msg));
                goto Lread;
            }
            
            reply(AdapterReply());
            goto Lread;
        // show [INFO]
        // Show information about session.
        // Without an argument, GDB shows everything as stream output and
        // quits without sending a reply nor the prompt.
        case "show":
            if (command.args.length < 1)
            {
                reply(AdapterReply());
                goto Lread;
            }
            
            string showCommand = command.args[1];
            switch (showCommand) {
            case "version":
                static immutable string APPVERSION = "~\"Aliceserver "~PROJECT_VERSION~"\\n\"\n";
                send(APPVERSION);
                send(msgDone);
                send(gdbPrompt);
                goto Lread;
            default:
            }
            
            reply(AdapterError(format(`Unknown show command: "%s"`, showCommand)));
            goto Lread;
        // TODO: -info-gdb-mi-command COMMAND
        // Check if command exists.
        //case "info-gdb-mi-command":
        //    goto Lread;
        // List debugger features
        // gdb 13.1 example: ^done,features=["example","python"]
        case "list-features":
            // See §27.23 GDB/MI Support Commands for list.
            send("^done,features=[]\n");
            send(gdbPrompt);
            goto Lread;
        case "q", "quit", "gdb-exit":
            request.type = AdapterRequestType.close;
            // NOTE: gdb-mi when attached does not terminate.
            //       Therefore, the preference is not to terminate.
            request.closeOptions.terminate = false;
            return request;
        // Ignore list
        case "gdb-set", "inferior-tty-set": goto Lread;
        default:
            reply(AdapterError(format(`Unknown request: "%s"`, command.name)));
            goto Lread;
        }
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
            buffer.write("^running\n");
            break;
        default:
            // TODO: Add result data
            buffer.write("^done\n");
        }
        
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
        // since the client is supposed to do that.
        //
        // So, do nothing!
    }
    
private:
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
    assert(miVersion(AdapterType.mi)  == 4);
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
