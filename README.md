# About Aliceserver

Aliceserver is a debugger server implementing the DAP and GDB/MI protocols, using
[Alicedbg](https://github.com/dd86k/alicedbg) as the debugger back-end.

It combines all the transport and adapter options into one runtime, allowing
clients to run any adapter protocol under any transport mediums.

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

Uses:
- Integrating your favorite text or code editor that implements a debugger UI.
- Automated debugging integration testing.
- Reusable high-level integration of Alicedbg.

# Usage

Typically, a debugger client (e.g., VSCode) will start the server on its own.

To select a transport:
- Default is `stdio`, no extra arguments needed.
- Use `--port=PORT` to listen to this TCP port, defaults to the `localhost` interface.
- Use `--pipe=PATH` with a path (`\\.\pipe\example` or `/var/run/example`) or name (`example`).

To select an adapter:
- `--adapter=dap` selects DAP, which is the default. No extra argument needed.
- `--adapter=mi` selects the latest MI version.

Examples:
- `aliceserver`: Without options, aliceserver starts with DAP via stdio.
- `aliceserver -a mi --port=9090`: Start multi-session on this TCP port with GDB/MI.
- `aliceserver --pipe=/run/aliceserver`: (POSIX platforms) Start multi-session on this UNIX socket.
- `aliceserver --pipe=aliceserver`: (Windows only) Start multi-session on `\\.\pipe\aliceserver` Named Pipe.
- `aliceserver --pipe=\\.\pipe\example`: (Windows only) Start multi-session on this Named Pipe.

With multi session, a new connection means a new debugging session. Clients are still
free to invoke additional single sessions (stdio).

Implementation details, such as which commands are supported, are in `source/README.md`.

# Building

You'll need DUB and a recent D compiler: DMD, GDC, or LDC.

Debug build: `dub build`

Release build: `dub build -b release`

DUB will automatically pull in the dependencies.

# Licensing

This project is licensed under the BSD-3-Clause-Clear license.