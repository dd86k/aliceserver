/// Automated GDB/MI integration tests.
///
/// Spawns aliceserver with -i mi, sends MI commands, and asserts on responses.
/// Run with: rdmd test_mi_integration.d
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module test_mi_integration;

import std;
import core.thread;

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
    bool verbose;
    bool isGdb;     // true when testing against real GDB
}

void log(A...)(char op, string fmt, A args)
{
    if (verbose == false)
    switch (op) {
    case Op.trace, Op.receiving, Op.sending: return;
    default:
    }

    stderr.write("TEST[", op, "]: ");
    stderr.writefln(fmt, args);
}

struct MIResponse
{
    string[] lines;       // all raw lines (including ~, &, = prefixed)
    string resultLine;    // the ^... line (with token prefix if any)
    string resultClass;   // "done", "error", "exit", "running"
    string resultBody;    // everything after ^class, or ^class,
}

/// Read lines from server stdout until "(gdb)" prompt.
string[] readUntilPrompt()
{
    string[] lines;
    while (true)
    {
        string line = stripRight(server.stdout.readln());
        log(Op.receiving, "%s", line);

        if (line is null)
            break; // EOF

        if (line == "(gdb)")
            break;

        if (line.length > 0)
            lines ~= line;
    }
    return lines;
}

/// Send a command and collect the response.
MIResponse send(string command)
{
    log(Op.sending, "%s", command);
    server.stdin.write(command, '\n');
    server.stdin.flush();

    string[] lines = readUntilPrompt();

    MIResponse resp;
    resp.lines = lines;

    // Find the result record (line starting with optional digits then ^)
    foreach (line; lines)
    {
        // Skip stream/async records
        if (line.length == 0)
            continue;

        // Find ^ in the line - it could be preceded by token digits
        auto caretIdx = line.indexOf('^');
        if (caretIdx < 0)
            continue;

        // Verify everything before ^ is digits (token)
        bool isResult = true;
        foreach (ch; line[0 .. caretIdx])
        {
            if (!ch.isDigit)
            {
                isResult = false;
                break;
            }
        }
        if (!isResult)
            continue;

        resp.resultLine = line;

        // Parse result class and body from after ^
        string afterCaret = line[caretIdx + 1 .. $];
        auto commaIdx = afterCaret.indexOf(',');
        if (commaIdx >= 0)
        {
            resp.resultClass = afterCaret[0 .. commaIdx];
            resp.resultBody = afterCaret[commaIdx + 1 .. $];
        }
        else
        {
            resp.resultClass = afterCaret;
            resp.resultBody = "";
        }
        break;
    }

    return resp;
}

// --- Test infrastructure ---

struct TestResult
{
    string name;
    bool passed;
    string failMsg;
}

TestResult[] results;
int testsPassed;
int testsFailed;

alias TestFunc = void function();

struct TestEntry
{
    string name;
    TestFunc func;
}

TestEntry[] allTests;

void registerTest(string name, TestFunc func)
{
    allTests ~= TestEntry(name, func);
}

void runTest(TestEntry test)
{
    try
    {
        test.func();
        writefln("[PASS] %s", test.name);
        results ~= TestResult(test.name, true, "");
        testsPassed++;
    }
    catch (Exception e)
    {
        writefln("[FAIL] %s: %s", test.name, e.msg);
        results ~= TestResult(test.name, false, e.msg);
        testsFailed++;
    }
}

void assertDone(MIResponse resp, string context = "")
{
    if (resp.resultClass != "done")
        throw new Exception(
            format(`expected "^done" but got "^%s"%s`,
                resp.resultClass,
                context.length ? " (" ~ context ~ ")" : ""));
}

void assertError(MIResponse resp, string msgSubstring = "")
{
    if (resp.resultClass != "error")
        throw new Exception(
            format(`expected "^error" but got "^%s"`, resp.resultClass));
    if (msgSubstring.length > 0 && !resp.resultBody.canFind(msgSubstring))
        throw new Exception(
            format(`error body missing "%s", got: %s`, msgSubstring, resp.resultBody));
}

void assertResult(MIResponse resp, string expectedClass)
{
    if (resp.resultClass != expectedClass)
        throw new Exception(
            format(`expected "^%s" but got "^%s"`, expectedClass, resp.resultClass));
}

void assertLinesContain(MIResponse resp, string substring)
{
    foreach (line; resp.lines)
        if (line.canFind(substring))
            return;
    throw new Exception(
        format(`no line contains "%s"`, substring));
}

// --- Test definitions ---

static this()
{
    registerTest("show_version", &test_show_version);
    registerTest("environment_pwd", &test_environment_pwd);
    registerTest("info_cmd_exists", &test_info_cmd_exists);
    registerTest("info_cmd_nonexistent", &test_info_cmd_nonexistent);
    registerTest("list_features", &test_list_features);
    registerTest("file_exec_and_symbols", &test_file_exec_and_symbols);
    registerTest("file_exec_and_symbols_error", &test_file_exec_and_symbols_error);
    registerTest("exec_arguments", &test_exec_arguments);
    registerTest("gdb_set", &test_gdb_set);
    registerTest("unknown_command", &test_unknown_command);
    registerTest("empty_command", &test_empty_command);
    registerTest("dash_only", &test_dash_only);
    registerTest("token_handling", &test_token_handling);
    registerTest("gdb_exit", &test_gdb_exit); // must be last
}

void test_show_version()
{
    auto resp = send("show version");
    assertDone(resp);
    // aliceserver: ~"GNU gdb compatible Aliceserver ...", GDB: ~"GNU gdb ..."
    assertLinesContain(resp, `~"GNU gdb`);
}

void test_environment_pwd()
{
    auto resp = send("-environment-pwd");
    assertDone(resp);
    if (!resp.resultBody.canFind("cwd="))
        throw new Exception(
            format(`body missing "cwd=", got: %s`, resp.resultBody));
}

void test_info_cmd_exists()
{
    // Use list-features: a real MI command recognized by both GDB and aliceserver
    auto resp = send("-info-gdb-mi-command list-features");
    assertDone(resp);
    if (!resp.resultBody.canFind(`exists="true"`))
        throw new Exception(
            format(`body missing exists="true", got: %s`, resp.resultBody));
}

void test_info_cmd_nonexistent()
{
    auto resp = send("-info-gdb-mi-command nonexistent");
    assertDone(resp);
    if (!resp.resultBody.canFind(`exists="false"`))
        throw new Exception(
            format(`body missing exists="false", got: %s`, resp.resultBody));
}

void test_list_features()
{
    auto resp = send("-list-features");
    assertDone(resp);
    if (!resp.resultBody.canFind("features="))
        throw new Exception(
            format(`body missing "features=", got: %s`, resp.resultBody));
}

void test_file_exec_and_symbols()
{
    auto resp = send("-file-exec-and-symbols /bin/true");
    assertDone(resp);
}

void test_file_exec_and_symbols_error()
{
    auto resp = send("-file-exec-and-symbols a b");
    // GDB: only processes first arg, errors "No such file"
    // aliceserver: rejects multiple args
    if (isGdb)
        assertError(resp, "No such file");
    else
        assertError(resp, "Unrecognized argument");
}

void test_exec_arguments()
{
    auto resp = send("-exec-arguments arg1 arg2");
    assertDone(resp);
}

void test_gdb_set()
{
    // GDB errors on unknown set variables; aliceserver accepts silently
    auto resp = send("-gdb-set something");
    if (isGdb)
        assertError(resp);
    else
        assertDone(resp);
}

void test_unknown_command()
{
    auto resp = send("-blah-nonexistent");
    // GDB: "Undefined MI command", aliceserver: "Unknown request"
    if (isGdb)
        assertError(resp, "Undefined MI command");
    else
        assertError(resp, "Unknown request");
}

void test_empty_command()
{
    auto resp = send("");
    assertDone(resp);
}

void test_dash_only()
{
    auto resp = send("-");
    // GDB: ^error (undefined MI command ""), aliceserver: ^done
    if (isGdb)
        assertError(resp);
    else
        assertDone(resp);
}

void test_token_handling()
{
    auto resp = send("123-list-features");
    assertDone(resp);
    if (!resp.resultLine.startsWith("123^done"))
        throw new Exception(
            format(`result line should start with "123^done", got: %s`, resp.resultLine));
}

void test_gdb_exit()
{
    auto resp = send("-gdb-exit");
    assertResult(resp, "exit");
}

// --- Main ---

int main(string[] args)
{
    string oserver;
    string otestFilter;
    bool olist;

    GetoptResult ores;
    try
    {
        ores = getopt(args,
            "s|server",  "Server path (default=./aliceserver)", &oserver,
            "t|test",    "Run specific test by name", &otestFilter,
            "l|list",    "List test names", &olist,
            "v|verbose", "Show protocol traffic", &verbose,
        );
    }
    catch (Exception ex)
    {
        stderr.writefln("Error: %s", ex.msg);
        return 1;
    }

    if (ores.helpWanted)
    {
        defaultGetoptPrinter(
`MI integration tests for aliceserver

OPTIONS`, ores.options);
        return 0;
    }

    if (olist)
    {
        foreach (test; allTests)
            writeln(test.name);
        return 0;
    }

    // Resolve server and build launch args
    string[] svropts;
    switch (oserver) {
    case "gdb":
        svropts = ["gdb", "-i", "mi", "--quiet"];
        isGdb = true;
        break;
    case "":
        // Auto-build if needed
        if (!exists(defaultServer))
        {
            log(Op.important, "Server not found locally, building...");
            int code = wait(spawnProcess(["dub", "build"]));
            if (code)
            {
                log(Op.error, "Compilation ended in error, aborting");
                return code;
            }
        }
        svropts = [defaultServer, "-i", "mi"];
        break;
    default:
        svropts = [oserver];
    }

    // Spawn server
    log(Op.info, "Starting server: %s", svropts.join(" "));
    server = pipeProcess(svropts, Redirect.stdin | Redirect.stdout);
    Thread.sleep(250.msecs);
    if (tryWait(server.pid).terminated)
    {
        log(Op.error, "Could not launch server");
        return 2;
    }

    // Read initial (gdb) prompt
    // This is because GDB without -q tend to send a wall of text
    readUntilPrompt();

    // Filter tests if requested
    TestEntry[] testsToRun;
    if (otestFilter.length)
    {
        foreach (test; allTests)
            if (test.name == otestFilter)
                testsToRun ~= test;
        if (testsToRun.length == 0)
        {
            stderr.writefln("Unknown test: %s", otestFilter);
            // Still need to clean up server
            server.stdin.write("-gdb-exit\n");
            server.stdin.flush();
            wait(server.pid);
            return 1;
        }
    }
    else
    {
        testsToRun = allTests;
    }

    // Run tests
    foreach (test; testsToRun)
        runTest(test);

    // If gdb_exit wasn't run as part of tests, shut down the server
    if (!testsToRun.canFind!(t => t.name == "gdb_exit"))
    {
        send("-gdb-exit");
    }

    // Wait for server to terminate
    wait(server.pid);

    // Summary
    int total = testsPassed + testsFailed;
    writefln("\nResults: %d passed, %d failed, %d total", testsPassed, testsFailed, total);

    return testsFailed > 0 ? 1 : 0;
}
