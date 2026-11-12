# Vim-opencode Codebase Analysis — Index

## Analysis Files

| File | Content |
|------|---------|
| `01-structure.md` | Complete folder/file → element mapping (all functions, constants, module state, imports, test files, docs) |
| `02-controlflow.md` | All implementation routes and control flow pathways (command dispatch, prompt/ask/operator, panel, discovery, sessions, catalog, permissions, diff, quickchat, tabs, health, popup, palette, V1/V2, config load) |
| `03-bugs-discrepancies.md` | All bugs and discrepancies noted (NOT fixed yet — awaiting your approval per item) |

## Repository Structure Analyzed

| Path | Role |
|------|------|
| `plugin/vim-opencode.vim` | Entry point, `:Opencode` command, mappings |
| `autoload/vim_opencode/` | Core modules (config, util, commands, transport, discovery, server, protocol, state, events, context, prompt, sessions, catalog, permissions, review, tabs, quickchat, health) |
| `autoload/vim_opencode/protocol/` | V1/V2 adapter implementations + active dispatcher |
| `autoload/vim_opencode/ui/` | Panel, render, popup, palette, style, diff |
| `ftplugin/` | Output and input buffer settings |
| `syntax/` | Output buffer syntax |
| `doc/` | User documentation |
| `docs/analysis/` | Implementation plan + Neovim plugin comparisons |
| `docs/codebase-analysis/` | This analysis (new) |
| `test/` | 12 headless smoke tests + Python fixture server |
| `.github/workflows/ci.yml` | CI pipeline |

## Change Tracking Log

| # | File | Change | Reason | Status | Approved |
|---|------|--------|--------|--------|----------|
| 1 | `autoload/vim_opencode/config.vim` | `Setup()` now calls `Normalize()` before `Validate()` | Normalize mutates config after validation; moved before so validation checks final values | Fixed | all |
| 2 | `autoload/vim_opencode/config.vim` | `ValidateGui()` uses `RequireString()` for `popup_border` | Consistency with other validators; was using `get(..., v:null)` check | Fixed | all |
| 3 | `autoload/vim_opencode/config.vim` | `ValidateKeymaps()` detects duplicate mapping values | Prevents ambiguous prefix-chord conflicts (`<Leader>o` vs `<Leader>oo`) | Fixed | all |
| 4 | `autoload/vim_opencode/state.vim` | `ApplyRevert()` keeps boundary message, drops after | Off-by-one: `messages[0 : position-1]` dropped the boundary message | Fixed | all |
| 5 | `autoload/vim_opencode/state.vim` | `DropOptimistic()` drops all matching optimistic messages | Only dropped first match; retried prompts left duplicates | Fixed | all |
| 6 | `autoload/vim_opencode/state.vim` | `EnsureMessage()` calls `Reindex()` before reading `index` | Stale index could return wrong message after `RemoveMessage` | Fixed | all |
| 7 | `autoload/vim_opencode/transport.vim` | `Finish()` sets `req.cancelled = true` on stream non-zero exit | Inconsistent with `Fail()` which sets it | Fixed | all |
| 8 | `autoload/vim_opencode/discovery.vim` | `Connect()` guards against concurrent calls via `connecting` flag | Shared module state (`poll_timer`, `poll_callbacks`) could be overwritten | Fixed | all |
| 9 | `autoload/vim_opencode/discovery.vim` | `Connect()` wraps callbacks to reset `connecting` flag on resolve | Flag must be cleared when async discovery chain completes | Fixed | all |
| 10 | `autoload/vim_opencode/ui/panel.vim` | Removed duplicate `ApplyStatusline()` call in `Open()` | Harmless but redundant | Fixed | all |
| 11 | `autoload/vim_opencode/quickchat.vim` | `Start()` validates `instruction` is non-empty | Empty instruction produced a meaningless prompt | Fixed | all |
| 12 | `autoload/vim_opencode/review.vim` | `Text()` skips `stale` comments | `stale` flag was set by `MarkSent()` but never read | Fixed | all |
| 13 | `autoload/vim_opencode/review.vim` | `AddCurrent()` validates buffer has a file path | `expand('%:p')` could be empty for scratch buffers | Fixed | all |
| 14 | `test/fixtures/server.py` | Removed duplicate unreachable `/command` route handler | Dead code at lines 189-190 | Fixed | all |
| 15 | `autoload/vim_opencode/commands.vim` | Added `'status'` to `ARG_COMPLETIONS.debug` | `DebugCommand` accepts `status` but completion didn't suggest it | Fixed | all |
| 16 | `README.md` | Updated status from "P0-P7" to "P0-P10" | Code implements P8 (tab) and P10 (debug) too | Fixed | all |
| 17 | `doc/vim-opencode.txt` | Fixed duplicate section 8 → section 9 for FUNCTIONS | Contents table said 9 but body said 8 | Fixed | all |
| 18 | `doc/vim-opencode.txt` | Updated phase description text | Said phase-marked commands are "not implemented yet" but they are | Fixed | all |
| 19 | `.github/workflows/ci.yml` | Added `:defcompile` step to CI | FEATURES.md documented defcompile in CI but it wasn't running | Fixed | all |

*Not fixed (intentional behavior or low risk):*
- `DeepMerge` non-dict override — working as designed, caught by validation
- `state.Apply` session-scoped event rejection — intentional, events from other sessions should be ignored
- `BuildArgs` auth — Basic auth requires both username and password
- `Close()` not invoking `on_close` for streams — intentional, manual close ≠ natural close
- V1 `NormalizeEvent` incomplete mapping — known limitation, V1 is secondary
- `panel.Open()` not calling `EnsureSessionAsync` when already open — intentional early return
- Catalog `SelectAgent` string vs `SelectModel` dict — server expects string agent name
- Review `stale` field — now filtered in `Text()`

## Next Step

All documented bugs have been addressed. The analysis files remain in `docs/codebase-analysis/` as a reference. No further changes are pending.
