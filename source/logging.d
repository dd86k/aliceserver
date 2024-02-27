/// Logging facility.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module logging;

//NOTE: Made this since std.logger does a weird thing with its log level

import std.stdio;
import std.datetime;
import std.datetime.stopwatch;
import std.container;
import std.format;
import std.conv;

/// Log level used on a per-message basis.
enum LogLevel
{
    none,
    critical,
    error,
    warning,
    info,
    trace,
}

/// Log message given to all appenders.
struct LogMessage
{
    LogLevel level;
    SysTime time;
    long usecs;
    const(char)[] text;
}

/// Get the name of a level.
///
/// This excludes "none".
/// Params: level = LogLevel value.
/// Returns: Name, like "CRITICAL".
string logLevelName(LogLevel level)
{
    static immutable string[5] leveltable = [
        "CRITICAL",
        "ERROR",
        "WARNING",
        "INFO",
        "TRACE",
    ];
    size_t idx = level-1;
    return idx < leveltable.length ? leveltable[idx] : "???";
}

/// Main interface for implementing and appender.
interface IAppender
{
    void log(ref LogMessage message);
}
class ConsoleAppender : IAppender
{
    this()
    {
    }
    
    void log(ref LogMessage message)
    {
        enum second_us = 1_000_000;
        long secs = message.usecs / second_us;
        long frac = message.usecs % second_us;
        // NOTE: 999,999 seconds is 277,8 Hours, so 6 digits is okay
        // NOTE: stderr is not buffered by default (vs. stdout/stdin)
        stderr.writefln("[%6d.%06d] %-8s %s",
            secs, frac, logLevelName(message.level), message.text);
    }
}
class FileAppender : IAppender
{
    File file;
    
    this(string path)
    {
        file = File(path, "a");
    }
    
    void log(ref LogMessage message)
    {
        file.writefln("%-24s %-8s %s",
            message.time.toISOExtString(),
            logLevelName(message.level),
            message.text);
        file.flush();
    }
}

private __gshared
{
    LogLevel loglevel;
    Array!IAppender appenders;
    char[1024] msgbuf;
    StopWatch watch;
}

shared static this()
{
    watch.start();
    appenders = Array!IAppender();
}

void logSetLevel(LogLevel level)
{
    loglevel = level;
}

void logAddAppender(IAppender appender)
{
    appenders.insertBack(appender);
}

private
void log(LogLevel level, const(char)[] message, string mod)
{
    if (appenders.length == 0) return;
    if (level > loglevel) return;
    
    Duration since = watch.peek();
    // NOTE: currTime takes ~500 µs to get time on Windows
    SysTime time = Clock.currTime();
    
    scope msgtext = text(mod, ": ", message);
    LogMessage msg = LogMessage(level,
        time,
        since.total!"usecs"(),
        msgtext);
    
    // NOTE: This could be done using parallel()
    foreach (appender; appenders)
    {
        appender.log(msg);
    }
}

void logCritical(A...)(string fmt, A args, string mod = __MODULE__)
{
    if (appenders.length == 0) return;
    if (loglevel < LogLevel.critical) return;
    
    log(LogLevel.critical, sformat(msgbuf, fmt, args), mod);
}
void logError(A...)(string fmt, A args, string mod = __MODULE__)
{
    if (appenders.length == 0) return;
    if (loglevel < LogLevel.error) return;
    
    log(LogLevel.error, sformat(msgbuf, fmt, args), mod);
}
void logWarn(A...)(string fmt, A args, string mod = __MODULE__)
{
    if (appenders.length == 0) return;
    if (loglevel < LogLevel.warning) return;
    
    log(LogLevel.warning, sformat(msgbuf, fmt, args), mod);
}
void logInfo(A...)(string fmt, A args, string mod = __MODULE__)
{
    if (appenders.length == 0) return;
    if (loglevel < LogLevel.info) return;
    
    log(LogLevel.info, sformat(msgbuf, fmt, args), mod);
}
void logTrace(A...)(string fmt, A args, string mod = __MODULE__)
{
    if (appenders.length == 0) return;
    if (loglevel < LogLevel.trace) return;
    
    log(LogLevel.trace, sformat(msgbuf, fmt, args), mod);
}
