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

[Debugger Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/) (DAP)
is a HTTP-like protocol using JSON that was introduced in
[vscode-debugadapter-node](https://github.com/microsoft/vscode-debugadapter-node)
and was readapted as a
[standalone protocol](https://github.com/microsoft/debug-adapter-protocol)
for debugging various processes and runtimes in Visual Studio Code.

The protocol leaves a lot of nuance regarding implementation
details, which can be a little infuriating to work with.

This chapter reuses terminology from DAP, such as _Integer_ meaning, strictly
speaking, a 32-bit integer number (`int`), and _Number_ meaning a 64-bit
double-precision floating-point number (`double`, IEEE 754).

DAP is capable of initiating multiple debugging sessions, also known as a
multi-session configuration

Aliceserver does not yet support multi-session.

### Connection Details

By default, single-session mode is used. A client may request to initiate a new
debugging session by emiting the `startDebugging` request, which turns the server
configuration into a multi-session mode.

In either modes, the client spawns the server and uses the standard streams (stdio)
to communicate with the server.

Messages are encoded as HTTP messages using JSON for its body, where the header and body
of the message are separated by two HTTP newlines ("\r\n").

Currently, there is only one header field, `Content-Length`, that determines the
length of the message. This includes requests, replies, and events. This field is
read as an Integer (32-bit integer number, `int`).

This is important since streams are of inderminate sizes, unlike TCP packets.

The body of the message is encoded using [JSON](https://json.org).

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
it poses no difference to its usage.

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

[Machine Interface](https://sourceware.org/gdb/current/onlinedocs/gdb.html/GDB_002fMI.html)
is a line-oriented protocol introduced in GDB 5.1.

To my knowledge, MI is not capable of multi-session.

### Connection Details

In a typical setting, MI uses the standard streams to communicate with the child
process.

Once the server starts running, it may already emit console streams, until
`(gdb)\n` is printed, indicating that the server is ready to receive commands.

Commands are almost the same as you would use on GDB:

```text
attach 12345\n
```

Replies to commands start with a `^` character:

```text
^done\n
```

Or on error (note: `\\n` and `\\"` denote c-string formatting):

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
| Console Stream | `~` | Console informational message from debugger. |
| Target Stream | `@` | Program output. |
| Log Stream | `&` | Server repeated command for logging purposes. |

Some commands may start with `-`.

### Supported Requests

NOTE: Command focus is on GDB, lldb-mi commands may work.

| Request | Commands | Supported? | Comments |
|---|---|---|---|
| Attach | `attach` | ✔️ | |
| Launch | `-exec-run`, `target exec`, `-exec-arguments` | ✔️ | |
| Continue | `-exec-continue` | ✔️ | |
| Terminate | `-exec-abort` | ✔️ | |
| Detach | `-exec-detach`, `detach` | ✔️ | |
| Set working directory | `environment-directory` | ✔️ | |
| Disconnect | `q`, `quit`, `-gdb-exit` | ✔️ | |

### Supported Events

TODO.

# Licensing

This project is licensed under the BSD-3-Clause-Clear license.