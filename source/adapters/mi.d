/// GDB/MI adapter.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module adapters.mi;

import adapters.base;
import transports.base : ITransport;
import logging;
import server : SERVER_NAME, SERVER_VERSION;
import core.vararg;
import std.format;
import std.array : replace, split;
import std.ascii : isWhite;

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

// Reference:
// - https://ftp.gnu.org/old-gnu/Manuals/gdb/html_chapter/gdb_22.html
// - https://sourceware.org/gdb/current/onlinedocs/gdb.html/GDB_002fMI.html
// - https://github.com/lldb-tools/lldb-mi
// - gdb: gdb/mi

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

enum MIVariant { gdb }

private
immutable string gdbString = "(gdb)\n";

private
string parseCString(string cstr)
{
    return "";
}

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
    this(ITransport t, MIVariant mivariant = MIVariant.gdb, int miversion = 1)
    {
        super(t);
        
        variant  = mivariant;
        version_ = miversion;
        
        final switch (mivariant) {
        case MIVariant.gdb:
            requests["q"] = RequestType.close;
            requests["quit"] = RequestType.close;
            requests["-gdb-exit"] = RequestType.close;
            requests["-gdb-detach"] = RequestType.detach;
            requests["attach"] = RequestType.attach;
            requests["exec-run"] = RequestType.go;
            //requests["exec-interrupt"] = RequestType.pause;
            requests["exec-continue"] = RequestType.go;
            //requests["exec-next"] = RequestType.go; // + --reverse
            //requests["exec-step"] = RequestType.instructionStep; // + --reverse
            //requests["exec-finish"] = RequestType.instructionStepOut; // + --reverse
            // goto:
            //   break-insert -t TARGET
            //   exec-jump TARGET
            //requests["goto"] = RequestType.instructionStepOut;
            // change variable: gdb-set var REGISTER = VALUE
            //requests["gdb-set"] = RequestType.instructionStepOut;
            break;
        }
        
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
        string[] args = fullrequest.split!isWhite;
        if (args.length == 0)
        {
            send("^done\n");
            send(gdbString);
            goto Lread;
        }
        AdapterRequest request;
        
        // Recognized requests
        string requestName = args[0];
        RequestType *req = requestName in requests;
        
        // Filter by recognized requests
        if (req) switch (*req) {
        case RequestType.attach:
            request.type = RequestType.attach;
            //areq.attachOptions.pid = 
            return request;
        case RequestType.close:
            request.type = RequestType.close;
            return request;
        default: // Not an official request, likely more GDB related
        }
        
        // Filter by specific GDB or LLDB command
        switch (requestName) {
        case "show":
            // NOTE: "show" alone makes GDB show everything
            //       and then quits.
            if (args.length < 1)
            {
                send(cast(ubyte[])"^done\n");
                goto Lread;
            }
            
            switch (args[1]) {
            case "version":
                enum SERVER_LINE = SERVER_NAME~" "~SERVER_VERSION~"\n";
                send(SERVER_LINE);
                send("^done\n");
                send(gdbString);
                goto Lread;
            default:
            }
            break; // Fallthrough to error
        default:
            string e = format(`Unknown request: "%s"`, requestName);
            logError(e);
            reply(AdapterError(e));
            goto Lread;
        }
        
        return AdapterRequest();
    }
    
    override
    void reply(AdapterReply msg)
    {
        // TODO: send command and newline
        
        send("^done\n");
        send(gdbString);
    }
    
    override
    void reply(AdapterError msg)
    {
        // Example: ^error,msg="Undefined command: \"%s\"."
        send(format(`^error,msg="%s"`~"\n", formatCString( msg.message )));
        send(gdbString);
    }
    
    override
    void event(AdapterEvent msg)
    {
        
    }
    
    override
    void close()
    {
        // Do nothing
    }
    
private:
    MIVariant variant;
    int version_;
    RequestType[string] requests;
}