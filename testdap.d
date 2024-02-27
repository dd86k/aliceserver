/// A simple DAP interactive tester tool.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module testdap;

import std.stdio;
import std.string;
import std.process;
import std.json;
import std.conv;
import std.file : exists;
import std.array;
import std.ascii;
import core.thread;

version (Windows)
{
    immutable string defaultCommand = "aliceserver.exe";
}
else
{
    immutable string defaultCommand = "./aliceserver";
}

enum Op : char
{
    trace = '@',
    info = '~',
    important = '*',
    warn = '?',
    error = '!',
    sending = '>',
    receiving = '<',
}
__gshared
{
    ProcessPipes proc;
    bool overbose = true;
    int current_seq = 1;
}

void log(A...)(char op, string fmt, A args)
{
    if (op == Op.trace && overbose == false) return;
    
    stderr.write(op, op, op, "\ttest: ");
    stderr.writefln(fmt, args);
}
int error(int code, string msg)
{
    log(Op.error, msg);
    return code;
}

JSONValue serverSend(JSONValue jobj)
{
    string bodydata = jobj.toString();
    size_t bodylen  = bodydata.length;
    
    log(Op.sending, bodydata);
    proc.stdin.write(
    "Content-Length: ", bodylen, "\r\n"~
    "\r\n",
    bodydata);
    proc.stdin.flush();
    
    __gshared char[4096] buffer;

LREADAGAIN:
    //TODO: Read until empty in case of multiple header fields
    string header = strip( proc.stdout.readln() );
    cast(void)proc.stdout.readln();
    
    log(Op.info, "Header: %s", header);
    string[] parts = header.split(":");
    size_t sz = to!uint(strip(parts[1]));
    const(char)[] httpbody = proc.stdout.rawRead(buffer[0..sz]);
    
    log(Op.receiving, cast(string)httpbody);
    
    JSONValue j = parseJSON(httpbody);
    
    if (j["type"].str == "event")
    {
        onEvent(j);
        goto LREADAGAIN;
    }
    
    return j;
}
JSONValue newMsg(string command)
{
    JSONValue j;
    j["seq"] = current_seq++;
    j["type"] = "request";
    j["command"] = command;
    return j;
}

void onEvent(JSONValue j)
{
    log(Op.info, "%s", j);
}

//
// CLI
//

int main(string[] args)
{
    /*GetoptResult ores;
    try
    {
        ores = getopt(args,
        );
    }
    catch (Exception ex)
    {
        log(Op.error, ex.msg);
        return 1;
    }*/
    
    if (args.length > 1)
    {
        args = args[1..$];
    }
    else
    {
        args = [ defaultCommand ];
    }
    
    if (args.length <= 1 && exists(defaultCommand) == false)
    {
        log(Op.important, "Server not found locally, building...");
        auto pid = spawnProcess([ "dub", "build" ]);
        int code = wait(pid);
        if (code)
        {
            log(Op.error, "Compilation ended in error, aborting");
            return code;
        }
    }
    
    // Spawn server, redirect all except stderr (inherits handle)
    log(Op.info, "Starting server...");
    proc = pipeProcess(args, Redirect.stdin | Redirect.stdout);
    if (proc.pid.processID == 0)
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
            string output;
            foreach (ref key; jbody.object().keys)
            {
                // NOTE: supportTerminateDebuggee lacks the 's'
                if (startsWith("support", key) == false)
                    continue;
                output ~= key;
            }
            log(Op.info, "Server capabilities: %s", output);
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
    
LPROMPT:
    write("test> ");
    string[] ucomm = stripRight(readln()).split!isWhite;
    
    if (ucomm.length == 0)
        goto LPROMPT;
    
    switch (ucomm[0]) {
    case "help":
        log(Op.info, "Commands: attach, spawn, disconnect, terminate, quit");
        break;
    case "attach": // pid
        if (ucomm.length < 2)
        {
            log(Op.error, "I need a PID");
            break;
        }
        JSONValue jattach = newMsg("attach");
        jattach["arguments"] = [
            "pid": to!uint(ucomm[1])
        ];
        
        JSONValue jresponse = serverSend(jattach);
        if (jresponse["request_seq"] != jattach["seq"])
        {
            log(Op.warn, "Request id invalid, continuing anyway...");
        }
        break;
    case "launch": // path
        if (ucomm.length < 2)
        {
            log(Op.error, "I need a path");
            break;
        }
        JSONValue jlaunch = newMsg("launch");
        jlaunch["arguments"] = [
            "path": to!uint(ucomm[1])
        ];
        
        JSONValue jresponse = serverSend(jlaunch);
        if (jresponse["request_seq"] != jlaunch["seq"])
        {
            log(Op.warn, "Request id invalid, continuing anyway...");
        }
        break;
    case "disconnect": // detach or kill debuggee
        break;
    case "terminate": // gracefully terminate debuggee
        break;
    case "q", "quit":
        JSONValue jdisconnect = newMsg("disconnect");
        cast(void)serverSend(jdisconnect);
        return 0;
    default:
        if (ucomm.length)
            log(Op.info, "Unknown command");
    }
    
    goto LPROMPT;
}
