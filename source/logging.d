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
import std.container : Array;
import std.format;
import std.conv;
import core.sync.mutex;

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
    void log(ref LogMessage message, string mod, int line);
}
class ConsoleAppender : IAppender
{
    this()
    {
    }
    
    void log(ref LogMessage message, string mod, int line)
    {
        enum second_us = 1_000_000;
        long secs = message.usecs / second_us;
        long frac = message.usecs % second_us;
        // NOTE: 999,999 seconds is 277,8 Hours, so 6 digits is okay
        // NOTE: stderr is not buffered by default (vs. stdout/stdin)
        stderr.writefln("[%6d.%06d] %-8s [%s:%d] %s",
            secs, frac, logLevelName(message.level),
            mod, line,
            message.text);
    }
}
class FileAppender : IAppender
{
    File file;
    
    this(string path)
    {
        file = File(path, "a");
    }
    
    void log(ref LogMessage message, string mod, int line)
    {
        // 2024-02-06T10:26:23.0468545
        file.writefln("%-27s %-8s [%s:%d] %s",
            message.time.toISOExtString(),
            logLevelName(message.level),
            mod, line,
            message.text);
        file.flush();
    }
}

private __gshared
{
    LogLevel loglevel;
    Array!IAppender appenders;
    StopWatch watch;
    
    Mutex mutx;
}

shared static this()
{
    watch.start();
    appenders = Array!IAppender();
    mutx = new Mutex();
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
void logt(A...)(LogLevel level, string mod, int line, const(char)[] fmt, A args)
{
    if (appenders.length == 0) return;
    if (level > loglevel) return;
    
Ltest:
    if (mutx.tryLock_nothrow() == false)
        goto Ltest;
    
    char[2048] buf = void;
    log(level, buf.sformat(fmt, args), mod, line);
    mutx.unlock_nothrow();
}
private
void log(LogLevel level, const(char)[] message, string mod, int line)
{
    Duration since = watch.peek();
    SysTime time = Clock.currTime(); // NOTE: takes ~500 µs on Windows
    LogMessage msg = LogMessage(level,
        time,
        since.total!"usecs"(),
        message);
    
    foreach (appender; appenders)
    {
        appender.log(msg, mod, line);
    }
}

void logCritical(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    if (appenders.length == 0) return;
    if (loglevel < LogLevel.critical) return;
    
    logt(LogLevel.critical, MODULE, LINE, fmt, args);
}
void logError(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    if (appenders.length == 0) return;
    if (loglevel < LogLevel.error) return;
    
    logt(LogLevel.error, MODULE, LINE, fmt, args);
}
void logWarn(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    if (appenders.length == 0) return;
    if (loglevel < LogLevel.warning) return;
    
    logt(LogLevel.warning, MODULE, LINE, fmt, args);
}
void logInfo(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    if (appenders.length == 0) return;
    if (loglevel < LogLevel.info) return;
    
    logt(LogLevel.info, MODULE, LINE, fmt, args);
}
void logTrace(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    if (appenders.length == 0) return;
    if (loglevel < LogLevel.trace) return;
    
    logt(LogLevel.trace, MODULE, LINE, fmt, args);
}
