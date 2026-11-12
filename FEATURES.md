# opencode9.vim — Feature Reference

Complete list of all implemented features, recommended example uses, and
default shortcuts for the most useful commands.

---

## Table of Contents

1. [P0 — Foundation](#p0---foundation)
2. [P1 — Server Connection](#p1---server-connection)
3. [P2 — Context-Aware Prompts](#p2---context-aware-prompts)
4. [P3 — Split Panel Transcript](#p3---split-panel-transcript)
5. [P4 — Sessions, Models, Agents, Commands](#p4---sessions-models-agents-commands)
6. [P5 — Permissions and Edit Review](#p5---permissions-and-edit-review)
7. [P6 — Review Comments](#p6---review-comments)
8. [P7 — Quick-Chat Inline Edits](#p7---quick-chat-inline-edits)
9. [P8 — Persistent Panel Tabs](#p8---persistent-panel-tabs)
10. [P9 — V1 Protocol Adapter](#p9---v1-protocol-adapter)
11. [P10 — Hardening and CI](#p10---hardening-and-ci)
12. [Recommended Default Shortcuts](#recommended-default-shortcuts)
13. [Events Reference](#events-reference)

---

## P0 — Foundation

| Command | Usage | Description |
|---------|-------|-------------|
| `:Opencode help` | `help [doc]` | Show command summary or open full help file |
| `:Opencode version` | `version` | Show plugin and Vim versions |
| `:Opencode health` | `health` | Run environment checks (Vim features, curl, config) |
| `:Opencode config` | `config [path\|validate]` | Show merged config as JSON, validate, or get a dotted path |

**Recommended example uses:**

- `:Opencode health` — Verify Vim 9.1, `+job`, `+channel`, `+timers`, `+textprop`, and `curl` are available before doing anything else.
- `:Opencode config validate` — Confirm your `g:opencode9_config` is valid after editing your `.vimrc`.
- `:Opencode config panel.height` — Inspect a single config value (e.g. the panel height).
- `:Opencode help doc` — Open the full reference manual in a help window.

**Default shortcut:** None by default (opt-in via `default_mappings: true` and `keymaps.help`, `keymaps.health`).

---

## P1 — Server Connection

| Command | Usage | Description |
|---------|-------|-------------|
| `:Opencode server` | `server [status\|connect\|disconnect\|start\|stop]` | Manage discovery and the OpenCode connection |
| `:Opencode server status` | — | Show active URL, version, and connection state |
| `:Opencode server connect` | — | Discover and connect, then subscribe to SSE events |
| `:Opencode server disconnect` | — | Close the stream and stop reconnecting |
| `:Opencode server start` | — | Run the configured `server_command` |
| `:Opencode server stop` | — | Stop a server started by this plugin |

**Recommended example uses:**

- `:Opencode server connect` — Connect to your running OpenCode server (or the URL in `server_url`).
- `:Opencode server status` — Check whether the plugin is connected and which server/version it is using.
- `:Opencode server start` — If `server_command` is configured, launch the OpenCode server from within Vim.

**Default shortcut:** None by default.

---

## P2 — Context-Aware Prompts

| Command | Usage | Description |
|---------|-------|-------------|
| `:Opencode prompt` | `prompt [text]` | Send a prompt with `@` context placeholders |
| `:Opencode ask` | `ask [text]` | Open an interactive input prompt with optional initial text |
| `:Opencode operator` | `operator` | Set operatorfunc and send the selected range |
| `:Opencode context` | `context [show\|clear]` | Inspect or clear captured context |

**Context placeholders:**

| Placeholder | Meaning |
|-------------|---------|
| `@this` | Selected range, or cursor location (`path:L1:C2-L3:C4`) |
| `@buffer` | Current buffer path (or full text for scratch buffers) |
| `@buffers` | All listed file-backed buffers |
| `@visible` | Visible line range in every window |
| `@quickfix` | Quickfix list locations |
| `@marks` | Global marks A–Z |
| `@diagnostics` | Quickfix entries for current buffer/range |

**Recommended example uses:**

- `:Opencode prompt @this explain` — Explain the current selection or cursor location.
- `:Opencode prompt @buffer @quickfix fix the error` — Send the current file and quickfix errors for debugging.
- `:Opencode ask @this` — Interactively refine a question about the selection before sending.
- `vip :Opencode prompt` — Visually select a paragraph, then send it as a prompt.
- `:Opencode context show` — See what context placeholders would expand to.
- `:Opencode context clear` — Clear the transcript state.

**Default shortcut (opt-in):**
- `<Leader>op` → `:Opencode prompt`
- `<Leader>oa` → `:Opencode ask`

---

## P3 — Split Panel Transcript

| Command | Usage | Description |
|---------|-------|-------------|
| `:Opencode toggle` | `toggle` | Show or hide the whole panel |
| `:Opencode open` | `open [input\|output\|panel]` | Open the input, output, or full panel |
| `:Opencode close` | `close [input\|output\|panel]` | Close a panel window or the whole panel |

**Panel transcript window mappings (normal mode):**

| Key | Action |
|-----|--------|
| `<CR>` | Jump to the file location under the cursor |
| `q` | Close the panel |
| `]m` | Jump to the next message start |
| `[m` | Jump to the previous message start |
| `]u` | Jump to the next user message |
| `[u` | Jump to the previous user message |

**Panel input window mappings:**

| Key | Action |
|-----|--------|
| `<CR>` | Submit the draft as a prompt |
| `<C-p>` | Previous draft from history |
| `<C-n>` | Next draft from history |

**Recommended example uses:**

- `:Opencode toggle` — Bring up the chat panel to read streaming responses, then hide it to focus on code.
- `:Opencode open output` — Open only the transcript window to review history without the input area.
- In the panel, press `]m` / `[m` to navigate between assistant and user messages.
- Press `<CR>` in the input window to submit your draft as a prompt.

**Default shortcut (opt-in):**
- `<Leader>ot` → `:Opencode toggle`

---

## P4 — Sessions, Models, Agents, Commands

| Command | Usage | Description |
|---------|-------|-------------|
| `:Opencode session` | `session [list\|pick\|new\|open\|rename\|delete\|fork]` | Manage conversations |
| `:Opencode model` | `model [list\|pick\|current\|clear\|<model>]` | List or select a model |
| `:Opencode agent` | `agent [list\|pick\|current\|clear\|<agent>]` | List or select an agent |
| `:Opencode command` | `command [list\|pick\|run\|<name> [args]]` | List or run a server command |

**Recommended example uses:**

- `:Opencode session list` — See all conversations for the current directory.
- `:Opencode session new "Code review"` — Create a new session with a title.
- `:Opencode session open 2` — Open the second-most-recent session by numeric index.
- `:Opencode session fork` — Fork the current session into a new one.
- `:Opencode model pick` — Interactively choose a model (e.g. `anthropic/claude-3`).
- `:Opencode agent pick` — Choose an agent (e.g. `build` or `plan`).
- `:Opencode command run review src` — Run the `review` server command on `src`.
- `:Opencode prompt @this` (after selecting a model/agent) — The prompt uses the selected model and agent.

**Model/agent persistence:** Selections are saved to `$XDG_STATE_HOME/opencode9/favorites.json` and survive restarts.

**Default shortcut:** None by default.

---

## P5 — Permissions and Edit Review

| Command | Usage | Description |
|---------|-------|-------------|
| `:Opencode permission` | `permission [list\|accept\|always\|accept_all\|deny\|ask]` | Answer pending permission requests |
| `:Opencode diff` | `diff [open\|accept\|reject\|close]` | Review the active edit diff |

**Recommended example uses:**

- `:Opencode permission list` — See pending permission/question requests.
- `:Opencode permission accept` — Allow the most recent permission request.
- `:Opencode permission deny` — Reject the most recent request.
- `:Opencode permission ask` — Open an interactive picker for pending requests.
- `:Opencode diff open` — Review a proposed single-file edit in a diff split.
- `:Opencode diff accept` — Accept the proposed edit (writes to disk).
- `:Opencode diff reject` — Discard the proposed edit.

**Default shortcut:** None by default.

---

## P6 — Review Comments

| Command | Usage | Description |
|---------|-------|-------------|
| `:Opencode review` | `review [list\|add\|clear]` | Manage review comments |

**Recommended example uses:**

- `:Opencode review add This function is too long` — Attach a review comment at the current line.
- `:Opencode review list` — Show all review comments with file and line ranges.
- `:Opencode review clear` — Remove all review comments.

Review comments are appended to the next prompt sent via `:Opencode prompt` or `:Opencode ask`.

**Default shortcut:** None by default.

---

## P7 — Quick-Chat Inline Edits

| Command | Usage | Description |
|---------|-------|-------------|
| `:Opencode quickchat` | `quickchat [instruction]` | Edit the current range in place |

**Recommended example uses:**

- `:Opencode quickchat simplify this` — Replace the current line/range with a simplified version.
- `vip :Opencode quickchat make this more idiomatic` — Visually select a paragraph and request a rewrite.
- The replacement is whole-line only; use `u` to undo if needed.
- Cancellation restores the original buffer state.

**Default shortcut:** None by default.

---

## P8 — Persistent Panel Tabs

| Command | Usage | Description |
|---------|-------|-------------|
| `:Opencode tab` | `tab [list\|new\|open\|close]` | Manage panel tabs |

**Recommended example uses:**

- `:Opencode tab list` — Show all project-scoped tabs with `*` marking the current one.
- `:Opencode tab new` — Create a new tab for the current session.
- `:Opencode tab open 2` — Switch to tab 2.
- `:Opencode tab close` — Close the current tab.

Tab metadata (session, directory, draft) is persisted under `$XDG_STATE_HOME/opencode9/` and restored on startup.

**Default shortcut:** None by default.

---

## P9 — V1 Protocol Adapter

A V1 protocol adapter (`autoload/opencode9/protocol/v1.vim`) normalizes V1 wire shapes
(`/global/health`, `/global/event`, `/global/session*`, etc.) into the shared model used by the UI.
Protocol selection is via `g:opencode9_config.protocol` (`v1` or `v2`, default `v2`).

The V2 code path is unchanged and fully functional.

**Default shortcut:** None.

---

## P10 — Hardening and CI

- `.github/workflows/ci.yml` — GitHub Actions: builds Vim 9.1, runs headless smoke tests, `:defcompile` on all modules, and plugin source check.
- `render.Chunks(max_messages)` — Caps rendered transcript messages with a truncation notice.
- Transport `FormatError()` / `Truncate()` — Clear error messages including curl exit code, HTTP status, response body, and stderr.
- Config validation for `protocol` (v1/v2) and `panel.max_messages`.
- P9/P10 smoke tests for adapter normalization and hardening checks.

**Default shortcut:** None.

---

## Recommended Default Shortcuts

The plugin does not enable default mappings by default (`default_mappings: false`). To enable them, add to your `.vimrc`:

```vim
let g:opencode9_config = {
  \ default_mappings: v:true,
  \ keymaps: {
  \   help: '<Leader>oh',
  \   health: '<Leader>oH',
  \   prompt: '<Leader>op',
  \   ask: '<Leader>oa',
  \   toggle: '<Leader>ot',
  \ },
  \}
```

### Most useful default shortcuts

| Shortcut | Command | When to use |
|----------|---------|-------------|
| `<Leader>op` | `:Opencode prompt` | Send a prompt with context placeholders (most used) |
| `<Leader>oa` | `:Opencode ask` | Interactively compose a prompt before sending |
| `<Leader>ot` | `:Opencode toggle` | Show/hide the split panel |
| `<Leader>oh` | `:Opencode help` | Open command reference |
| `<Leader>oH` | `:Opencode health` | Verify environment and connection |

### Panel buffer-local shortcuts (active when panel is open)

| Shortcut | Context | Action |
|----------|---------|--------|
| `<CR>` | Transcript (normal) | Jump to file under cursor |
| `<CR>` | Input (normal/insert) | Submit draft as prompt |
| `q` | Transcript (normal) | Close panel |
| `]m` / `[m` | Transcript (normal) | Next/previous message |
| `]u` / `[u` | Transcript (normal) | Next/previous user message |
| `<C-p>` / `<C-n>` | Input (insert) | Previous/next draft history |

---

## Events Reference

The plugin emits `User` autocmds prefixed with `OpencodeEvent:`. The decoded payload is in `g:opencode9_event`.

| Event | When |
|-------|------|
| `OpencodeEvent:server.connected` | SSE connection established |
| `OpencodeEvent:session.status` | Session status changed |
| `OpencodeEvent:permission.asked` | Permission request received |
| `OpencodeEvent:question.asked` | Question request received |
| `OpencodeEvent:server.disconnected` | Stream lost (before reconnect) |
| `OpencodeEvent:prompt.sent` | Prompt POST succeeded |
| `OpencodeEvent:prompt.failed` | Prompt failed |
| `OpencodeEvent:session.opened` | Session attached to panel |
| `OpencodeEvent:session.created` | New session created |
| `OpencodeEvent:session.renamed` | Session title changed |
| `OpencodeEvent:session.deleted` | Session deleted |
| `OpencodeEvent:session.forked` | Session forked |
| `OpencodeEvent:permission.pending` | Permission/question needs attention |
| `OpencodeEvent:permission.replied` | Permission response accepted |
| `OpencodeEvent:question.answered` | Question response accepted |
| `OpencodeEvent:diff.pending` | Edit diff ready for review |
| `OpencodeEvent:diff.accepted` | Proposed edit written to disk |
| `OpencodeEvent:diff.rejected` | Proposed edit discarded |
| `OpencodeEvent:review.pending` | Review comment created |

**Example autocmd:**

```vim
autocmd User OpencodeEvent:permission.asked echo 'Permission requested: ' .. string(g:opencode9_event)
```

---

## Installation Quick Start

```vim
" Add to your .vimrc
let g:opencode9_config = {
  \ server_url: 'http://127.0.0.1:18767',
  \ default_mappings: v:true,
  \ keymaps: {
  \   prompt: '<Leader>op',
  \   ask: '<Leader>oa',
  \   toggle: '<Leader>ot',
  \   help: '<Leader>oh',
  \   health: '<Leader>oH',
  \ },
  \}

runtime plugin/vim-opencode.vim

" Then in Vim:
:Opencode health
:Opencode server connect
:Opencode toggle
:Opencode session list
:Opencode prompt @this explain
```

---

## Requirements

- Vim 9.1 with `+job`, `+channel`, `+timers`, and `+textprop`
- `curl` on `PATH` for HTTPS and SSE transport
- An OpenCode server exposing the V2 HTTP and SSE APIs
