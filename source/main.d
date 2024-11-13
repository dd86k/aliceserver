/// Main application command-line interface.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module main;

import std.stdio;
import std.getopt;
import core.stdc.stdlib : exit;
import config, server, ddlogger;
import adbg.platform : ADBG_VERSION;

// TODO: Attach available adapter types
//       e.g., register them before calling getopt or statically in global memory

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
        // TODO: --list-capabilities: List DAP capabilities and GDB/MI features
        // TODO: --tcp-port=NUMBER
        gres = getopt(args,
        "a|adapter",`Set adapter to use`, (string _, string value) {
            switch (value) {
            case "dap":
                osettings.adapter.type = AdapterType.dap;
                break;
            case "mi":
                osettings.adapter.type = AdapterType.mi;
                break;
            case "mi2":
                osettings.adapter.type = AdapterType.mi2;
                break;
            case "mi3":
                osettings.adapter.type = AdapterType.mi2;
                break;
            case "mi4":
                osettings.adapter.type = AdapterType.mi4;
                break;
            default:
                write("Invalid adapter. Available adapters listed below.\n\n");
                cliListAdapters();
            }
        },
        /*"d|debugger",``, (string _, string value) {
            
        },*/
        "list-adapters",  `List available adapters`, &cliListAdapters,
        "log",      `Logger: Enable logging to stderr`, {
            logAddAppender(new ConsoleAppender());
        },
        "logfile",  `Logger: Enable logging to file path`, (string _, string path) {
            logAddAppender(new FileAppender(path));
        },
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
    logInfo("New instance with options %s", osettings);
    
    // Run server
    try startServer(osettings);
    catch (Exception ex)
    {
        debug logCritical("Unhandled exception: %s", ex);
        else  logCritical(`/!\ Unhandled exception: %s`, ex.msg);
        exit(2);
    }
}
