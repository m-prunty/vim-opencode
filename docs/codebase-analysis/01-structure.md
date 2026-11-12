# Vim-opencode Codebase Analysis — Part 1: Structure Mapping

## Root Layout

| Path | Type | Purpose |
|------|------|---------|
| `plugin/vim-opencode.vim` | File | Plugin entry point: load guard, `:Opencode` command, default mappings, augroup, highlight setup |
| `autoload/vim_opencode/config.vim` | File | Configuration defaults, deep merge, validation, keymap tables |
| `autoload/vim_opencode/util.vim` | File | Shared helpers: JSON, paths, URL encoding, logging, version compare |
| `autoload/vim_opencode/commands.vim` | File | Command table, parsing, dispatch, completion |
| `autoload/vim_opencode/transport.vim` | File | curl-based HTTP and SSE transport, request tracking, timeouts |
| `autoload/vim_opencode/discovery.vim` | File | Server discovery: configured URL, service registrations, start command, polling |
| `autoload/vim_opencode/server.vim` | File | Connection class: URL, auth, request/stream, shutdown |
| `autoload/vim_opencode/protocol/adapter.vim` | File | Shared protocol adapter interface (stub/defaults) |
| `autoload/vim_opencode/protocol/active.vim` | File | Active protocol dispatcher (v1/v2 delegation) |
| `autoload/vim_opencode/protocol/v1.vim` | File | OpenCode V1 protocol adapter |
| `autoload/vim_opencode/protocol/v2.vim` | File | OpenCode V2 protocol adapter |
| `autoload/vim_opencode/state.vim` | File | Transcript state model: messages, parts, sessions, events |
| `autoload/vim_opencode/events.vim` | File | Event dispatch: listeners, User autocmds, g: event dict |
| `autoload/vim_opencode/context.vim` | File | Editor context capture, placeholder expansion (`@this`, `@buffer`, etc.) |
| `autoload/vim_opencode/prompt.vim` | File | Prompt/ask/operator workflows |
| `autoload/vim_opencode/sessions.vim` | File | Session listing, creation, lifecycle helpers |
| `autoload/vim_opencode/catalog.vim` | File | Model, agent, and server-command catalogs with selection |
| `autoload/vim_opencode/permissions.vim` | File | Pending permission/question requests |
| `autoload/vim_opencode/review.vim` | File | Review comments management |
| `autoload/vim_opencode/tabs.vim` | File | Persistent project-scoped panel tabs |
| `autoload/vim_opencode/quickchat.vim` | File | Quick-chat inline-edit workflow |
| `autoload/vim_opencode/health.vim` | File | Health checks exposed via `:Opencode health` |
| `autoload/vim_opencode/ui/panel.vim` | File | Split-panel transcript and input |
| `autoload/vim_opencode/ui/render.vim` | File | Transcript formatter: chunks, lines, folding |
| `autoload/vim_opencode/ui/popup.vim` | File | Generic bordered popup runner |
| `autoload/vim_opencode/ui/palette.vim` | File | Interactive command palette |
| `autoload/vim_opencode/ui/style.vim` | File | Style helpers (colors from highlight groups, key labels) |
| `autoload/vim_opencode/ui/diff.vim` | File | Minimal single-file edit review |
| `ftplugin/vim-opencode_output.vim` | File | Settings for transcript output buffer |
| `ftplugin/vim-opencode_input.vim` | File | Settings for prompt input buffer (completion) |
| `syntax/vim-opencode_output.vim` | File | Syntax highlighting for transcript |
| `doc/vim-opencode.txt` | File | User documentation |
| `doc/tags` | File | Help tags |
| `README.md` | File | Project overview |
| `FEATURES.md` | File | Feature reference |
| `docs/gui-popup-styling-plan.md` | File | GUI popup styling plan (branch: feature/gui-popup-styling-plan) |
| `docs/analysis/vim9-opencode-implementation-analysis.json` | File | Implementation plan and comparison analysis |
| `docs/analysis/sudo-tee-opencode-nvim.json` | File | sudo-tee/opencode.nvim analysis |
| `docs/analysis/nickjvandyke-opencode-nvim.json` | File | nickjvandyke/opencode.nvim analysis |
| `test/run.sh` | File | Test runner script |
| `test/p0.vim` - `test/p11.vim` | Files | Headless smoke tests (P0-P11) |
| `test/fixtures/server.py` | File | Python fixture OpenCode V2 server |
| `.github/workflows/ci.yml` | File | GitHub Actions CI |
| `.gitignore` | File | Git ignore |

## Autoload Module Details

### plugin/vim-opencode.vim
- Load guard: `g:loaded_vim_opencode`
- Version: `g:vim_opencode_version = '0.1.0-dev'`
- Vim 9.1+ requirement check
- Imports: config, commands, prompt, permissions, diff, style, popup, server, panel, quickchat, tabs
- `g:VimOpencodeShutdown()` - calls `server.Shutdown()`
- `g:VimOpencodeComplete()` - delegates to `commands.Complete()`
- `:Opencode` command definition with `-nargs=* -range -bang -complete=customlist`
- Highlight group definitions: VimOpencodeInfo, VimOpencodeWarn, VimOpencodeError, VimOpencodeMuted, VimOpencodeUser, VimOpencodeTool, VimOpencodeReasoning
- `<Plug>` mappings: help, health, prompt, ask, toggle, operator
- Default mappings block (opt-in via `default_mappings`)
- `panel.Setup()`, `permissions.Setup()`, `diff.Setup()`, `quickchat.Setup()`, `tabs.Setup()`
- Autocmd group `vim-opencode`: `VimLeavePre` → `g:VimOpencodeShutdown()`

### autoload/vim_opencode/config.vim
- `Defaults` const: server_url, server_command, auto_start, protocol, directory, timeouts, reconnect, default_mappings, log_level, log_file, keymaps, gui, server, context, panel, diff
- `Setup(user)`: DeepMerge defaults + user, Validate, Normalize, store in g:vim_opencode_config
- `Get()`: return active config or setup defaults
- `GetPath(path)`: dotted path lookup
- `DeepMerge(base, override)`: recursive merge without mutation
- `Validate(config)`: throws on invalid config
- `Normalize(config)`: strip trailing slashes, normalize paths
- `ValidateServerCommand`, `ValidateKeymaps`, `ValidateServer`, `ValidateContext`, `ValidatePanel`, `ValidateDiff`, `ValidateGui`
- `RequireDict`, `RequireString`, `RequireBool`, `RequirePositiveNumber`, `Prefix`, `Fail`
- `Reset()`: clear g:vim_opencode_config

### autoload/vim_opencode/util.vim
- `LOG_LEVELS` const: silent=0, error=1, warn=2, info=3, debug=4
- `LogLevels()`: return copy of LOG_LEVELS
- `JsonEncode(value)`: json_encode wrapper
- `JsonDecode(text)`: json_decode wrapper
- `UrlEncode(value)`: percent-encode per RFC 3986
- `ExpandPath(path)`: expand() wrapper
- `NormalizePath(path)`: fnamemodify(expand(path), ':p'), strip trailing /
- `Cwd()`: NormalizePath(getcwd())
- `StateDir()`: $XDG_STATE_HOME/vim-opencode or ~/.local/state/vim-opencode
- `TempFile(prefix)`: tempname() .. '-' .. prefix
- `EnsureDir(path)`: mkdir('p')
- `ShellJoin(args)`: shellescape + join
- `IsExecutable(name)`: executable() == 1
- `VersionAtLeast(actual, minimum)`: dotted version comparison
- `VersionParts(version)`: split version into numbers
- `Log(level, message)`: conditional logging to file and echo
- `EchoError(message)`, `EchoWarn(message)`, `EchoInfo(message)`
- `StartsWith(value, prefix)`
- `ExceptionText()`: format exception with throw point

### autoload/vim_opencode/commands.vim
- `COMMANDS` const: command table with phase, usage, description, implemented
- `ARG_COMPLETIONS` const: per-command argument completions
- `Dispatch(args, range, bang)`: main command dispatcher
- `Complete(arglead, cmdline, cursorpos)`: tab completion
- `Table()`: return deepcopy of COMMANDS
- `Help(rest)`, `Version()`, `ShowConfig(rest)`
- `ContextCommand(rest, range)`, `PromptCommand(rest, range)`, `AskCommand(rest, range)`, `OperatorCommand(rest)`
- `Server(rest)`, `Session(rest, bang)`, `Permission(rest)`, `Diff(rest)`, `Review(rest)`, `Tab(rest)`, `Model(rest)`, `Agent(rest)`, `Command(rest)`
- `ShowServerStatus()`, `ConnectServer()`, `ServerConnected(conn)`, `DisconnectServer()`, `StartServer()`, `StopServer()`
- `NotImplemented(name, phase)`, `DebugCommand(rest)`
- `PluginVersion()`, `VimVersion()`

### autoload/vim_opencode/transport.vim
- `next_id`, `requests`, `channels`, `timers` module state
- `Request(opts)`: start JSON request via curl job
- `Stream(opts)`: start SSE stream via curl job
- `Close(id)`: stop request/stream
- `CloseAll()`: stop all tracked jobs
- `Count()`, `IsActive(id)`
- `BuildArgs(req, opts, stream)`: build curl argv
- `ChannelKey(ch)`: channel id string
- `ArmTimer(req, timeout_ms)`: arm timeout timer
- Job callbacks: `g:VimOpencodeTransportOut`, `g:VimOpencodeTransportErr`, `g:VimOpencodeTransportExit`, `g:VimOpencodeTransportTimeout`
- `HandleStreamLine(req, line)`: SSE line parsing
- `DispatchFrame(req)`: decode SSE frame JSON
- `Finish(key, exit_status)`: request completion handler
- `Fail(key, message)`: request failure handler
- `StopTimer(req)`, `Cleanup(req)`, `CleanupFiles(req)`
- `ReadBody(file)`, `ReadStatus(file)`
- `FormatError(req, exit_status, status, body)`, `Truncate(value, limit)`

### autoload/vim_opencode/discovery.vim
- `POLL_INTERVAL_MS = 500`, `POLL_ATTEMPTS = 10`
- `poll_timer`, `poll_attempts`, `poll_callbacks`, `start_job` module state
- `StateDir()`: OpenCode state dir ($XDG_STATE_HOME/opencode)
- `Registrations()`: read service*.json files newest first
- `ReadRegistration(path)`: parse single registration file
- `CompareRegistrations(a, b)`: sort by mtime desc
- `Configured()`: return configured server URL candidate
- `HasStartCommand()`: check server_command configured
- `Start(on_error)`: job_start server command
- `StopStarted()`: stop started server job
- `Connect(callbacks)`: discover, probe, subscribe
- `TryCandidates(candidates, index, callbacks, polling)`: iterate candidates
- `CandidateSucceeded(conn, info, callbacks)`: set current, subscribe
- `Subscribe(conn)`: active.Subscribe
- `OnEvent(conn, event)`, `OnStreamError(conn, message)`, `OnStreamClose(conn)`
- `ScheduleReconnect(conn)`, `RetrySubscribe(conn)`
- `BeginPoll(callbacks)`, `PollTick()`, `SchedulePoll(callbacks)`, `StopPoll()`
- `FirstLine(value)`, `IsCurrent(conn)`, `Invoke(callback, args)`

### autoload/vim_opencode/server.vim
- `Connection` class: url, username, password, directory, headers, timeout_ms, version, info, stream_id, connected, reconnect fields
- `new(url, opts)`, `Url()`, `Version()`, `Info()`, `SetInfo(value)`, `IsConnected()`, `SetConnected(value)`
- `Request(path, method, body, on_success, on_error)`, `Stream(path, callbacks)`
- `CloseStream()`, `SetReconnect(enabled)`, `ResetReconnect()`, `NextReconnectDelay()`, `ReconnectTimer()`, `SetReconnectTimer(timer)`
- `current` module state, `New(url, opts)`, `Current()`, `SetCurrent(conn)`, `ClearCurrent()`
- `Disconnect(conn)`, `Shutdown()`, `Status()`

### autoload/vim_opencode/protocol/adapter.vim
- Interface stub: `CanProbe()`, `Probe()`, `Subscribe()`, `Version()`, `Healthy()`, `EventType()`, `EventData()`, `ResolveSession()`, `ListSessions()`, `CreateSession()`, `RenameSession()`, `DeleteSession()`, `InterruptSession()`, `ForkSession()`, `SessionValue()`, `SessionId()`, `ListModels()`, `ListProviders()`, `ListAgents()`, `ListCommands()`, `ReplyPermission()`, `ReplyQuestion()`, `RunCommand()`, `Prompt()`, `LoadMessages()`, `SessionDiff()`
- `Fail(on_error, message)`: default error handler

### autoload/vim_opencode/protocol/active.vim
- `Protocol()`, `SetProtocol(p)`, `IsV1()`
- Delegates all operations to v1 or v2 based on `Protocol()`
- `Probe`, `Subscribe`, `Version`, `Healthy`, `EventType`, `EventData`, `ResolveSession`, `ListSessions`, `CreateSession`, `RenameSession`, `DeleteSession`, `InterruptSession`, `ForkSession`, `SessionValue`, `SessionId`, `ListModels`, `ListProviders`, `ListAgents`, `ListCommands`, `ReplyPermission`, `ReplyQuestion`, `RunCommand`, `Prompt`, `LoadMessages`, `SessionDiff`

### autoload/vim_opencode/protocol/v1.vim
- `HEALTH_PATH = '/global/health'`, `EVENT_PATH = '/global/event'`, `HEARTBEAT_MS = 20000`
- `Probe`, `Subscribe`, `Version`, `Healthy`, `EventType`, `EventData`
- `ResolveSession`, `ListSessions`, `CreateSession`, `RenameSession`, `DeleteSession`, `InterruptSession`, `ForkSession`
- `SessionValue`, `SessionId`, `ListModels`, `ListProviders`, `ListAgents`, `ListCommands`, `ReplyPermission`, `ReplyQuestion`, `RunCommand`, `Prompt`, `LoadMessages`, `SessionDiff`
- `HandleSessions`, `IsArchived`, `NormalizeInfo`, `NormalizeEvent`, `NormalizeSession`
- `Invoke(callback, args)`

### autoload/vim_opencode/protocol/v2.vim
- `INFO_PATH = '/api/info'`, `EVENT_PATH = '/api/event'`, `HEARTBEAT_MS = 20000`
- Same function set as v1.vim but with V2 endpoints
- `HandleSessions`, `HandleSessionList`, `IsArchived`
- `SessionValue`, `SessionId`
- `Invoke(callback, args)`

### autoload/vim_opencode/state.vim
- Module state: session_id, model, messages, index, version, optimistic_seq, listeners
- `SessionId()`, `Model()`, `Version()`, `Messages()`, `AddListener`, `RemoveListener`, `Status()`
- `Reset(new_session)`, `EnsureSession(new_session)`, `Clear()`
- `Snapshot(new_session, items)`, `AddUser(new_session, text)`, `AddNotice(new_session, text, description)`
- `Apply(event)`: main event application dispatcher (28+ event types)
- `ApplyOrdinal`, `ApplyToolStart`, `ApplyToolInput`, `ApplyToolCalled`, `ApplyToolFinished`, `ApplyStepFinished`
- `ApplyInbox`, `ApplySynthetic`, `ApplyRevert`, `ApplyMessageUpdated`, `ApplyMessageRemoved`, `ApplyPartUpdated`, `ApplyPartDelta`, `ApplyPartRemoved`
- `IngestMessage`, `IngestPart`, `IngestTool`
- `EnsureMessage(id, kind)`, `EnsurePart(message, key, kind)`, `FindMessage(id)`, `FindPartById(message, id)`, `FindTool(data)`
- `RemoveMessage(id)`, `DropOptimistic(text)`, `Reindex()`, `Touch()`
- `HandledEvent(event_type)`, `ModelText(value)`, `GetString(dict, key)`

### autoload/vim_opencode/events.vim
- `listeners` module state
- `AddListener(Callback)`, `RemoveListener(Callback)`, `ListenerCount()`
- `Emit(event)`: emit to listeners + User autocmd + g:vim_opencode_event
- `EmitLocal(event_type, data)`: emit local synthetic event
- `Type(event)`, `Data(event)`, `Id(event)`, `Last()`

### autoload/vim_opencode/context.vim
- `PLACEHOLDERS` const: @diagnostics, @quickfix, @buffers, @visible, @buffer, @marks, @this
- `sent_hashes` module state
- `Capture(line_range)`, `CaptureOperator(operator_type)`
- `Highlight(ctx)`, `Clear(ctx)`, `Resume(ctx)`
- `Render(text, ctx)`: placeholder expansion
- `Placeholders()`, `Rich(ctx)`, `Changed(session_id, ctx)`, `ClearSent(session_id)`
- `GitDiff(cwd, file)`
- `Build(placeholder, ctx)`, `This(ctx)`, `Buffer(ctx)`, `Buffers(ctx)`, `Visible(ctx)`, `Quickfix(ctx)`, `Marks(ctx)`, `Diagnostics(ctx)`
- `FormatRange(buf, from, to, kind, cwd)`, `FormatLocation(buf, lnum, col, cwd)`
- `RangeText(buf, from, to, kind)`, `IsFileBuffer(buf)`, `RelativePath(path, cwd)`, `LineLength(lnum, buf)`
- `Positions(ctx)`, `ReplaceAll(text, needle, replacement)`

### autoload/vim_opencode/prompt.vim
- `Send(text, line_range)`, `SendWithContext(text, ctx)`
- `AskWithRange(initial, line_range)`, `AskWithContext(initial, ctx)`
- `OperatorExpr(prompt_text)`, `OperatorCommand(prompt_text)`
- `g:VimOpencodeOperator(operator_type)`
- `g:VimOpencodeAskComplete(arglead, cmdline, cursorpos)`
- `EnsureConnection(on_ready, on_error)`, `Continue(conn, text, ctx)`, `Submit(conn, session, text, ctx)`
- `Succeeded(ctx, session_id, text)`, `Fail(ctx, message)`, `Invoke(callback, args)`

### autoload/vim_opencode/sessions.vim
- `cache` module state
- `Cached()`, `Current()`, `Title(session)`, `Format(session, index)`
- `Refresh(on_success, on_error)`, `ResolveToken(token)`
- `List()`, `PrintList(sessions)`, `Pick()`, `ShowPicker(sessions)`
- `Open(token)`, `New(title)`, `Rename(token, title)`, `Delete(token, force)`, `Fork(token)`
- `OpenSession(session)`, `UpdateCachedTitle(id, title)`
- `Fail(on_error, message)`, `Invoke(callback, args)`

### autoload/vim_opencode/catalog.vim
- `models`, `agents`, `commands`, `selected_model`, `selected_agent`, `prefs_loaded` module state
- `PLACEHOLDERS` const
- `Models()`, `Agents()`, `Commands()`
- `RefreshModels`, `RefreshAgents`, `RefreshCommands`
- `CurrentModel()`, `ModelLabel()`, `CurrentAgent()`, `AgentLabel()`
- `SelectModel(token)`, `ClearModel()`, `SelectAgent(token)`, `ClearAgent()`
- `PromptOptions()`, `FindModel(token)`, `FindAgent(token)`
- `ListModels()`, `ListAgents()`, `ListCommands()`
- `ListPopup(kind, items)`, `PrintEntries(kind, items, current)`, `FormatEntry(kind, entry, index, current)`
- `ShowPicker(kind, items)`, `ChooseEntry(kind, index)`
- `RunCommand(name, arguments)`, `RunInSession(conn, session_id, name, arguments)`, `RunFromPicker(entry)`
- `Complete(base)`: input completion candidates
- `PreferencesFile()`, `LoadPrefs()`, `SavePrefs()`
- `NormalizeModels(value)`, `AddProviderModels(out, provider_id, provider)`, `AddModel(out, raw, fallback_provider)`
- `NormalizeAgents(value)`, `NormalizeCommands(value)`
- `Unwrap(value)`, `Collection(value)`, `FindByKey(items, key)`
- `RequireConnection(on_error)`, `Done(on_success, value)`, `Fail(on_error, message)`, `Invoke(callback, args)`, `GetString(dict, key)`

### autoload/vim_opencode/permissions.vim
- `pending`, `listener_installed` module state
- `Setup()`, `Pending()`, `Count()`, `Add(request)`, `Remove(id)`, `Clear()`, `Current()`, `ResolveToken(token)`
- `Accept(token)`, `Always(token)`, `Deny(token)`, `Answer(token, answer)`, `Ask()`
- `Reply(token, action, always)`, `AnswerQuestion(id, answer)`
- `OnEvent(event)`, `Normalize(request)`, `GetString(dict, key)`

### autoload/vim_opencode/review.vim
- `comments`, `next_id` module state
- `Add(file, line, text, end_line)`, `Remove(id)`, `Clear()`, `List()`, `Text()`
- `MarkSent()`, `AddCurrent(text)`

### autoload/vim_opencode/tabs.vim
- `tabs`, `current`, `loaded` module state
- `Setup()`, `List()`, `Current()`, `New(session_id)`, `Select(token)`, `Close(token)`, `Format(tab, index)`, `File()`
- `EnsureCurrent()`, `Resolve(token)`, `Save()`, `Restore()`
- `OnEvent(event)`: handles session.opened, session.deleted

### autoload/vim_opencode/quickchat.vim
- `qc_state`, `installed` module state
- `Setup()`, `Active()`, `Start(instruction, line_range)`, `Cancel()`
- `Create(conn)`, `OnEvent(event)`, `Apply(text)`, `Fail(message)`, `LineLength(buf, line)`, `Noop(value, status)`

### autoload/vim_opencode/health.vim
- `REQUIRED_FEATURES`, `OPTIONAL_FEATURES` consts
- `Report()`, `Run()`, `Ok()`
- `Status(ok, label, note)`, `ModuleStatus(name, path, phase)`, `VimVersion()`, `CurlVersion()`

### autoload/vim_opencode/ui/panel.vim
- Constants: OUTPUT_NAME, INPUT_NAME, OUTPUT_FILETYPE, INPUT_FILETYPE, INPUT_HEIGHT, SNAPSHOT_LIMIT
- Module state: output_buf, input_buf, output_win, input_win, main_win, flush_timer, rendered, draft, history, history_index, setup_done, loading_session, session_pinned
- `Setup()`, `IsOpen()`, `Toggle()`, `Open()`, `InfoChunk()`, `Close()`, `FocusInput()`, `FocusOutput()`, `OpenTarget(target)`, `CloseTarget(target)`
- `EnsureBuffers()`, `BufferFor(name, filetype)`, `ApplyBufferOptions(buf, editable)`
- `ApplyOutputWindowOptions()`, `ApplyInputWindowOptions()`, `ApplyStatusline()`, `StatuslineState()`, `StateLabel()`, `UpdateStatusline()`
- `InstallMappings()`
- `InputText()`, `SetInput(text)`, `ClearInput()`
- `Submit()`, `CaptureMainContext()`
- `HistoryPrev()`, `HistoryNext()`
- `OnStateChanged()`, `MarkDirty()`, `StopFlushTimer()`, `g:VimOpencodePanelFlush(timer)`, `Flush()`
- `CommonPrefix(chunks)`, `BufferLineCount(buf)`, `WindowView(win)`, `ViewAtBottom(line_count)`, `ReplaceFrom(start_line, new_lines)`
- `EnsurePropTypes()`, `PropName(group)`, `ApplyProps(chunks, common, start_line)`, `CreateFolds(chunks, common)`
- `OpenSession(session_id)`, `FollowRecent()`, `EnsureSessionAsync()`, `AttachSession(conn, session)`, `LoadSnapshot(conn, session_id)`
- `OnEvent(event)`: handles server.connected, catalog events, prompt.sent, state.Apply
- `NextMessage()`, `PrevMessage()`, `NextUser()`, `PrevUser()`, `JumpMessage(direction, user_only)`, `JumpToFile()`
- Global wrappers: g:VimOpencodePanelSubmit, g:VimOpencodePanelClose, g:VimOpencodePanelJump, g:VimOpencodePanelNextMessage, g:VimOpencodePanelPrevMessage, g:VimOpencodePanelNextUser, g:VimOpencodePanelPrevUser, g:VimOpencodePanelHistoryPrev, g:VimOpencodePanelHistoryNext

### autoload/vim_opencode/ui/render.vim
- Constants: MAX_REASONING_LINES=80, MAX_TOOL_LINES=120, MAX_INPUT_CHARS=400, MAX_RESULT_CHARS=2000
- `Chunks(max_messages)`, `Lines(chunks)`, `MessageLines(chunks)`
- `ChunksForMessage(message)`, `MarkStart(chunks)`, `ToolLines(part)`
- `ResultLines(result)`, `ErrorText(error)`, `JsonText(value)`
- `SplitLines(text)`, `PrefixLines(text, prefix)`, `IndentLines(lines)`, `CapLines(lines, limit)`, `CapText(value, limit)`

### autoload/vim_opencode/ui/popup.vim
- `DEFAULT_BORDER_CHARS`, `SINGLE_BORDER_CHARS` consts
- `open_popups` module state
- `EnsureGlobals()`, `BuildLines(spec)`, `GetConfig()`, `BorderName(style)`
- `Run(spec)`: create popup window or fallback to inputlist
- `InstallPopupMappings(info)`
- Global wrappers: g:VimOpencodePopupSelect, g:VimOpencodePopupPeek, g:VimOpencodePopupCloseById, g:VimOpencodePopupScrollDown, g:VimOpencodePopupScrollUp, g:VimOpencodePopupScrollDownPage, g:VimOpencodePopupScrollUpPage
- `CurrentPopupId()`, `CurrentPopup()`, `CurrentPopupLine()`, `CurrentPopupOffset()`
- `CloseAll(info)`, `RunInputlist(spec)`

### autoload/vim_opencode/ui/palette.vim
- `palette_state` module state
- `Source()`: flattened commands + sub-actions
- `FormatEntry(entry)`, `Filtered()`
- `Palette(info)`: run the palette popup
- Global wrappers: g:PaletteRunSelection, g:PaletteStartFilter, g:PaletteHelp, g:PalettePreview, g:PaletteNext, g:PalettePrev

### autoload/vim_opencode/ui/style.vim
- `GetColor(info)`, `GetColorAny(info)`, `KeyLabel(info)`, `KeyLabels(info)`

### autoload/vim_opencode/ui/diff.vim
- `active`, `original_buf`, `proposed_buf`, `original_win`, `proposed_win`, `installed` module state
- `Setup()`, `Current()`, `Set(file, text, request_id)`, `Open()`, `Accept()`, `Reject()`, `Close()`
- `InstallMappings()`, `OnEvent(event)`
- Global wrappers: g:VimOpencodeDiffAccept, g:VimOpencodeDiffReject

### ftplugin/vim-opencode_output.vim
- Buffer settings for transcript: buftype=nofile, bufhidden=wipe, noswapfile, nobuflisted, nomodifiable, readonly, noundofile, foldmethod=manual, foldcolumn=1, wrap, linebreak, nonumber, norelativenumber
- `b:undo_ftplugin`

### ftplugin/vim-opencode_input.vim
- Buffer settings for input: buftype=nofile, bufhidden=wipe, noswapfile, nobuflisted, nonumber, norelativenumber, noundofile, wrap, linebreak
- `g:VimOpencodeInputComplete(findstart, base)`: omnifunc using catalog.Complete()
- `completeopt=menu,menuone,noinsert`, `omnifunc=g:VimOpencodeInputComplete`

### syntax/vim-opencode_output.vim
- Syntax matches: VimOpencodeHeading, VimOpencodeUser, VimOpencodeTool, VimOpencodePath, VimOpencodeCode
- Highlight links

## Test Files

| Test | Purpose | Needs server fixture |
|------|---------|---------------------|
| p0.vim | Plugin loading, config, commands, completion, health, util | No |
| p1.vim | Transport, discovery, connection lifecycle | Yes (port 18767) |
| p2.vim | Context, sessions, prompt submission | Yes (port 18769) |
| p3.vim | Split panel, streaming renderer | No |
| p4.vim | Session lifecycle, catalogs, commands, prompts | Yes (port 18771) |
| p5.vim | Permissions/questions state and V2 replies | Yes (port 18772) |
| p6.vim | Context dedup, review comments | No |
| p7.vim | Command registration, quickchat cancellation | No |
| p8.vim | Persistent panel tabs | No |
| p9.vim | V1 adapter normalization | No |
| p10.vim | Render capping, transport errors, config validation | No |
| p11.vim | GUI popups, styling, palette, keymaps | No |

## Analysis Docs

- `docs/analysis/vim9-opencode-implementation-analysis.json`: Full implementation plan (P0-P10), architecture, module layout, data model, transport model, async model, UI model, protocol, persistence, implementation pathways, alternative pathways, milestones, risks, testing strategy
- `docs/analysis/sudo-tee-opencode-nvim.json`: 182 Lua files, ~49.6k lines Neovim plugin analysis
- `docs/analysis/nickjvandyke-opencode-nvim.json`: 19 Lua files, ~2.4k lines Neovim plugin analysis
- `docs/gui-popup-styling-plan.md`: GUI popup styling plan (10 phases)
