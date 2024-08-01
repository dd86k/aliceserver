/// Main application command-line interface.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module main;

import std.stdio;
import std.getopt;
import core.stdc.stdlib : exit;
import config;
import server;
import logging;
import adbg.platform : ADBG_VERSION;

debug
{
    private enum DEFAULT_LEVEL = LogLevel.trace;
}
else
{
    private enum DEFAULT_LEVEL = LogLevel.info;
}

void main(string[] args)
{
    LogLevel ologlevel = DEFAULT_LEVEL;
    string ologfile;
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
                throw new Exception(`Unknown adapter`);
            }
        },
        "list-adapters",  `List available adapters`, {
            writeln("Adapters:");
            writeln("dap .... (default) Debug Adapter Protocol");
            writeln("mi ..... GDB/MI (GDB Machine Interface)");
            exit(0);
        },
        "logpath",  `Logger: Set file path for logging`, &ologfile,
        "loglevel", `Logger: Set path`, &ologlevel,
        "ver",      `Show only version and quit`, {
            writeln(PROJECT_VERSION);
            exit(0);
        },
        "version",  `Show version page and quit`, {
            write(
            "aliceserver ", PROJECT_VERSION, "\n",
            "            Built ", __TIMESTAMP__, "\n",
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
        gres.options[$-1].help = "Show this help page and quit";
        defaultGetoptPrinter("Debugger server", gres.options);
        return;
    }
    
    // Setup logger
    logSetLevel(ologlevel);
    logAddAppender(new ConsoleAppender());
    if (ologfile)
        logAddAppender(new FileAppender(ologfile));
    
    try
    {
        serverStart(osettings);
    }
    catch (Exception ex)
    {
        debug logCritical("Unhandled Exception: %s", ex);
        else  logCritical(`/!\ %s`, ex.msg);
        exit(2);
    }
}
