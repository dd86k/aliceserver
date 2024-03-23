# Aliceserver

Debugger server supporting the DAP protocol using Alicedbg.

Major work in progress! Don't expect it to replace GDB or LLDB.

# Implementation Details

## DAP

The Debugger Adapter Protocol leaves a lot of nuance regarding implementation
details, which can be a little infuriating to work with.

This chapter reuses terminology from DAP, such as _Integer_ meaning, strictly
speaking, a 32-bit integer number (`int`), and _Number_ meaning a 64-bit
double-precision floating-point number (`double`, IEEE 754).

### Connection

By default, single-session mode is used, where standard streams are used
to communicate with the client (tool).

In single-session mode, the server starts by reading a line from the program's
_standard input stream_ ("stdin") by reading characters until a newline is
seen, then reads an empty line.

This is used to get the (currently only) HTTP-like header field, `Content-Length`,
describing the size of the HTTP body. Then, the server reads N amount of bytes
described by the `Content-Length` field as an Integer.

A typical message may look like this:

```text
Content-Length: 82\r\n
\r\n
{"seq":1,"type":"request","command":"initialize","arguments":{"adapterId":22"test"}}
```

Both client and server maintain their own sequence number, starting at 1.

NOTE: lldb-vscode starts their seq number at 0.

Multi-session mode is not currently supported.

### Requests

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

### Events

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

The Machine Interface protocol is currently not supported, but could be in
some future.

# Licensing

This project is licensed under the BSD-3-Clause-Clear license.