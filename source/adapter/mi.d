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

import adapter.base;
import config;
import logging;
import server : AdapterType, targetExec, targetExecArgs;
import std.array : replace;
import std.ascii : isDigit;
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
        
        // Imitate GDB by send what we got
        send(format(`&"%s"`~"\n", formatCString( fullrequest )));
        
        // Get arguments
        string[] args = shellArgs( fullrequest );
        if (args.length == 0)
        {
            send(msgDone);
            send(gdbPrompt);
            goto Lread;
        }
        
        request = AdapterRequest.init;
        
        // Commands can come in two flavors: Numbered and unnumbered
        //
        // Unnumbered is just "-file-exec-and-symbols", this is mostly expected
        // for simple workloads, where we are expecting one process.
        //
        // Numbered has an request ID attached like "1-file-exec-and-symbols",
        // this allows (assumingly) the control of multiple processes.
        //
        // Commands like "123e" will be parsed (by GDB) as id=123 command="e".
        //
        // On GDB, a number alone is a no-op, but a (seemingly) valid command,
        // since it replies with `N^done\n` where N was the number input.
        MICommand command = miParseCommand(args[0]);
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
            request.type = AdapterRequestType.go;
            return request;
        // Terminal process.
        case "exec-abort":
            request.type = AdapterRequestType.terminate;
            return request;
        // attach PID
        // Attach debugger to process by its ID.
        case "target-attach", "attach":
            if (args.length < 2)
            {
                reply(AdapterError("Missing process-id argument."));
                goto Lread;
            }
            
            try request.attachOptions.pid = to!uint(args[1]);
            catch (Exception ex)
            {
                reply(AdapterError(format("Illegal process-id: '%s'.", args[1])));
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
            if (args.length < 2)
            {
                reply(AdapterError("Need target type"));
                goto Lread;
            }
            
            string targetType = args[1];
            switch (targetType) {
            case "exec":
                if (args.length < 3)
                {
                    reply(AdapterError("Need target executable path"));
                    goto Lread;
                }
                
                targetExec( args[2].dup );
                reply(AdapterReply());
                goto Lread;
            default:
                reply(AdapterError(format("Invalid target type: %s", targetType)));
            }
            goto Lread;
        // file-exec-and-symbols PATH
        // (gdb, lldb) Set target path and symbols as the same
        case "file-exec-and-symbols":
            if (args.length < 2)
            {
                reply(AdapterError("Need target executable path"));
                goto Lread;
            }
            
            targetExec( args[1].dup );
            reply(AdapterReply());
            goto Lread;
        // -exec-arguments ARGS
        // Set target arguments.
        case "exec-arguments":
            // If arguments given, set, otherwise, clear.
            targetExecArgs(args.length > 1 ? args[1..$].dup : null);
            reply(AdapterReply());
            goto Lread;
        // -environment-cd PATH
        // Set debugger directory.
        case "environment-cd":
            if (args.length < 2)
            {
                reply(AdapterError("Missing PATH directory."));
                goto Lread;
            }
            
            // NOTE: Ultimately, the server should be the one controlling cwd
            try chdir(args[1]);
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
            if (args.length < 1)
            {
                reply(AdapterReply());
                goto Lread;
            }
            
            string showCommand = args[1];
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
        // -info-gdb-mi-command COMMAND
        // Check if command exists.
        //case "info-gdb-mi-command":
        //    goto Lread;
        // List debugger features
        // gdb 13.1 example: ^done,features=["example","python"]
        // NOTE: GDB only accepts "-list-features", Native Debug sends "list-features"
        //       Command parse removes it for convenience
        case "list-features":
            // See §27.23 GDB/MI Support Commands for list.
            send("^done,features=[]\n");
            send(gdbPrompt);
            goto Lread;
        case "q", "quit", "gdb-exit":
            request.type = AdapterRequestType.close;
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
        if (request.id) buffer.writef("%u", request.id);
        
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
        // Example: ^error,msg="Undefined command: \"%s\"."
        send(format("^error,msg=\"%s\"\n", formatCString( msg.message )));
        send(gdbPrompt);
    }
    
    override
    void event(AdapterEvent msg)
    {
        // Examples:
        // - *stopped,reason="exited-normally"
        // - *stopped,reason="breakpoint-hit",disp="keep",bkptno="1",thread-id="0",
        //   frame={addr="0x08048564",func="main",
        //   args=[{name="argc",value="1"},{name="argv",value="0xbfc4d4d4"}],
        //   file="myprog.c",fullname="/home/nickrob/myprog.c",line="68",
        //   arch="i386:x86_64"}
        // - *stopped,reason="exited",exit-code="01"
        // - *stopped,reason="exited-signalled",signal-name="SIGINT",
        //   signal-meaning="Interrupt"
        // - @Hello world!
        // - ~"Message from debugger\n"
        switch (msg.type) with (AdapterEventType) {
        /*case output:
            send(format("~\"%s\"\n", formatCString( msg. )));
            break;*/
        case stopped:
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
struct MICommand
{
    string name;
    int id;
}

/// Parse the command 
// Throws: ConvOverflowException from `to` template
private
MICommand miParseCommand(string command)
{
    MICommand com = void;
    
    // TODO: Background syntax
    //       "example&"
    //       bool background;
    
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
        com.id      = to!int(idbuf[0..i]);
        com.name    = command[i..$];
    }
    else
    {
        com.id      = 0;
        com.name    = command;
    }
    
    // GDB/MI §27.23: "Note that the dash (-) starting all GDB/MI commands is
    //                 technically not part of the command name"
    if (com.name[0] == '-')
        com.name = com.name[1..$];
    
    return com;
}
unittest
{
    assert(miParseCommand("example").name == "example");
    assert(miParseCommand("example").id   == 0);
    
    assert(miParseCommand("123example").name == "example");
    assert(miParseCommand("123example").id   == 123);
    
    assert(miParseCommand("-file-exec-and-symbols").name == "file-exec-and-symbols");
    assert(miParseCommand("-file-exec-and-symbols").id   == 0);
    
    assert(miParseCommand("1-file-exec-and-symbols").name == "file-exec-and-symbols");
    assert(miParseCommand("1-file-exec-and-symbols").id   == 1);
}
