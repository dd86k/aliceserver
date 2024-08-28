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
module adapters.mi;

import std.conv : to;
import std.format : format;
import std.file : chdir;
import std.array : replace;
import logging;
import config;
import utils.shell : shellArgs;
import adapters.base;
import server : targetExec;

// TODO: Function to separate shell-like arguments (with quotes)

// NOTE: GDB/MI versions
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
//       Debian  6: GDB 7.0
//       Debian  7: GDB 7.4
//       Debian  8: GDB 7.7
//       Debian  9: GDB 7.12
//       Debian 10: GDB 8.2
//       Debian 11: GDB 10.1
//       Debian 12: GDB 13.1

// NOTE: code-debug
//
//     Launching GDB
//       On Win32 platforms:
//         - `file-exec-and-symbols` for file path and symbols (?)
//         - if separateConsole is defined: `gdb-set new-console on`.
//         - `exec-run` (+ `--start`)
//
//       On Linux, if separateConsole is defined, `inferior-tty-set TTY` is executed.
//       

enum MIType : char
{
    // Replies
    result = '^',
    
    // Events (Async record types)
    exec = '*', // execution state changed: "stopped" or other message
    notify = '=', // notification: "stopped" or other message
    asyncStatus = '+', // async status: "stopped" or other message
    
    // Stream record (informative)
    // "running" (exec running), "done" (task performed successfully),
    // "exit" (quit), "error" (task failed), "connected" (?),
    console = '~', // terminal output
    targetStream = '@', // 
    logStream = '&', // echoes commands
    
    // Input
    command = '-',
}

private immutable string gdbString = "(gdb)\n";
private immutable string doneMsg = "^done\n";

/*
private
string parseCString(string cstr)
{
    return "";
}
*/

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
    // TODO: version parameter
    this(ITransport t, int version_ = 1)
    {
        super(t);
        
        miversion = version_;
        
        send(gdbString); // Ready!
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
            send(doneMsg);
            send(gdbString);
            goto Lread;
        }
        
        // Recognized requests
        string requestCommand = args[0];
        
        // TODO: These commands
        //       - -exec-finish: functionOut
        //       - -exec-next: nextLine
        //       - -exec-interrupt: pause
        //       - -exec-step: instructionStep
        //       - -exec-finish: instructionStepOut
        //       - break-insert: insert breakpoint
        //       - break-condition: change condition to breakpoint
        //       - file-exec-and-symbols: set exec and symbols
        //       - goto: break-insert -t TARGET or exec-jump TARGET
        
        // Command list: gdb/mi/mi-cmds.c
        // Filter by recognized requests
        AdapterRequest request;
        switch (requestCommand) {
        case "-exec-run":
            request.type = RequestType.launch;
            
            // If we saved the exec target
            if (exec)
            {
                request.launchOptions.path = exec;
                return request;
            }
            
            // If server got exec specified earlier
            string exec2 = targetExec();
            if (exec2)
            {
                request.launchOptions.path = exec2;
                return request;
            }
            
            reply(AdapterError("No executable to run."));
            goto Lread;
        case "-exec-continue":
            request.type = RequestType.go;
            return request;
        case "-exec-abort":
            request.type = RequestType.terminate;
            return request;
        case "-gdb-detach", "detach":
            request.type = RequestType.detach;
            return request;
        case "attach":
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
            
            request.type = RequestType.attach;
            return request;
        case "environment-directory":
            if (args.length < 2)
            {
                reply(AdapterError("Missing process-id argument."));
                goto Lread;
            }
            
            string dir = args[1];
            chdir(dir);
            reply(AdapterReply());
            goto Lread;
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
                
                exec = args[2].dup;
                reply(AdapterReply());
                goto Lread;
            default:
                reply(AdapterError(format("Invalid target type: %s", targetType)));
            }
            goto Lread;
        // (gdb, lldb) Set target path and symbols as the same
        // file-exec-and-symbols PATH
        case "file-exec-and-symbols":
            if (args.length < 2)
            {
                reply(AdapterError("Need target executable path"));
                goto Lread;
            }
            
            exec = args[1].dup;
            goto Lread;
        case "-exec-arguments":
            // If arguments given, set, otherwise, clear.
            execArguments = args.length >= 1 ? args[1..$].dup : null;
            reply(AdapterReply());
            goto Lread;
        // TODO: print exec arguments
        //case "-exec-show-arguments":
        
        //case "mi-async": // TODO: mi-async
        case "show":
            // NOTE: "show" alone makes GDB show everything
            //       and then quits, without saying anything else.
            if (args.length < 1)
            {
                reply(AdapterReply());
                goto Lread;
            }
            
            string showCommand = args[1];
            switch (showCommand) {
            case "version":
                static immutable string APPVERSION = "Aliceserver "~PROJECT_VERSION~"\n";
                send(APPVERSION);
                send(doneMsg);
                send(gdbString);
                goto Lread;
            default:
            }
            
            reply(AdapterError(format(`Unknown show command: "%s"`, showCommand)));
            break;
        case "q", "quit", "-gdb-exit":
            request.type = RequestType.close;
            return request;
        // Ignore list
        case "gdb-set", "inferior-tty-set": goto Lread;
        default:
            reply(AdapterError(format(`Unknown request: "%s"`, requestCommand)));
            break;
        }
        
        goto Lread;
    }
    
    override
    void reply(AdapterReply msg)
    {
        send(doneMsg);
        send(gdbString);
    }
    
    override
    void reply(AdapterError msg)
    {
        logError(msg.message);
        // Example: ^error,msg="Undefined command: \"%s\"."
        send(format("^error,msg=\"%s\"\n", formatCString( msg.message )));
        send(gdbString);
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
        switch (msg.type) with (EventType) {
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
    
    string exec;
    string[] execArguments;
}