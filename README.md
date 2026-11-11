# opencode9.vim

A Vim 9.1-native client for [OpenCode](https://opencode.ai), built around the
OpenCode V2 HTTP and SSE APIs.

The project follows a V2-first, layered design:

- a small transport and discovery core;
- context-aware prompt, ask and operator workflows;
- a split-panel transcript, permissions and diff review;
- optional session tabs, review comments and V1 compatibility.

## Status

Early development. The current tree implements the P0 walking skeleton:
plugin loading, configuration, command dispatch, health checks and a headless
test harness. Network, prompt and panel features arrive in later phases.

See `docs/analysis/vim9-opencode-implementation-analysis.json` for the
implementation plan and `doc/opencode9.txt` for user documentation.

## Requirements

- Vim 9.1 with `+job`, `+channel`, `+timers` and `+textprop`.
- `curl` on `PATH` for HTTPS and SSE transport.
- An OpenCode server exposing the V2 API (for later phases).

## Installation

Use a Vim package manager, or add this repository to `runtimepath`:

```vim
set runtimepath+=/path/to/opencode9.vim
```

Then source the plugin or restart Vim:

```vim
runtime plugin/opencode9.vim
```

## Quick start

```vim
:Opencode health
:Opencode version
:Opencode help
```

## Development

Run the P0 smoke test from the repository root:

```sh
./test/run.sh
```

## License

MIT. See `LICENSE` when it is added.
