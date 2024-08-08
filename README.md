# Aliceserver

Debugger server supporting the DAP and MI protocols using
[Alicedbg](https://github.com/dd86k/alicedbg).

Major work in progress! Don't expect it to replace GDB or LLDB any time soon.

Why?

- lldb-mi is generally not available as prebuilt binaries anymore after LLDB 9.0.1.
- lldb-vscode/lldb-dap requires Python.
- gdb-mi is fine, but GDC is generally unavailable on Windows.
- gdb-dap uses and requires Python.
- mago-mi is only available for Windows on x86/AMD64 platforms.
- Making this server provides a better direction for future Alicedbg features.

# Implementation Details

## DAP

The [Debugger Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/) (DAP)
is a protocol introduced in Visual Studio Code.

The protocol leaves a lot of nuance regarding implementation
details, which can be a little infuriating to work with.

This chapter reuses terminology from DAP, such as _Integer_ meaning, strictly
speaking, a 32-bit integer number (`int`), and _Number_ meaning a 64-bit
double-precision floating-point number (`double`, IEEE 754).

DAP is capable of initiating multiple debugging sessions.

Aliceserver does not yet support multi-session.

### Connection Details

By default, single-session mode is used, where standard streams are used
to communicate with the client (tool).

Messages are encoded in JSON using an HTTP-like wrapper.

In single-session mode, the server starts by reading a line from the program's
_standard input stream_ ("stdin") by reading characters until a newline is
seen, then reads an empty line.

This is used to get the (currently only) HTTP-like header field, `Content-Length`,
describing the size of the HTTP body. Then, the server reads N amount of bytes
described by the `Content-Length` field as an Integer.

A typical request may look like this:

```text
Content-Length: 82\r\n
\r\n
{"seq":1,"type":"request","command":"initialize","arguments":{"adapterId":"test"}}
```

And a typical response may look like this:

```text
Content-Length: 81\r\n
\r\n
{"command":"initialize","request_seq":1,"seq":1,"success":true,"type":"response"}
```

Both client and server maintain their own sequence number, starting at 1.

NOTE: lldb-vscode starts their seq number at 0, while not as per specification,
it poses no changes to its usage.

Multi-session mode is not currently supported.

### Supported Requests

Implementation-specific details:
- `launch` request:
  - `arguments:path`: (Required) [String] File path.
- `attach` request:
  - `arguments:pid`: (Required) [Integer] Process ID.

Command support:

| Command | Supported? | Comments |
|---|---|---|
| `attach` | ✔️ | `__restart` argument not supported. |
| `breakpointLocations` | ❌ | |
| `completions` | ❌ | |
| `configurationDone` | ❌ | |
| `continue` | ❌ | |
| `dataBreakpointInfo` | ❌ | |
| `disassemble` | ❌ | |
| `disconnect` | ✔️ | |
| `evaluate` | ❌ | |
| `exceptionInfo` | ❌ | |
| `goto` | ❌ | |
| `gotoTargets` | ❌ | |
| `initialize` | ✔️ | Locale is not supported. |
| `launch` | ✔️ | `noDebug` and `__restart` are not supported. |
| `loadedSources` | ❌ | |
| `modules` | ❌ | |
| `next` | ❌ | |
| `pause` | ❌ | |
| `readMemory` | ❌ | |
| `restart` | ❌ | |
| `restartFrame` | ❌ | |
| `reverseContinue` | ❌ | |
| `scopes` | ❌ | |
| `setBreakpoints` | ❌ | |
| `setDataBreakpoints` | ❌ | |
| `setExceptionBreakpoints` | ❌ | |
| `setExpression` | ❌ | |
| `setFunctionBreakpoints` | ❌ | |
| `setInstructionBreakpoints` | ❌ | |
| `setVariable` | ❌ | |
| `source` | ❌ | |
| `stackTrace` | ❌ | |
| `stepBack` | ❌ | |
| `stepIn` | ❌ | |
| `stepInTargets` | ❌ | |
| `stepOut` | ❌ | |
| `terminate` | ❌ | |
| `terminateThreads` | ❌ | |
| `threads` | ❌ | |
| `variables` | ❌ | |
| `writeMemory` | ❌ | |

### Supported Events

| Event | Supported? | Comments |
|---|---|---|
| `breakpoint` | ❌ | |
| `capabilities` | ❌ | |
| `continued` | ❌ | |
| `exited` | ❌ | |
| `initialized` | ❌ | |
| `invalidated` | ❌ | |
| `loadedSource` | ❌ | |
| `memory` | ❌ | |
| `module` | ❌ | |
| `output` | ❌ | |
| `process` | ❌ | |
| `progressEnd` | ❌ | |
| `progressStart` | ❌ | |
| `progressUpdate` | ❌ | |
| `stopped` | ❌ | |
| `terminated` | ❌ | |
| `thread` | ❌ | |
  
## MI

The [Machine Interface](https://sourceware.org/gdb/current/onlinedocs/gdb.html/GDB_002fMI.html)
protocol is a line-oriented protocol introduced in GDB.

To my knowledge, MI is not capable of multi-session.

### Connection Details

In a typical setting, MI uses the standard streams to communicate with the child
process.

Once the server starts running, it may already emiting log streams,
until `(gdb)\n` is printed, indicating that the server is ready to receive
commands.

Commands are roughly the same as you would use on GDB:

```text
attach 12345\n
```

Replies to commands start with a `^` character:

```text
^done\n
```

Or on error (note: `\\n` and `\\"` denote c-string formatting as-is):

```text
^error,msg="Example text.\\n\\nValue: \\"Test\\""\n
```

Events, console streams, logs, start with a significant unique character.

For example, command input (e.g., `test\n`) will be replied as `&"test\\n"\n`
using c-string formatting.

| Reply/Event | Character | Description |
|---|---|---|
| Result | `^` | Used to reply to a command, if successful or errorneous. |
| Exec | `*` | Async execution state changed. |
| Notify | `=` | Async notification related to the debugger. |
| Status | `+` | Async status change. |
| Console Stream | `~` | Console output. |
| Target Stream | `@` | |
| Log Stream | `&` | Typically for repeating commands as interpreted by the server. |

Some commands may start with `-`.

### Supported Requests

NOTE: LLDB command variants currently not supported.

| Request | Commands | Supported? | Comments |
|---|---|---|---|
| Attach | `attach` | ✔️ | |
| Launch | `exec-run` | ❌ | |

### Supported Events

TODO.

# Licensing

This project is licensed under the BSD-3-Clause-Clear license.