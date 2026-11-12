# vim-opencode GUI Smoothening Plan

**Branch:** `feature/gui-popup-styling-plan`
**Status:** Planning (no code committed yet beyond this document)
**Reference:** `/home/potz/rcs/vim/plugged/fzf.vim/fzf_analysis.json` (fzf.vim structure, popup/styling implementation notes)

---

## 1. Goal

Smooth out the graphical (GUI/TUI window) experience of the vim-opencode plugin by borrowing the **popup windows** and **styling options** implementations from fzf.vim, and converge toward **one (or a small set of) interactive window(s) that can reach every :Opencode command**.

Today the UI is inconsistent:
- listings (`:Opencode model list`, `agent list`, `command list`, `session list`, `permission list`) print plain `:echomsg` lines or fall back from `popup_menu()` to `inputlist()`;
- the split panel (transcript + input) is a plain horizontal split with no border/title/footer chrome;
- there is no single entry point that discovers and launches all commands from inside the editor.

This plan adopts fzf.vim's proven patterns (spec dict, highlight-group-derived colors, borders, preview window, show/peek key, footer hints) so vim-opencode gets a consistent, interactive, keyboard-driven UI.

---

## 2. What fzf.vim offers (from fzf_analysis.json)

The analysis file describes fzf.vim at `/home/potz/rcs/vim/plugged/fzf.vim/fzf_analysis.json`. The relevant implementation elements are:

| fzf.vim element | What it does | How vim-opencode can reuse it |
|---|---|---|
| **Spec dict** (`source`/`options`/`sink`/`sink*`/`window`/`exit`/`_paste`/`_show`/`_hint`) | Every command builds a dict and hands it to one runner (`s:fzf` → `fzf#run`). | One `vim_opencode#ui#popup#run(spec)` runner for pickers, palette, previews. |
| **Styling helpers** (`s:get_color`, `s:csi`, `s:ansi`, `s:black/red/…/cyan`) | Derive GUI/cterm color from a Vim highlight group via `synIDattr(synIDtrans(hlID(group)), …)`. | Color popup borders/titles/entries from existing `VimOpencode*` highlight groups instead of hard-coded ANSI. |
| **Borders** (`--list-border`, `--header-border inline`, `--info inline-right`, `--no-separator`) | fzf-side rendering options that draw list/header borders and inline info. | Equivalent popup styling: border chars, title bar, inline info line, separator control. |
| **Preview window** (`--preview` + `--preview-window '+{N}/2'`) | A tight popup-sized preview that centers on a field (`+{2}/2`, `+{3}/2`). | Side preview showing the selected session diff, model info, or command hint while browsing. |
| **Show / peek key** (`ctrl-o`, IPC fifo + `win_execute`) | Peek at the current entry in its origin window without closing fzf (`s:can_show`, `s:add_hints`, `ipc.vim`). | Peek at a session/model/command in a floating preview while the picker stays open. |
| **Footer hints** (`s:build_hint`, magenta keys via `Special`) | `Enter Open, C-X HSplit, C-V VSplit, C-T Tab` plus command-specific hints. | `Enter pick, C-P preview, C-Q quit, C-H help` footer on every popup. |
| **Key labels** (`s:key_label`: `C-X`, `A-S`, `S-`, …) | Canonical key spelling for display. | Consistent modifier labels in popup footers and help. |
| **Layout keys** (`window`/`up`/`down`/`left`/`right`/`popup`/`tmux`) | Layout chosen from spec keys plus `g:fzf_layout` fallback. | `popup` layout with configurable `width`/`height`/`row`/`col`, fallback to split. |
| **Statusline colors** (`fzf1`/`fzf2`/`fzf3`) | Colored mini statusline while fzf runs. | Optional statusline pill showing connection/server/session in the palette. |

---

## 3. Target state (interactive window(s) reaching all commands)

- **Command palette** (`:Opencode palette` / `<Leader>oc`): one floating popup listing every `:Opencode` command plus sub-actions (session list/pick/new, model pick, agent pick, command pick/run, permission list, diff open, review list, tab list, toggle/open/close, health, config). Fuzzy-filtered as you type. Pressing `Enter` runs the command; `C-P` previews; `C-Q` quits.
- **Styled pickers** (`model pick`, `agent pick`, `command pick`, `session pick`, `permission list`): replace `inputlist()`/`popup_menu()` plain lists with bordered titled popups with footer hints and optional preview.
- **Panel chrome**: the split transcript/input panel gains a title bar, border, and footer hint line consistent with the palette.
- **Preview pane**: optional side popup showing context for the highlighted entry (session messages diff, model catalog entry, server command hint).
- **Show/peek key**: `ctrl-o`-style peek opens the highlighted entry's target in the origin window without closing the popup.
- **Styling**: all colors derived from Vim highlight groups (no hard-coded ANSI), honoring `termguicolors`/`cterm` and `&ambiwidth`.

---

## 4. Design principles (carried from fzf.vim)

1. **Single runner:** one `vim_opencode#ui#popup#run(spec)` executes every popup/picker/palette/preview. Each UI surface builds a spec dict.
2. **Styles from highlights:** never hard-code a color. Use `synIDattr(synIDtrans(hlID(group)), 'gui'|'cterm')` like fzf's `s:get_color`/`s:ansi`, with `termguicolors`/`cterm` fallbacks and 16-color fallback.
3. **Graceful degradation:** if `+popupwin`/`popup_menu()` is missing, fall back to `inputlist()`/`:` echoes exactly as today; never crash.
4. **Keyboard-first:** every popup is fully operable with `jk/↑↓`, `Enter`, `C-P`, `C-Q`, `C-H`, and the show/peek key.
5. **Non-blocking:** rendering uses timers/debounce (as the panel already does) and `job_start`/`jobstart` for any async work; popups never block Vim.

---

## 5. Step-by-step implementation plan

### Phase 0 — Foundation & spec runner
**Files:** `autoload/vim_opencode/ui/popup.vim` (new), `autoload/vim_opencode/ui/style.vim` (new), `autoload/vim_opencode/config.vim` (extend), `plugin/vim-opencode.vim` (extend)

1. Add a `gui` section to `Defaults`/`Validate` in `config.vim`:
   - `gui.popup_border` — border style: `'rounded'` (╭╮╰╯ ─ │) or `'none'`/`'single'` (`+|-|`), default `'rounded'` when `&ambiwidth` is single, else `'single'`.
   - `gui.popup_title`, `gui.footer_hint`, `gui.preview_width`, `gui.colors` (enable/disable highlight-derived colors).
   - `gui.default_position` — where `:Opencode open`/`:Opencode toggle` place the panel: `'right'` (vertical split on the right, default), `'horizontal'` (botright/belowright), `'popup'` (floating). Honors an explicit `open [input|output|panel]`/`close [target]` target and `panel.position` override.
2. Create `style.vim` with fzf.vim-style helpers:
   - `style#get_color(attr, group...)` → gui/cterm color from a highlight group.
   - `style#ansi(str, group, default, bold)` → wrap a string in the group's fg/bg.
   - Color wrappers for the existing `VimOpencode*` groups.
   - `style#key_label(keys)` → `C-X`, `A-S`, etc.
3. Create `popup.vim` with `vim_opencode#ui#popup#run(spec)`:
   - accepts `items`, `title`, `border`, `width`, `height`, `row`, `col`, `callback`, `preview`, `footer`, `keymaps`.
   - builds a `popup_create()` window with border/title, installs `<buffer>` mappings, runs the callback on selection, closes on `C-Q`.
   - **scrolling:** map `<C-e>`, `<C-y>`, `<PageUp>`, `<PageDown>`, `<C-d>`, `<C-u>` inside popups to scroll the popup contents (`popup_close`/`popup` navigation or `win_execute` on the popup winid with `normal! <C-e>` etc.); fall back to `inputlist()` when `+popupwin` is unavailable.
4. Add default compound keymaps (opt-in via `default_mappings`). All shortcuts start with `<Leader>o` followed by an obvious letter (2–3 chars total after `<Leader>`). Single-letter entries are leaves (nothing extends them); multi-letter entries group by category prefix.

Daily driver (single letter, leaf mappings):
   - `oh` → `:Opencode help`          (command reference)
   - `oH` → `:Opencode health`        (verify environment/connection)
   - `op` → `:Opencode prompt`        (send a prompt with @ placeholders — most used)
   - `oa` → `:Opencode ask`           (interactively compose a prompt)
   - `ot` → `:Opencode toggle`        (show/hide the split panel)
   - `oo` → `:Opencode open`          (open the panel, right by default)
   - `oe` → `:Opencode ask @this explain` (explain the selection/cursor)

Sessions (prefix `os` = session):
   - `osl` → `:Opencode session list`
   - `osp` → `:Opencode session pick`
   - `osn` → `:Opencode session new`
   - `oso` → `:Opencode session open`

Models (prefix `om` = model):
   - `oml` → `:Opencode model list`
   - `omp` → `:Opencode model pick`

Agents (prefix `og` = aGent, since `a` is ask):
   - `ogl` → `:Opencode agent list`
   - `ogp` → `:Opencode agent pick`

Server (prefix `os` too — diverges at the 3rd char, no leaf conflict):
   - `osc` → `:Opencode server connect`
   - `oss` → `:Opencode server status`
   - `osd` → `:Opencode server disconnect`

Permissions (prefix `oq` = question/permission request):
   - `oql` → `:Opencode permission list`
   - `oqa` → `:Opencode permission accept`
   - `oqd` → `:Opencode permission deny`

Diff (prefix `od` = diff):
   - `odo` → `:Opencode diff open`
   - `oda` → `:Opencode diff accept`
   - `odr` → `:Opencode diff reject`

Palette / commands:
   - `ocp` → `:Opencode palette`        (open the interactive command palette — reaches every command)
   - `ocl` → `:Opencode command list`

Expose under `keymaps` in config: `help`, `health`, `prompt`, `ask`, `toggle`, `open`, `explain`, `session_list`, `session_pick`, `session_new`, `session_open`, `model_list`, `model_pick`, `agent_list`, `agent_pick`, `server_connect`, `server_status`, `server_disconnect`, `permission_list`, `permission_accept`, `permission_deny`, `diff_open`, `diff_accept`, `diff_reject`, `palette`, `command_list`. Defaults map to the `<Leader>o*` chords above.

Note: `ot` (toggle) is a leaf, so it cannot be extended (no `otl`/`otn` for tabs); tabs keep their existing `tab` subcommand or a user-chosen mapping. `oc` is deliberately not a leaf so `osc`/`oss`/`ocp`/`ocl` can coexist.

**Acceptance:** a `:Opencode palette` stub exists and opens a bordered popup listing commands; popups scroll with `<C-e>`/`<C-y>`/`<PageUp>`/`<PageDown>`; no hard-coded colors; the full `<Leader>o*` chord set works when `default_mappings: true`; falls back cleanly without `+popupwin`.

### Phase 1 — Replace `inputlist()` pickers with styled popups
**Files:** `autoload/vim_opencode/catalog.vim` (`ShowPicker`), `autoload/vim_opencode/sessions.vim` (list/pick), `autoload/vim_opencode/permissions.vim` (pending list)

4. Convert `catalog.vim` `ShowPicker()` (`model`/`agent`/`command`) from `popup_menu()` bare + `inputlist()` fallback to the styled popup runner with title, footer hint (`Enter pick / C-P preview / C-Q quit`), and highlight-derived colors.
5. Convert `sessions.List()`/`Pick()` and `permissions.Pending()` display to the same styled popup runner.
6. Add a preview callback for pickers: highlight a session → preview its latest message; highlight a model → show provider/model; highlight a command → show its `description`/`hint`.

**Acceptance:** `:Opencode model pick`, `agent pick`, `command pick`, `session pick`, `permission list` open bordered titled popups with footer hints; `inputlist()` remains the fallback.

### Phase 2 — Interactive command palette (reach all commands)
**Files:** `autoload/vim_opencode/commands.vim` (add `palette` to COMMANDS + dispatch), `autoload/vim_opencode/ui/palette.vim` (new)

7. Register a new `palette` command in `COMMANDS` and wire `Dispatch()` to `palette.Palette()`.
8. Build `palette.vim`:
   - source = flattened list of all `COMMANDS` entries plus session/model/agent/command/permission/diff/review/tab sub-actions (each with `name`, `description`, `handler` funcref).
   - as-you-type fuzzy filter over `name`/`description` (vim regex filter, no external dependency).
   - `Enter` → run handler; `C-P` → preview; `C-Q` → close; `C-H` → show help summary; `jk/↑↓` navigate.
   - persistent last-selection and recent-commands MRU.
9. Add default mapping `<Leader>ocp` → `:Opencode palette` (opt-in via `default_mappings`, consistent with the `<Leader>o*` chord set; `oc` is deliberately not a leaf so `osc`/`oss`/`ocp`/`ocl` can coexist).

**Acceptance:** one palette popup can launch every `:Opencode` command and sub-action without leaving normal mode.

### Phase 3 — Preview windows (fzf `--preview` / `--preview-window`)
**Files:** `autoload/vim_opencode/ui/preview.vim` (new), `autoload/vim_opencode/ui/popup.vim` (extend)

10. Add `preview` support to the popup runner: a second popup (or split) positioned to the right/bottom showing context for the highlighted entry.
11. Implement preview providers:
    - session → last N messages / diff summary (reuse `state.Messages()`);
    - model → providerID/modelID/key;
    - command → description + hint;
    - permission → request id/title;
    - diff → the active diff text (reuse `diff.vim`).
12. Center preview on the matched field where applicable (analogous to fzf's `'+{2}/2'`).

**Acceptance:** moving the picker/palette cursor updates a side preview without closing the list.

### Phase 4 — Show / peek key (fzf `ctrl-o` via IPC + win_execute)
**Files:** `autoload/vim_opencode/ui/popup.vim` (extend), optionally `autoload/vim_opencode/ui/ipc.vim` (new)

13. Add a `show_key` (default `C-O`) binding to every popup:
    - on press, run the highlighted entry's handler in the *origin* window via `win_execute(origin_winid, …)` without closing the popup (`vim_opencode#ui#ipc#start`-style fifo only if needed for async; for sync commands `win_execute` suffices).
14. Guard with the same preconditions as fzf's `s:can_show`: `+terminal`/`+patch-8.0.995`, `win_execute` exists, not Win32, no active bang/fullscreen layout.

**Acceptance:** `C-O` in a picker opens the selected session/model/command in the editing window while the popup stays open.

### Phase 5 — Panel chrome & consistent styling
**Files:** `autoload/vim_opencode/ui/panel.vim`, `autoload/vim_opencode/ui/diff.vim`, `plugin/vim-opencode.vim` (highlights)

15. Add a title bar + border + footer hint line to the split panel (`InfoChunk()` already builds a header; render it as a title/footer with border highlights).
16. **Scrolling:** ensure `<C-e>`/`<C-y>`/`<PageUp>`/`<PageDown>`/`<C-d>`/`<C-u>` scroll the transcript/output window when focus is there (and popups from Phase 0).
17. **Model-state status bar:** color the panel/statusline pill based on server/session/model state, driven by the plugin's events:
   - `idle` — muted/base (`VimOpencodeMuted`): connected, nothing in flight.
   - `connected` / ready — green-ish (`VimOpencodeInfo`): `server.connected`, session ready.
   - `thinking` / streaming / tool running — yellow (`VimOpencodeReasoning`): `prompt.sent` (request in flight), `session.status` reporting in-progress/thinking.
   - `error` / disconnected — red (`VimOpencodeError`): `server.disconnected`, `prompt.failed`, `session.status` error.
   Derive the colors from highlight groups via `style#get_color` (never hard-code ANSI). Listen to `OpencodeEvent:*` User autocmds / `events.AddListener` to flip the pill.
18. Apply the same highlight-derived colors and key labels to panel mappings (`q`, `]m`, `[m`, `]u`, `[u`, `<CR>`, `C-p`, `C-n`) so panel, palette, and pickers look like one UI.
19. **Default right position:** `:Opencode open` and `:Opencode toggle` open the panel to the **right** of the screen (vertical split) unless `gui.default_position` is `'horizontal'`/`'popup'` or an explicit target (`open [input|output|panel]` / `panel.position`) overrides it.

**Acceptance:** panel and popups share border/title/footer styling; statusline pill reflects connection/model state (idle/connected/thinking/error) with highlight-derived colors; panel opens to the right by default; scrolling works in transcript and popups.

### Phase 6 — Polish, config, docs, tests
**Files:** `doc/vim-opencode.txt`, `FEATURES.md`, `test/`

21. Document `gui.*` config options and the palette/picker/preview/peek keybindings in `doc/vim-opencode.txt` and `FEATURES.md`.
22. Add headless smoke tests (in `test/`) for: popup open/close, picker selection, palette dispatch of a real command, fallback without `+popupwin`, show/peek behavior.
23. Run `./test/run.sh` and fix regressions.

**Acceptance:** full test suite passes; help file documents all new GUI options and keys.

---

## 6. File map (new / touched)

| File | Action | Role |
|---|---|---|
| `autoload/vim_opencode/ui/style.vim` | new | Highlight-group→color helpers (fzf `s:get_color`/`s:ansi`/`s:key_label`). |
| `autoload/vim_opencode/ui/popup.vim` | new | Generic bordered popup runner with footer, preview, keymaps, fallback. |
| `autoload/vim_opencode/ui/palette.vim` | new | Interactive command palette reaching all `:Opencode` commands. |
| `autoload/vim_opencode/ui/preview.vim` | new | Side preview providers for picker/palette entries. |
| `autoload/vim_opencode/ui/ipc.vim` | new (optional) | Show/peek key via fifo + `win_execute` (fzf `ipc.vim` model). |
| `autoload/vim_opencode/config.vim` | extend | `gui.*` defaults + validation. |
| `autoload/vim_opencode/catalog.vim` | edit | Styled popups for model/agent/command pickers. |
| `autoload/vim_opencode/sessions.vim` | edit | Styled popups for session list/pick. |
| `autoload/vim_opencode/permissions.vim` | edit | Styled popup for pending permissions. |
| `autoload/vim_opencode/commands.vim` | edit | Register `palette` command + dispatch. |
| `autoload/vim_opencode/ui/panel.vim` | edit | Panel title/border/footer chrome + statusline pill + scrolling + right-default position. |
| `plugin/vim-opencode.vim` | edit | Default mappings `<Leader>oc` (palette), `<Leader>oo` (open), `<Leader>oe` (`ask @this explain`), palette highlight groups. |
| `doc/vim-opencode.txt` | edit | Document GUI config, palette, pickers, preview, peek key, shortcuts `oo`/`oe`, right-default position. |
| `FEATURES.md` | edit | Feature table + keymap additions (`oo`, `oe`, palette, rounded borders, scrolling, status bar). |
| `test/` | add | Headless smoke tests for popups/palette/pickers. |

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| `+popupwin` / `popup_create()` missing on older Vim 9.1 builds | Guard with `has('popupwin')`/`exists('*popup_create()')`; fall back to `inputlist()`/`:echomsg`. |
| Hard-coded colors clash with colorschemes | Always derive from highlight groups via `style#get_color`; provide `gui.colors = 0` to disable. |
| Popup mappings interfere with buffer-local mappings | Use `<buffer>` scoped mappings inside the popup only; restore focus to origin window on close. |
| Async peek blocking Vim | Keep peek sync where possible; use `job_start`/`timer` only for network/preview work; never `sleep`. |
| Long command lists slow the popup | Cap palette source at a few hundred entries; fuzzy filter incrementally; lazy-load server catalogs. |

---

## 8. Success criteria

- [ ] One interactive palette popup can reach every `:Opencode` command and sub-action.
- [ ] All pickers (model, agent, command, session, permission) are styled bordered popups with footer hints.
- [ ] Colors are derived from Vim highlight groups (no hard-coded ANSI), honoring `termguicolors`/`cterm`.
- [ ] Preview pane shows context for the highlighted entry; show/peek key works without closing popups.
- [ ] Graceful fallback to `inputlist()` when `+popupwin` is unavailable.
- [ ] Scrolling works in popups and the transcript (`<C-e>`/`<C-y>`/`<PageUp>`/`<PageDown>`/`<C-d>`/`<C-u>`).
- [ ] Status bar pill reflects model state (idle/connected/thinking/error) with highlight-derived colors.
- [ ] Panel opens to the right by default unless `gui.default_position` or an explicit target overrides.
- [ ] Plan + implementation committed on branch `feature/gui-popup-styling-plan`; tests pass.

---

## 9. Open questions for implementation

Before coding, I'd like to confirm the following decisions:

1. **`oo` / `oe` chord semantics:** The existing mappings are single keys after `<Leader>o` (e.g. `<Leader>ot` = toggle). `oo`/`oe` would be two-char chords after `<Leader>o` (e.g. `<Leader>oo`, `<Leader>oe`). Should these replace/extend the `keymaps` table as new keys `open`/`explain`, or should they be separate top-level `keymaps` entries? Vim's `maparg`/mapping resolution can be ambiguous with prefix chords (`<Leader>o` vs `<Leader>oo`), so confirm the intended table shape and whether `<Leader>o` itself should remain unmapped.

2. **Rounded border feasibility:** `popup_create()` supports a `border` dict with `chars` (e.g. `['╭','─','╮','│','╯','─','╰','│']`). Rounded box-drawing glyphs render correctly only when `&ambiwidth` is single and the font/gui has the glyphs; on double-width ambiwidth or grids without box-drawing support they can misalign. Should the default be `'rounded'` only when `&ambiwidth == 'single'` (else `'single'`/`'+|-'`), with `gui.popup_border` to override? Are there terminals/fonts in scope where we should force `'none'`?

3. **Status bar color trigger:** The panel/statusline pill colors by state (idle/connected/thinking/error). What Vim events/drivers set the `thinking` state — e.g. `session.status` / `prompt.sent` / `prompt.failed` / `server.connected` / `server.disconnected`? Should there be an explicit `gui.state` config override, or is it purely derived from `server.Status()`/SSE events?

4. **Right-default vs existing `panel.position`:** `config.panel.position` defaults to `'botright'` (horizontal). The new `gui.default_position` defaults to `'right'` (vertical). When both are set, which wins? Proposed: `gui.default_position` wins for `:Opencode open`/`:Opencode toggle`; `panel.position` remains for direct split geometry. Confirm.

5. **Scrolling implementation:** For popups, `popup_close`/re-create or `win_execute(popup_winid, 'normal! <C-e>')` can scroll contents. For the transcript window, plain window scroll mappings work. Should scrolling use `popup_setoptions`/`popup` navigation or `win_execute` + `normal!`? Any preference to keep the transcript at bottom (auto-scroll) while streaming, overriding manual scroll until the user scrolls up?

6. **`<Leader>oc` palette vs `oo`/`oe`:** Both are opt-in default mappings. Is there a risk of chord collision (`<Leader>o` as a prefix for `c`, `o`, `e`, `t`, `p`, `a`, `h`, `H`)? Confirm the leader key users typically set and whether we should reserve `<Leader>o` exclusively for vim-opencode chords.

---

## 10. References

- `/home/potz/rcs/vim/plugged/fzf.vim/fzf_analysis.json` — fzf.vim spec dict, styling helpers, borders, preview window, show/peek key, footer hints, key labels, layout keys.
- `doc/vim-opencode.txt` — existing vim-opencode user documentation to extend.
- `FEATURES.md` — existing feature/keymap table to extend.
- `plugin/vim-opencode.vim`, `autoload/vim_opencode/commands.vim`, `catalog.vim`, `ui/panel.vim` — current vim-opencode UI surfaces to smoothen.
