# About Aliceserver

Aliceserver is a debugger server implementing the
[DAP](https://microsoft.github.io/debug-adapter-protocol/) and
[GDB/MI](https://sourceware.org/gdb/current/onlinedocs/gdb.html/GDB_002fMI.html#GDB_002fMI)
protocols, using [Alicedbg](https://github.com/dd86k/alicedbg) as the debugger back-end.

It combines all the transport and adapter options into one runtime, allowing
clients to run any adapter protocol under any transport media.

Supports (and tested on) Windows and Linux.

> [!WARNING]
> This is WORK IN PROGRESS!
> 
> Experimental project, don't expect it to replace GDB or LLDB any time soon.

Why? Tool related:
- lldb-mi is generally no longer available as a prebuilt binary after LLDB 9.0.1.
- lldb and variants (including lldb-vscode/lldb-dap) all require the Python runtime.
- gdb-mi is fine, but GDC is generally unavailable for Windows.
- gdb-dap is written in Python and thus requires it.
- Mago, and mago-mi, are only available for Windows on x86/AMD64 platforms.

# Usage

Typically, a debugger client will start the server on its own.

The adapter option (using `-i ADAPTER`, `-i=ADAPTER`, or `--interpreter=ADAPTER`) is required.

Adapters:
- `dap` for Debug Adapter Protocol.
- `mi` for GDB's Machine Interface. (also accepts `-q`)

To select a transport:
- Default is `stdio`, no extra arguments needed.
- Use `--port=PORT` to listen to this TCP port, defaults to the `localhost` interface.
- Use `--pipe=PATH` with a path (`\\.\pipe\example` or `/var/run/example`) or name (`example`).

## Examples

| Command | Description |
|---|---|
| `aliceserver -i dap` | DAP via stdio |
| `aliceserver -i mi --port=9090` | GDB/MI over TCP |
| `aliceserver -i mi --pipe=/run/aliceserver` | MI over UNIX socket (POSIX) |
| `aliceserver -i dap --pipe=\\.\pipe\example` | DAP over NamedPipe path (Windows) |
| `aliceserver -i dap --pipe=aliceserver` | DAP over NamedPipe/socket name |

With TCP and pipe options, deemed multi session, a new connection means a new
debugging session. Clients are still free to invoke additional single sessions (stdio)
to also simulate multiple sessions.

When a pipe name (and not a path) is given, these are the prefixes used:
- Windows: `\\.\pipe\`
- POSIX: `XDG_RUNTIME_DIR` variable or `/tmp` if unavailable, both adding `/` when building the path

Pipe path examples with `example`:
- Windows: `\\.\pipe\example` (with `PIPE_REJECT_REMOTE_CLIENTS`)
- POSIX: `/run/user/1000/example` when `XDG_RUNTIME_DIR` is set
- POSIX: `/tmp/example` when `XDG_RUNTIME_DIR` is unset

Implementation details, such as which commands are supported, are in [source/README.md](source/README.md).

# Building

You'll need DUB and a recent D compiler: DMD, GDC, or LDC.

Debug build: `dub build`

Release build: `dub build -b release`

DUB will automatically pull in the dependencies.

# Licensing

This project is licensed under the BSD-3-Clause-Clear license.