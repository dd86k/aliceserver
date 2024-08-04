/// A simple DAP interactive tester tool.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module testdap;

import std;
import core.thread;

alias splitstr = std.array.split;
alias white = std.ascii.isWhite;

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

/// Prepare a new message to send
JSONValue newMsg(string command)
{
    JSONValue j;
    j["seq"] = current_seq++;
    j["type"] = "request";
    j["command"] = command;
    return j;
}

/// Send message to server and read a reply
JSONValue serverSend(JSONValue jobj)
{
    string bodydata = jobj.toString();
    size_t bodylen  = bodydata.length;
    
    log(Op.sending, bodydata);
    server.stdin.write(
    "Content-Length: ", bodylen, "\r\n"~
    "\r\n",
    bodydata);
    server.stdin.flush();
    
    __gshared char[4096] buffer;
    
Lread:
    //TODO: Read until empty in case of multiple header fields
    string header = strip( server.stdout.readln() );
    
    cast(void)server.stdout.readln();
    
    log(Op.trace, "Header: %s", header);
    string[] parts = header.split(":");
    size_t sz = to!size_t(strip(parts[1]));
    const(char)[] httpbody = server.stdout.rawRead(buffer[0..sz]);
    
    log(Op.receiving, cast(string)httpbody);
    
    JSONValue j = parseJSON(httpbody);
    
    if (j["type"].str == "event")
    {
        onEvent(j);
        goto Lread;
    }
    
    return j;
}

void onEvent(JSONValue j)
{
    log(Op.info, "event: %s", j);
}

int main(string[] args)
{
    string oserver;
    
    GetoptResult ores;
    try
    {
        ores = getopt(args,
        "s|server", "Server to use (default=aliceserver)", &oserver,
        "t|trace",  "Extra verbose messages", &overbose,
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
`Test DAP client, should support "gdb -i dap" and "lldb-vscode"

OPTIONS`, ores.options);
        return 0;
    }
    
    string[] svropts = void;
    switch (oserver) {
    case "gdb": // "gdb -i dap" alias
        svropts = [ "gdb", "-i", "dap" ];
        break;
    case "lldb": // "lldb-vscode" alias
        svropts = [ "lldb-vscode" ];
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
        
        svropts = [ defaultServer ];
        break;
    default: // custom
        svropts = [ oserver ];
    }
    
    // Spawn server, redirect all except stderr (inherits handle)
    log(Op.info, "Starting %s...", oserver);
    string[] launchopts = svropts ~ (args.length >= 1 ? args[1..$] : []);
    server = pipeProcess(launchopts, Redirect.stdin | Redirect.stdout);
    // NOTE: waitTimeout is only defined for Windows,
    //       despite Pid.performWait being available for POSIX
    Thread.sleep(250.msecs);
    if (tryWait(server.pid).terminated)
        return error(2, "Could not launch server");
    
    //bool serverSupportsXYZ;
    
    // Start with the initialize request
    {
        JSONValue jinitialize = newMsg("initialize");
        JSONValue jarguments;
        jarguments["clientID"] = "dd-dap-tester";
        jarguments["clientName"] = "DD's DAP Tester Tool";
        jarguments["adapterID"] = "dd";
        jinitialize["arguments"] = jarguments;
        
        JSONValue jres = serverSend(jinitialize); current_seq++;
        if (jres["request_seq"].integer != 1)
        {
            log(Op.warn, "Initial request id isn't 1, continuing anyway...");
        }
        if (jres["command"].str != "initialize")
        {
            log(Op.warn, "Mismatching command reponse to 'initialize'");
        }
        
        if (const(JSONValue)* jbody = "body" in jres)
        {
            static immutable string supports = "supports";
            static immutable string support  = "support";
            string[] output;
            foreach (ref key; jbody.object().keys)
            {
                // NOTE: supportTerminateDebuggee lacks the 's'
                if (startsWith(key, supports))
                    output ~= key[supports.length..$];
                else if (startsWith(key, support))
                    output ~= key[support.length..$];
            }
            log(Op.info, "Server capabilities: %s", output.join(", "));
        }
        else
            log(Op.info, "Server did not emit any capabilities");
        
        // NOTE: Usually, breakpoints would be set here
        
        /+jres = serverSend(newMsg("configurationDone"));
        
        if (jres["request_seq"].integer != 3)
        {
            log(Op.warn, "configurationDone request id isn't 3, continuing anyway...");
        }
        if (jres["command"].str != "configurationDone")
        {
            log(Op.warn, "Mismatching command reponse to 'configurationDone'");
        }+/
    }
    
    log(Op.info, "Connected");
    
Lprompt:
    write("tester> ");
    args = readln().stripRight().splitstr!white;
    if (args.length == 0)
        goto Lprompt;
    
    switch (args[0]) {
    case "help":
        log(Op.info, "Commands: attach PID, spawn PATH, disconnect, terminate, quit");
        break;
    case "attach": // pid
        if (args.length < 2)
        {
            log(Op.error, "I need a PID");
            break;
        }
        JSONValue jattach = newMsg("attach");
        jattach["arguments"] = [
            "pid": to!uint(args[1])
        ];
        
        JSONValue jresponse = serverSend(jattach);
        if (jresponse["request_seq"] != jattach["seq"])
        {
            log(Op.warn, "Request id invalid, continuing anyway...");
        }
        break;
    case "launch": // path
        if (args.length < 2)
        {
            log(Op.error, "I need a path to an executable");
            break;
        }
        JSONValue jlaunch = newMsg("launch");
        jlaunch["arguments"] = [
            "path": to!uint(args[1])
        ];
        
        JSONValue jresponse = serverSend(jlaunch);
        if (jresponse["request_seq"] != jlaunch["seq"])
        {
            log(Op.warn, "Request id invalid, continuing anyway...");
        }
        break;
    case "terminate": // gracefully terminate debuggee
        break;
    case "q", "quit", "disconnect":
        JSONValue jdisconnect = newMsg("disconnect");
        cast(void)serverSend(jdisconnect);
        return 0;
    default:
        if (args.length)
            log(Op.info, "Unknown command");
    }
    
    goto Lprompt;
}
