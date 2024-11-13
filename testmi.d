/// A simple GDB/MI interactive tester tool.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module testmi;

import std;
import core.thread;

//alias splitstr = std.array.split;
//alias white = std.ascii.isWhite;

version (Windows)
{
    immutable string defaultServer = "aliceserver.exe";
}
else
{
    immutable string defaultServer = "./aliceserver";
}

enum Op : char
{
    trace       = '@',
    info        = '~',
    important   = '*',
    warn        = '?',
    error       = '!',
    sending     = '>',
    receiving   = '<',
}
__gshared
{
    ProcessPipes server;
    bool overbose;
    int current_seq = 1;
}

void log(A...)(char op, string fmt, A args)
{
    // If operating is one of those, and we don't want verbose, do not print
    if (overbose == false)
    switch (op) {
    case Op.trace, Op.receiving, Op.sending: return;
    default:
    }
    
    stderr.write("TESTER[", op, "]: ");
    stderr.writefln(fmt, args);
}
int error(int code, string msg)
{
    log(Op.error, msg);
    return code;
}

string parseCString(string str)
{
    __gshared char[1024] buffer;
    
    return "";
}
unittest
{
    
}

struct MIReply
{
    string body_;
    char type;
}

MIReply send(string data)
{
    __gshared char[4096] buffer;
    
    // Read as much output first, then when we see "(gdb)" or "(lldb)",
    // we're free to send our command then
Lread:
    string reply = stripRight( server.stdout.readln() );
    
    log(Op.receiving, reply);
    
    if (reply.length <= 1)
    {
        error(3, "incomplete data");
        goto Lread;
    }
    
    MIReply mi;
    mi.type  = reply[0];
    mi.body_ = reply[1..$];
    
    switch (mi.type) {
    case '~': // console
    
        goto Lread;
    case '&': // logStream
    case '=': // notify:
        log(Op.trace, mi.body_);
        goto Lread;
    case '^': // result
        return mi;
    default: // Include unknown reads and "(gdb)\n" here
    }
    
    // Send command
    log(Op.sending, data);
    server.stdin.write(data, '\n');
    server.stdin.flush();
    
    // Read until we see a reply
    goto Lread;
}

int main(string[] args)
{
    string oserver;
    bool otrace;
    
    GetoptResult ores;
    try
    {
        ores = getopt(args,
        "s|server", "Server to use (default=aliceserver)", &oserver,
        "t|trace",  "Enable server trace messages", &otrace,
        "v|verbose","Enable client verbose messages", &overbose,
        );
    }
    catch (Exception ex)
    {
        log(Op.error, ex.msg);
        return 1;
    }
    
    if (ores.helpWanted)
    {
        defaultGetoptPrinter(
`MI client tester, supports "gdb -i mi" and "lldb-mi"

OPTIONS`, ores.options);
        return 0;
    }
    
    string[] svropts = void;
    switch (oserver) {
    case "gdb": // "gdb -i mi" alias
        svropts = [ "gdb", "-i", "mi", "--quiet" ];
        break;
    case "lldb": // "lldb-mi" alias
        svropts = [ "lldb-mi" ];
        break;
    case string.init: // default
        // Can't see it, build it
        if (exists(defaultServer) == false)
        {
            log(Op.important, "Server not found locally, building...");
            int code = wait( spawnProcess([ "dub", "build" ]) );
            if (code)
                return error(code, "Compilation ended in error, aborting");
        }
        
        svropts = [ defaultServer, "-a", "mi" ];
        if (otrace) svropts ~= [ "--log" ];
        break;
    default: // custom
        svropts = [ oserver ];
    }
    
    // Spawn server, redirect all except stderr (inherits handle)
    log(Op.info, "Starting %s...", oserver);
    string[] launchopts = svropts ~ [ "--adapter=mi" ] ~ (args.length >= 1 ? args[1..$] : []);
    server = pipeProcess(launchopts, Redirect.stdin | Redirect.stdout);
    // NOTE: waitTimeout is only defined for Windows,
    //       despite Pid.performWait being available for POSIX
    Thread.sleep(250.msecs);
    if (tryWait(server.pid).terminated)
        return error(2, "Could not launch server");
    
    send("show version");
    
    return 0;
}