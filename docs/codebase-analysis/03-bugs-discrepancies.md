# Vim-opencode Codebase Analysis — Part 3: Bugs & Discrepancies (ALL FIXED)

## Configuration / Validation Issues

### Fix 1: `config.ValidateGui` now uses `RequireString()` for `popup_border`
- **File**: `autoload/vim_opencode/config.vim`, `ValidateGui()`
- **Problem**: `get(value, 'popup_border', v:null)` check was inconsistent with other validators that use `RequireString()`.
- **Fix**: Replaced with `RequireString(value, 'popup_border', 'gui')`.

### Fix 2: `Setup()` now calls `Normalize()` before `Validate()`
- **File**: `autoload/vim_opencode/config.vim`, `Setup()`
- **Problem**: `Normalize()` mutated config after validation, so validation could pass on pre-normalization values.
- **Fix**: Swapped order: `Normalize(merged)` then `Validate(merged)`.

### Fix 3: `ValidateKeymaps()` detects duplicate mapping values
- **File**: `autoload/vim_opencode/config.vim`, `ValidateKeymaps()`
- **Problem**: No detection when two actions map to the same key (e.g., `<Leader>o` vs `<Leader>oo`).
- **Fix**: Added `seen` dictionary to track mappings and fail on conflicts.

## Session / State Issues

### Fix 4: `ApplyRevert()` keeps boundary message, drops after
- **File**: `autoload/vim_opencode/state.vim`, `ApplyRevert()`
- **Problem**: `messages[0 : position - 1]` dropped the boundary message (off-by-one). First fix used `messages[0 : position]` which still excluded the boundary (Vim9 slice end is exclusive).
- **Fix**: Changed to `messages[0 : position + 1]` to keep up to and including boundary. Vim9 slice `[0:position+1]` is exclusive of the end, so it includes index `position`.

### Fix 5: `DropOptimistic()` drops all matching optimistic messages
- **File**: `autoload/vim_opencode/state.vim`, `DropOptimistic()`
- **Problem**: Only dropped first matching message; retried prompts left duplicates.
- **Fix**: Iterates all matches, drops each, returns whether any were dropped.

### Fix 6: `EnsureMessage()` calls `Reindex()` before reading `index`
- **File**: `autoload/vim_opencode/state.vim`, `EnsureMessage()`
- **Problem**: Stale `index` after `RemoveMessage` could return wrong message.
- **Fix**: Call `Reindex()` before reading from `index`.

## Transport Issues

### Fix 7: `Finish()` sets `req.cancelled = true` on stream non-zero exit
- **File**: `autoload/vim_opencode/transport.vim`, `Finish()`
- **Problem**: Inconsistent with `Fail()` which sets `cancelled`.
- **Fix**: Added `req.cancelled = true` before invoking `on_error`.

## Discovery Issues

### Fix 8: `Connect()` guards against concurrent calls via `connecting` flag
- **File**: `autoload/vim_opencode/discovery.vim`, `Connect()`
- **Problem**: Shared module state could be overwritten by concurrent discovery calls.
- **Fix**: Added `connecting` flag; second call returns error immediately.

### Fix 9: `Connect()` wraps callbacks to reset `connecting` flag on resolve
- **File**: `autoload/vim_opencode/discovery.vim`, `Connect()`
- **Problem**: Flag needed to be cleared when async discovery chain completes.
- **Fix**: Wrapped `on_success`/`on_error` callbacks to reset `connecting = v:false`.

## UI / Panel Issues

### Fix 10: Removed duplicate `ApplyStatusline()` call in `Open()`
- **File**: `autoload/vim_opencode/ui/panel.vim`, `Open()`
- **Problem**: `ApplyStatusline()` called twice consecutively.
- **Fix**: Removed duplicate call.

## QuickChat Issues

### Fix 11: `Start()` validates `instruction` is non-empty
- **File**: `autoload/vim_opencode/quickchat.vim`, `Start()`
- **Problem**: Empty instruction produced a meaningless prompt.
- **Fix**: Added `trim(instruction) ==# ''` check with error message.

## Review Issues

### Fix 12: `Text()` skips `stale` comments
- **File**: `autoload/vim_opencode/review.vim`, `Text()`
- **Problem**: `stale` flag was set by `MarkSent()` but never read for filtering.
- **Fix**: Added `if item.stale continue` in the loop.

### Fix 13: `AddCurrent()` validates buffer has a file path
- **File**: `autoload/vim_opencode/review.vim`, `AddCurrent()`
- **Problem**: `expand('%:p')` could be empty for scratch buffers, producing `:0-0`.
- **Fix**: Added empty-file check with error message.

## Test Issues

### Fix 14: Removed duplicate unreachable `/command` route handler
- **File**: `test/fixtures/server.py`
- **Problem**: Lines 189-190 were dead code (earlier handler already returned).
- **Fix**: Removed duplicate `elif` block.

## Command Completion Issues

### Fix 15: Added `'status'` to `ARG_COMPLETIONS.debug`
- **File**: `autoload/vim_opencode/commands.vim`
- **Problem**: `DebugCommand` accepts `status` but completion didn't suggest it.
- **Fix**: Added `'status'` to the debug completions list.

## Documentation Fixes

### Fix 16: README status updated from "P0-P7" to "P0-P10"
- **File**: `README.md`
- **Problem**: Code implements P8 (tab) and P10 (debug) too.
- **Fix**: Updated status section.

### Fix 17: Fixed duplicate section 8 → section 9 for FUNCTIONS
- **File**: `doc/vim-opencode.txt`
- **Problem**: Contents table listed "9. Functions" but body had "8. FUNCTIONS".
- **Fix**: Renumbered to "9. FUNCTIONS".

### Fix 18: Updated phase description text
- **File**: `doc/vim-opencode.txt`, line 28
- **Problem**: Said phase-marked commands are "not implemented yet" but they are.
- **Fix**: Changed to indicate phases show implementation stage.

### Fix 19: Added `:defcompile` step to CI
- **File**: `.github/workflows/ci.yml`
- **Problem**: FEATURES.md documented defcompile in CI but it wasn't running.
- **Fix**: Added defcompile check step after smoke tests.

## Not Fixed (Intentional Behavior or Low Risk)

| # | File | Issue | Reason |
|---|------|-------|--------|
| A | `autoload/vim_opencode/config.vim` | `DeepMerge` non-dict override | Working as designed; caught by `ValidateServer()` |
| B | `autoload/vim_opencode/state.vim` | `state.Apply` session-scoped event rejection | Intentional; events from other sessions should be ignored |
| C | `autoload/vim_opencode/transport.vim` | `BuildArgs` auth requires password | Basic auth needs both username and password |
| D | `autoload/vim_opencode/transport.vim` | `Close()` not invoking `on_close` for streams | Intentional; manual close ≠ natural close |
| E | `autoload/vim_opencode/protocol/v1.vim` | V1 `NormalizeEvent` incomplete mapping | Known limitation; V1 is secondary |
| F | `autoload/vim_opencode/ui/panel.vim` | `panel.Open()` not calling `EnsureSessionAsync` when already open | Intentional early return |
| G | `autoload/vim_opencode/catalog.vim` | `SelectAgent` string vs `SelectModel` dict | Server expects string agent name |
| H | `autoload/vim_opencode/review.vim` | `stale` field | Now filtered in `Text()` |

## Summary

**19 fixes applied** across 12 files:
- 4 configuration/validation fixes
- 3 session/state fixes
- 1 transport fix
- 2 discovery fixes
- 1 UI/panel fix
- 1 quickchat fix
- 2 review fixes
- 1 test fix
- 1 command completion fix
- 4 documentation/CI fixes

**8 items intentionally not fixed** (documented above).
