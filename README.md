# About Aliceserver

Aliceserver is a debugger server implementing the DAP and GDB/MI protocols, using
[Alicedbg](https://github.com/dd86k/alicedbg) as the debugger back-end.

> [!WARNING]
> This is WORK IN PROGRESS!
> 
> Experimental project, don't expect it to replace GDB or LLDB any time soon.

It combines all the transport and adapter options into one runtime.

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
- Use `--pipe=PATH` with a path (`\\.\pipe\example`/`/var/run/example`) or name (`example`).

To select an adapter:
- `--adapter=dap` selects DAP, which is the default. No extra argument needed.
- `--adapter=mi` selects the latest MI version.

Implementation details, such as which commands are supported, are in `source/README.md`.

# Building

You'll need DUB and a recent D compiler: DMD, GDC, or LDC.

Debug build: `dub build`

Release build: `dub build -b release`

# Licensing

This project is licensed under the BSD-3-Clause-Clear license.