# Aliceserver

Debugger server supporting the DAP and MI protocols using
[Alicedbg](https://github.com/dd86k/alicedbg).

**Major work in progress!** Don't expect it to replace GDB or LLDB any time soon.

Why?

- lldb-mi is no longer available as a prebuilt binary after LLDB 9.0.1.
- lldb and variants (including lldb-vscode) all require the Python runtime.
- gdb-mi is fine, but GDC is generally unavailable for Windows.
- gdb-dap is written in Python and thus requires it.
- Mago, and mago-mi, are only available for Windows on x86/AMD64 platforms.
- Provides future directions for features in Alicedbg.

Use cases:

- Integrating your favorite text or code editor that implements a debugger UI
- Automated debugging integration testing

# Implementation Details

```text
+-------------------------------------------+
| Aliceserver                               |
| +---------------------------------------+ |
| |           Debugger server             | |
| +---------------------------------------+ |
|      ^               ^            ^       |
|      v               |            |       |
| +-----------+        |            |       |
| | Adapter   |        v            v       |
| +-----------+   +----------+ +----------+ |
| | Transport |   | Debugger | | Debugger | |
+-+-----------+---+----------+-+----------+-+
       ^               ^            ^
       v               v            v
   +~~~~~~~~~+    +~~~~~~~~~+  +~~~~~~~~~+
   | Client  |    | Process |  | Process |
   +~~~~~~~~~+    +~~~~~~~~~+  +~~~~~~~~~+
```

Aliceserver is implemented using an Object-Oriented Programming model.

The debugger server provides types and structures that the adapters and
debuggers must interpret.

Aliceserver does not yet support multi-session.

## Transports

Each transport classes inherit `transport.base.ITransport`.

Available transports:
- `StdioTransport`: Implements a transport using standard streams.
- `HTTPStdioTransport`: Implements a transport using standard streams formatted as HTTP.
  The payload is given to the adapter to process.

## Adapters

Used to interface transports, translating requests and events.

Each adapter classes inherit `adapter.base.Adapter` and must be
constructed with a valid `ITransport` instance.

Available adapters:
- `DAPAdapter`: Implements an adapter that interprets the Debug Adapter Protocol.
  - Works best with `HTTPStdioTransport`.
- `MIAdapter`: Implements an adapter that interprets GDB's Machine Interface.
  - Works best with `StdioTransport`.

## Debuggers

Used to interface a debugger that manipulates processes.

Each debugger classes inherit `debugger.base.IDebugger`.

Right now, only `AlicedbgDebugger` is available as a debugger.

# Adapter Details

## DAP

[Debugger Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/) (DAP)
is a HTTP-like JSON protocol that was introduced in
[vscode-debugadapter-node](https://github.com/microsoft/vscode-debugadapter-node)
and was readapted as a
[standalone protocol](https://github.com/microsoft/debug-adapter-protocol)
for debugging various processes and runtimes in Visual Studio Code.

The protocol leaves a lot of nuance regarding implementation
details, which can be a little infuriating to work with.

This chapter reuses terminology from DAP, such as _Integer_ meaning, strictly
speaking, a 32-bit integer number (`int`), and _Number_ meaning a 64-bit
double-precision floating-point number (IEEE 754 `double`).

### Connection Details

DAP has two connection models: Single-session and multi-session.
- Single-session: Using standard I/O (stdio), a single adapter instance is started.
- Multi-session: Using TCP/IP, every new connection initiates a new adapter instance.

Messages are encoded as HTTP messages using the UTF-8 encoding.

Currently, there is only one header field, `Content-Length`, that determines the
length of the message (payload). This field is read as an Integer.

The body (payload) is assumed to be encoded as [JSON](https://json.org).

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
| `terminate` | ✔️ | |
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
| `exited` | ✔️ | |
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
| Console Stream | `~` | Console messages intended to be printed. |
| Target Stream | `@` | Program output when truly asynchronous, for remote targets. |
| Log Stream | `&` | Internal debugger messages. |

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

| Request | Details | Supported? | Comments |
|---|---|---|---|
| Continued | | ✔️ | |
| Exited | Reasons: `exited`, `exited-normally` | ✔️ | |
| Output | | ❌ | |
| Stopped | | ❌ | |

# Licensing

This project is licensed under the BSD-3-Clause-Clear license.