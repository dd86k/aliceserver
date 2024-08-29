/// Main application command-line interface.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module main;

import std.stdio;
import std.getopt;
import core.stdc.stdlib : exit;
import config, server, logging;
import adapters, debuggers, transports;
import adbg.platform : ADBG_VERSION;

template VER(uint ver)
{
    enum VER =
        cast(char)((ver / 1000) + '0') ~ "." ~
        cast(char)(((ver % 1000) / 100) + '0') ~
        cast(char)(((ver % 100) / 10) + '0') ~
        cast(char)((ver % 10) + '0');
}

void cliListAdapters()
{
    writeln("Adapters:");
    writeln("dap ....... (default) Debug Adapter Protocol");
    writeln("mi ........ GDB/MI (GDB Machine Interface) version 1");
    exit(0);
}

void main(string[] args)
{
    ServerSettings osettings;
    
    GetoptResult gres = void;
    try
    {
        //TODO: --list-capabilities: List DAP or GDB/MI capabilities
        gres = getopt(args,
        "a|adapter",`Set adapter to use`, (string _, string value) {
            switch (value) {
            case "dap":
                osettings.adapterType = AdapterType.dap;
                break;
            case "mi":
                osettings.adapterType = AdapterType.mi;
                break;
            default:
                write("Invalid adapter. Available adapters listed below.\n\n");
                cliListAdapters();
            }
        },
        "list-adapters",  `List available adapters`, &cliListAdapters,
        "log",      `Logger: Enable logging to stderr`, &osettings.logStderr,
        "logfile",  `Logger: Enable logging to file path`, &osettings.logFile,
        "loglevel", `Logger: Set log level (default=info)`, &osettings.logLevel,
        "ver",      `Show only version and quit`, {
            writeln(PROJECT_VERSION);
            exit(0);
        },
        "version",  `Show version page and quit`, {
            write(
            "aliceserver ", PROJECT_VERSION, "\n",
            "            Built: ", __TIMESTAMP__, "\n",
            "            Compiler: ", __VENDOR__, " ", VER!__VERSION__, "\n",
            "            ", PROJECT_COPYRIGHT, "\n",
            "            ", PROJECT_LICENSE, "\n",
            "alicedbg    ", ADBG_VERSION, "\n",
            );
            exit(0);
        }
        );
    }
    catch (Exception ex)
    {
        stderr.writeln("cli error: ", ex.msg);
        exit(1);
    }
    
    if (gres.helpWanted)
    {
        static immutable int optpad = -16;
        gres.options[$-1].help = "Show this help page and quit";
        writeln("Debugger server\n\nOptions:");
        foreach (Option opt; gres.options)
        {
            with (opt) if (optShort)
                writefln(" %s, %*s  %s", optShort, optpad, optLong, help);
            else
                writefln("     %*s  %s", optpad, optLong, help);
        }
        exit(0);
    }
    
    // Setup logger
    logSetLevel(osettings.logLevel);
    if (osettings.logStderr)
        logAddAppender(new ConsoleAppender());
    if (osettings.logFile)
        logAddAppender(new FileAppender(osettings.logFile));
    logInfo("New instance with options %s", osettings);
    
    // Select main adapter with transport
    Adapter adapter = void;
    final switch (osettings.adapterType) with (AdapterType) {
    case dap:
        adapter = new DAPAdapter(new HTTPStdioTransport());
        break;
    case mi, mi2, mi3, mi4:
        adapter = new MIAdapter(new StdioTransport(), miVersion(osettings.adapterType));
        break;
    }
    
    // Extra parameters for Aliceserver right now are for the target
    if (args.length > 1)
    {
        targetExec(args[1]);
        
        if (args.length > 2)
        {
            targetExecArgs(args[2..$]);
        }
    }
    
    // Run server
    try startServer(adapter);
    catch (Exception ex)
    {
        debug logCritical("Unhandled Exception: %s", ex);
        else  logCritical(`/!\ Critical: %s`, ex.msg);
        exit(2);
    }
}
