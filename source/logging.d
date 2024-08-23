/// Logging facility.
///
/// Inspired by Apache log4net, without the hierarchy.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module logging;

import std.stdio;
import std.datetime;
import std.datetime.stopwatch;
import std.container : Array;
import std.format;
import std.conv;
import core.sync.mutex;

// NOTE: Made this since std.logger does a weird non-linear thing with its log level.

// TODO: Message passing
//       To avoid slowing down the caller thread, formatting on a different thread
//       would be beneficial. The issue would be the thread mailbox and how to handle
//       a full mailbox.
//       Make feature opt-in.

// TODO: Appender ideas
//       MemoryAppender
//       ColoredConsoleAppender
//       SyslogAppender

// TODO: Flag/function to enable "debug info"? Like module/line.

/// Log level used on a per-message basis.
///
/// The higher the level, the more verbose the logger will be. As in,
/// "give me more information".
enum LogLevel
{
    /// Silence. Appender is disabled.
    none,
    
    /// When the execution of the entire program cannot continue.
    critical,
    /// When a specific action resulted in an error.
    error,
    /// When a specific action can continue, but its setting was not optimal.
    warning,
    /// Informational message.
    info,
    /// Debugging messages.
    debugging,
    /// Information dumps and traces.
    trace,
    
    /// Include every log message possible.
    all,
}

/// Log message given to all appenders.
struct LogMessage
{
    /// Log level.
    LogLevel level;
    /// System time.
    SysTime time;
    /// Time since startup.
    long usecs;
    /// Formatted text.
    const(char)[] text;
    /// Module.
    const(char)[] mod;
    /// Line.
    int line;
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
abstract class Appender
{
    void setLogLevel(LogLevel level)
    {
        loglevel = level;
    }
    LogLevel getLogLevel()
    {
        return loglevel;
    }
    void log(ref LogMessage message);

private:
    LogLevel loglevel;
}

/// Implements a logger that prints logs to the process's stderr stream.
class ConsoleAppender : Appender
{
    this()
    {
    }
    
    override
    void log(ref LogMessage message)
    {
        enum second_us = 1_000_000;
        long secs = message.usecs / second_us;
        long frac = message.usecs % second_us;
        // NOTE: 999,999 seconds is 277,8 Hours, so 6 digits is okay
        // NOTE: stderr is not buffered by default (vs. stdout/stdin)
        with (message)
        stderr.writefln("[%6d.%06d] %-8s [%s:%d] %s",
            secs, frac, logLevelName(level),
            mod, line,
            text);
    }
}

/// Implements a logger that prints logs to a file.
class FileAppender : Appender
{
    File file;
    
    this(string path)
    {
        file = File(path, "a");
    }
    
    override
    void log(ref LogMessage message)
    {
        // 2024-02-06T10:26:23.0468545
        with (message)
        file.writefln("%-27s %-8s [%s:%d] %s",
            time.toISOExtString(),
            logLevelName(level),
            mod, line, text);
        file.flush();
    }
}

private __gshared
{
    Array!Appender appenders;
    StopWatch watch;
    Mutex mutx;
}

shared static this()
{
    watch.start();
    appenders = Array!Appender();
    mutx = new Mutex();
}

/// Set log level to all appenders.
/// Params: level = New log level.
void logSetLevel(LogLevel level)
{
    foreach (appender; appenders)
        appender.setLogLevel(level);
}

void logAddAppender(Appender appender)
{
    appenders.insertBack(appender);
}

// Function template will make the target binary bigger but it is the
// only sane way to deal with format() and variadic parameters for it...
private
void logt(A...)(LogLevel level, string mod, int line, const(char)[] fmt, A args)
{
    if (appenders.length == 0) return;
    
Ltest:
    if (mutx.tryLock_nothrow() == false)
        goto Ltest;
    
    LogMessage msg = void;
    bool prepped;
    foreach (appender; appenders)
    {
        // Do not bother if the appender's level is too low against requested level
        if (appender.getLogLevel() < level)
            continue;
        
        // At least one appender has the required level, init message
        if (prepped == false)
        {
            Duration since = watch.peek();
            SysTime time = Clock.currTime(); // NOTE: takes ~500 µs on Windows
            msg = LogMessage(level,
                time,
                since.total!"usecs"(),
                format(fmt, args),
                mod,
                line);
            prepped = true;
        }
        
        // Send message to appender
        appender.log(msg);
    }
    
    mutx.unlock_nothrow();
}

void logCritical(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.critical, MODULE, LINE, fmt, args);
}
void logError(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.error, MODULE, LINE, fmt, args);
}
void logWarn(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.warning, MODULE, LINE, fmt, args);
}
void logInfo(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.info, MODULE, LINE, fmt, args);
}
void logDebugging(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.debugging, MODULE, LINE, fmt, args);
}
void logTrace(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.trace, MODULE, LINE, fmt, args);
}

unittest
{
    // Define custom appender
    class UnittestAppender : Appender
    {
        int count;
        
        LogMessage lastmsg;
        
        override
        void log(ref LogMessage message)
        {
            ++count;
            lastmsg = message;
        }
    }
    
    // Create new appender
    scope app = new UnittestAppender();
    app.setLogLevel(LogLevel.warning);
    assert(app.getLogLevel() == LogLevel.warning);
    
    // Add it to global list
    logAddAppender(app);
    assert(appenders.length == 1);
    
    // Set level to all (including ours)
    logSetLevel(LogLevel.all);
    assert(app.getLogLevel() == LogLevel.all);
    
    // Trace message
    logTrace("Here's a number: %d", 42);
    assert(app.lastmsg.mod == __MODULE__);
    assert(app.lastmsg.line);
    assert(app.lastmsg.text == "Here's a number: 42");
    assert(app.lastmsg.level == LogLevel.trace);
    assert(app.lastmsg.usecs);
    assert(app.lastmsg.time.day);
    
    // Set new level
    logSetLevel(LogLevel.warning);
    assert(app.getLogLevel() == LogLevel.warning);
    
    // TODO: Thread test
}