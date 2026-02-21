/// Main application command-line interface.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module main;

import std.stdio;
import std.getopt;
import std.conv : text;
import core.stdc.stdlib : exit;
import aliceserver;
import ddlogger;
import adbg.platform : ADBG_VERSION;

// TODO: Attach available adapter types
//       e.g., register them before calling getopt or statically in global memory

debug enum LogLevel DEFAULT_LOGLEVEL = LogLevel.trace;
else  enum LogLevel DEFAULT_LOGLEVEL = LogLevel.info;

template VER(uint ver)
{
    enum VER =
        cast(char)((ver / 1000) + '0') ~ "." ~
        cast(char)(((ver % 1000) / 100) + '0') ~
        cast(char)(((ver % 100) / 10) + '0') ~
        cast(char)((ver % 10) + '0');
}

void main(string[] args)
{
    ServerSettings osettings;
    LogLevel olevel = DEFAULT_LOGLEVEL;
    
    //uint ologlevel;
    GetoptResult gres = void;
    try
    {
        // TODO: --list-capabilities: List DAP capabilities and GDB/MI features
        gres = getopt(args,
        //
        // Adapter options
        //
        "list-adapters",  `List available adapters`, {
            writeln("Adapters:");
            writeln("dap ....... Debug Adapter Protocol (default)");
            writeln("mi ........ GDB/MI (GDB Machine Interface), latest version");
            writeln("mi2 ....... GDB/MI version 2");
            writeln("mi3 ....... GDB/MI version 3");
            writeln("mi4 ....... GDB/MI version 4");
            exit(0);
        },
        config.required,
        "a|adapter",`Set adapter to use`, (string _, string value) {
            switch (value) {
            case "dap": osettings.adapter = AdapterType.dap; break;
            case "mi":  osettings.adapter = AdapterType.mi; break;
            case "mi2": osettings.adapter = AdapterType.mi2; break;
            case "mi3": osettings.adapter = AdapterType.mi3; break;
            case "mi4": osettings.adapter = AdapterType.mi4; break;
            default:
                throw new Exception(text("Invalid adapter: '", value, "'.",
                    " A full list can be read using --list-adapters"));
            }
        },
        //
        // Transport options
        //
        "host",     "Set listening interface for TCP transport",
        (string _, string val)
        {
            osettings.host = val;
        },
        "port",     "Use TCP transport and set listening port",
        (string _, string val)
        {
            import std.conv : to;
            osettings.port = to!ushort(val);
            osettings.transport = TransportType.tcp;
        },
        "pipe",     "Set name or path for pipe/unix transport",
        (string _, string val)
        {
            osettings.host = val;
            osettings.transport = TransportType.pipe;
        },
        //
        // Logging
        //
        "log",      `Logger: Enable logging to stderr`, {
            logAddAppender(new ConsoleAppender());
        },
        "logfile",  `Logger: Enable logging to file path`, (string _, string path) {
            logAddAppender(new FileAppender(path));
        },
        "loglevel", `Logger: Set log level (default=info)`, &olevel,
        // bundling+cumulative is possible, but defaults to trace in debug builds atm
        //config.bundling, "v+", `Verbose`, &ologlevel,
        //
        // Pages
        //
        "ver",      `Show only version and quit`, {
            writeln(PROJECT_VERSION);
            exit(0);
        },
        "version",  `Show version page and quit`, {
            static immutable string verpage =
            "aliceserver " ~ PROJECT_VERSION ~ "\n"~
            "            Built: " ~ __TIMESTAMP__ ~ "\n"~
            "            Compiler: " ~ __VENDOR__ ~ " " ~ VER!__VERSION__ ~ "\n"~
            "            " ~ PROJECT_COPYRIGHT ~ "\n"~
            "            " ~ PROJECT_LICENSE ~ "\n"~
            "alicedbg    " ~ ADBG_VERSION ~ "\n";
            
            write(verpage);
            exit(0);
        }
        );
    }
    catch (Exception ex)
    {
        stderr.writeln("Error: ", ex.msg);
        exit(1);
    }
    
    if (gres.helpWanted)
    {
        static immutable int optpad = -16;
        gres.options[$-1].help = "Show this help page and quit";
        writeln("Debugger server\n\nOPTIONS");
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
    logSetLevel(olevel);
    logInfo("Server options: %s", osettings);
    
    // Run server
    try startServer(osettings);
    catch (Exception ex)
    {
        debug logCritical("Unhandled exception: %s", ex);
        else  logCritical(`/!\ Unhandled exception: %s`, ex.msg);
        exit(2);
    }
}
