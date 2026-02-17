# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

This is a D language project using the `dub` package manager.

- **Build:** `dub build`
- **Run:** `dub -- [args]` (e.g., `dub -- --ver`)
- **Unit tests:** `dub test`
- **Generate docs:** `dub build --build=docs`

Compiles with DMD, LDC, and GDC. CI tests all three on Linux; LDC on macOS/Windows.

## What This Is

Aliceserver is a debugger server that speaks DAP (Debug Adapter Protocol) and GDB/MI
protocols, using [Alicedbg](https://github.com/dd86k/alicedbg) as the debugging back-end.
It is work-in-progress — many DAP and GDB/MI commands are not yet implemented.

## Architecture

The server uses an OOP model with three interface layers that compose together:

- **`ITransport`** (`source/transport.d`) — data I/O abstraction (streams, sockets). Impl: `StdioTransport`.
- **`IAdapter`** (`source/adapter.d`) — protocol handler that parses requests from a transport and formats responses/events. Impls: `DAPAdapter`, `MIAdapter`.
- **`IDebugger`** (`source/debugger.d`) — debugger abstraction for process control. Impl: `AliceDebugger` (wraps Alicedbg).

The main loop in `source/aliceserver.d` (`startServer`) polls the transport for data, dispatches to the adapter, and forwards debugger events back through the adapter. The adapter selection (DAP vs MI) is set via CLI `--adapter=dap|mi`.

Entry point: `source/main.d` — CLI argument parsing, then calls `startServer()`.

## Key Source Layout

- `source/adapters/dap.d` — DAP protocol implementation
- `source/adapters/mi.d` — GDB/MI protocol implementation
- `source/debuggers/alicedbg.d` — Alicedbg integration
- `source/transports/stdio.d` — stdio transport
- `source/util/` — JSON helpers, shell utilities, formatting
- `testdap.d`, `testmi.d` — interactive tester tools (spawn server as subprocess, send protocol messages)

## testdap.d and testmi.d

`testdap.d` and `testmi.d` are D scripts (invoked with `rdmd`, `gdmd -run`, or `ldmd2 -run`)
meant to emulate a client interactively. They do not integrate a test framework, and thus
do not have automated integration tests.

## D Language Notes

- Module names match file paths (e.g., `module adapters.dap` → `source/adapters/dap.d`)
- Dependencies are pinned by git commit hash in `dub.sdl` (alicedbg, ddlogger)
- `debug`/`else` blocks are used for debug-vs-release conditional compilation
