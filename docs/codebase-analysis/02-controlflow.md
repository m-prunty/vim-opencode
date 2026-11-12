# Vim-opencode Codebase Analysis — Part 2: Implementation Routes & Control Flow Pathways

## Command Dispatch Route (Primary Entry)

```
User types :Opencode <args>
        |
        v
plugin/vim-opencode.vim :Opencode command definition
        |
        v
commands.Dispatch(args, range, bang)
        |
        +-- name == ''          -> Help('')  (shows command summary)
        +-- name == 'help'      -> Help(rest)
        +-- name == 'version'   -> Version()
        +-- name == 'health'    -> health.Run()
        +-- name == 'config'    -> ShowConfig(rest)
        +-- name == 'server'    -> Server(rest)
        +-- name == 'session'   -> Session(rest, bang)
        +-- name == 'model'     -> Model(rest)
        +-- name == 'agent'     -> Agent(rest)
        +-- name == 'command'   -> Command(rest)
        +-- name == 'permission'-> Permission(rest)
        +-- name == 'diff'      -> Diff(rest)
        +-- name == 'review'    -> Review(rest)
        +-- name == 'quickchat' -> quickchat.Start(trim(rest), range)
        +-- name == 'tab'       -> Tab(rest)
        +-- name == 'prompt'    -> PromptCommand(rest, range)
        +-- name == 'ask'       -> AskCommand(rest, range)
        +-- name == 'operator'  -> OperatorCommand(rest)
        +-- name == 'context'   -> ContextCommand(rest, range)
        +-- name == 'toggle'    -> panel.Toggle()
        +-- name == 'open'      -> panel.OpenTarget(trim(rest))
        +-- name == 'close'     -> panel.CloseTarget(trim(rest))
        +-- name == 'palette'   -> palette.Palette({})
        +-- name == 'debug'     -> DebugCommand(rest)
        +-- implemented command -> NotImplemented(name, phase)
        +-- unknown             -> util.EchoError('unknown command')
        |
        v (all paths wrapped in try/catch -> util.EchoError(util.ExceptionText()))
```

## Prompt/Ask/Operator Control Flow

### :Opencode prompt <text> [range]
```
PromptCommand(rest, range)
  |
  +-- text == ''  -> prompt.AskWithRange('', range)
  +-- text != ''  -> prompt.Send(text, range)
        |
        v
SendWithContext(text, ctx = context.Capture(line_range))
        |
        +-- text ends with '...' -> AskWithContext(text[:-3], ctx)
        +-- text empty           -> EchoError, context.Resume(ctx)
        +-- normal               -> context.Highlight(ctx)
                                      |
                                      v
                              EnsureConnection(on_ready, on_error)
                                      |
                                      +-- conn exists     -> Continue(conn, text, ctx)
                                      +-- conn missing    -> discovery.Connect(...)
                                            |
                                            v
                                    Continue(conn, text, ctx)
                                          |
                                          v
                                    active.ResolveSession(conn, ctx.cwd)
                                          |
                                          v
                                    Submit(conn, session, text, ctx)
                                          |
                                          v
                                    context.Render(text, ctx)  [placeholder expansion]
                                    + review.Text() appended
                                    |
                                    v
                                    active.Prompt(conn, session_id, rendered, ...)
                                          |
                                          +-- success -> Succeeded(ctx, session_id, text)
                                          |             -> context.Clear(ctx)
                                          |             -> events.EmitLocal('prompt.sent', ...)
                                          |             -> echomsg 'prompt sent'
                                          |
                                          +-- error   -> Fail(ctx, message)
                                                -> context.Resume(ctx)
                                                -> events.EmitLocal('prompt.failed', ...)
                                                -> util.EchoError(message)
```

### :Opencode ask [text] [range]
```
AskCommand(rest, range) -> prompt.AskWithRange(rest, range)
        |
        v
AskWithContext(initial, ctx)
        |
        v
context.Highlight(ctx)
        |
        v
input('OpenCode: ', initial, 'customlist,g:VimOpencodeAskComplete')
        |
        +-- answer empty -> context.Resume(ctx)
        +-- answer != '' -> SendWithContext(answer, ctx)  [same flow as prompt above]
```

### :Opencode operator [text] / <Plug>(vim-opencode-operator)
```
OperatorCommand(prompt_text)
        |
        v
OperatorExpr(prompt_text)   [sets g:vim_opencode_operator_prompt, &operatorfunc = 'g:VimOpencodeOperator', returns 'g@']
        |
        v
normal! g@   [triggers operator-pending mode, user selects range]
        |
        v
g:VimOpencodeOperator(operator_type)
        |
        v
SendWithContext(g:vim_opencode_operator_prompt, context.CaptureOperator(operator_type))
        |
        v [same SendWithContext flow as prompt]
```

## Panel Control Flow

### :Opencode toggle / open / close
```
panel.Toggle()
  |
  +-- IsOpen()  -> Close()
  +-- !IsOpen() -> Open()

panel.Open()
  |
  v
Setup()  [state.AddListener(OnStateChanged), events.AddListener(OnEvent)]
  |
  v
EnsureBuffers()  [create output_buf, input_buf via BufferFor]
  |
  v
Split window (vertical rightbelow or cfg.panel.position)
  |
  v
InstallMappings()  [buffer-local <CR>, q, ]m, [m, ]u, [u, C-e, C-y, PageUp/Down, C-d, C-u, input <CR>, C-p, C-n]
  |
  v
Flush()  [render transcript]
  |
  v
FocusInput()
  |
  v
EnsureSessionAsync()  [resolve most recent session for cwd]
  |
  v
events.EmitLocal('panel.opened', ...)

panel.Close()
  |
  v
StopFlushTimer()
  |
  v
draft = InputText()
  |
  v
close input_win, output_win
  |
  v
win_gotoid(main_win)
  |
  v
events.EmitLocal('panel.closed', ...)
```

### Panel Submit Flow
```
panel.Submit()  [from <CR> in input window]
  |
  v
text = InputText()
  |
  +-- empty -> return
  |
  v
history->add(text)
  |
  v
ctx = CaptureMainContext()
  |
  v
ClearInput()
  |
  v
prompt.SendWithContext(text, ctx)  [same prompt flow]
  |
  v
events.EmitLocal('panel.submitted', {text: text})
```

### Panel Streaming/Render Flow
```
state.AddListener(OnStateChanged)  [registered in Setup]
  |
  v
OnStateChanged() -> MarkDirty()
  |
  v
MarkDirty()  [if IsOpen: StopFlushTimer, timer_start(debounce_ms, g:VimOpencodePanelFlush)]
  |
  v
g:VimOpencodePanelFlush(timer) -> Flush()
  |
  v
Flush()
  |
  +-- chunks = [InfoChunk()] + render.Chunks(max_messages)
  +-- common = CommonPrefix(chunks)  [diff against rendered]
  +-- if common == len(rendered) == len(chunks) -> return (no change)
  |
  v
ReplaceFrom(start_line, new_lines)  [rewrite only changed suffix]
  |
  v
ApplyProps(chunks, common, start_line)  [text properties]
  |
  v
CreateFolds(chunks, common)  [manual folds]
  |
  v
rendered = chunks
  |
  v
setbufvar('vim_opencode_message_lines', render.MessageLines(chunks))
  |
  v
restore view (at_bottom -> normal! G, else winrestview)
```

### Panel Session Attachment Flow
```
panel.OpenSession(session_id)
  |
  v
session_pinned = true
  |
  v
Open()
  |
  v
state.EnsureSession(session_id)
  |
  v
rendered = []
  |
  v
LoadSnapshot(conn, session_id)  [active.LoadMessages]
  |
  v
state.Snapshot(session_id, items)  [Reset + IngestMessage for each]
  |
  v
Flush()
  |
  v
events.EmitLocal('session.opened', ...)

EnsureSessionAsync()  [called on open if not pinned]
  |
  v
active.ResolveSession(conn, util.Cwd())
  |
  v
AttachSession(conn, session)
  |
  +-- session_pinned -> return
  +-- id empty -> return
  +-- state.EnsureSession(id) changed || no messages -> LoadSnapshot
  +-- else -> MarkDirty()
```

### Panel Event Handling Flow (OnEvent)
```
panel.OnEvent(event)
  |
  +-- 'server.connected' -> EnsureSessionAsync() + UpdateStatusline()
  +-- catalog event (model.selected/cleared, agent.selected/cleared) -> MarkDirty()
  +-- 'prompt.sent' -> state.EnsureSession(session_id) + state.AddUser(session_id, text) + UpdateStatusline()
  +-- default -> state.Apply(event)
                   |
                   +-- changed -> MarkDirty() + UpdateStatusline()
```

## Server Connection & Discovery Flow

### :Opencode server connect
```
ConnectServer() -> discovery.Connect({on_success, on_error})
        |
        v
discovery.Connect(callbacks)
        |
        +-- connecting == true -> on_error('a discovery is already in progress'); return
        |
        v
connecting = true
        |
        v
Wrap callbacks via ConnectDoneSuccess / ConnectDoneError helpers
  (these reset connecting = false when the async chain resolves)
        |
        v
TryCandidates(wrapped_candidates, 0, wrapped_callbacks, false)
        |
        +-- configured URL exists -> TryCandidates([configured], 0, wrapped, false)
        +-- registrations exist   -> TryCandidates(registrations, 0, wrapped, false)
        +-- has start command     -> Start() -> BeginPoll(wrapped)
        +-- else                  -> connecting = false; on_error('no OpenCode server found')
        |
        v
TryCandidates(candidates, index, callbacks, polling)
        |
        +-- index >= len -> polling ? SchedulePoll(callbacks) : on_error('failed to connect')
        |
        v
conn = server.New(candidate.url, {...})
  |
  v
active.Probe(conn, on_success=CandidateSucceeded, on_error=next candidate)
  |
  v
CandidateSucceeded(conn, info, callbacks)
  |
  v
StopPoll()
  |
  v
conn.SetInfo(info), conn.SetConnected(true), conn.ResetReconnect()
  |
  v
server.SetCurrent(conn)
  |
  v
Subscribe(conn)  [active.Subscribe]
  |
  v
ConnectDoneSuccess(conn, info)  [connecting = false; invoke original on_success]

### Discovery completion helpers
```
ConnectDoneSuccess(conn, info, cb)
  |
  v
connecting = false
  |
  v
Invoke(cb.on_success, [conn, info])

ConnectDoneError(message, cb)
  |
  v
connecting = false
  |
  v
Invoke(cb.on_error, [message])
```
```

### SSE Stream Flow
```
active.Subscribe(conn, on_event, on_error, on_close)
  |
  v
conn.Stream(EVENT_PATH, {on_event, on_error, on_close, heartbeat_ms})
  |
  v
transport.Stream(opts)  [curl job_start]
  |
  v
job callbacks:
  g:VimOpencodeTransportOut(ch, msg)  -> HandleStreamLine(req, msg)
    |
    +-- blank line -> DispatchFrame(req)  [decode JSON, invoke on_event]
    +-- 'data:'    -> accumulate sse_data
    +-- ':'        -> skip (heartbeat/comment)
    +-- else       -> arm timer, ignore
  |
  v
Discovery.OnEvent(conn, event)
  |
  +-- 'server.connected' -> conn.SetConnected(true), ResetReconnect
  +-- 'global.disposed'/'server.instance.disposed' -> server.Disconnect(conn)
  |
  v
events.Emit(event)  [to listeners + User autocmd]
```

### Reconnect Flow
```
OnStreamError / OnStreamClose
  |
  +-- IsCurrent(conn) && reconnect_enabled -> ScheduleReconnect(conn)
        |
        v
ScheduleReconnect(conn)
  |
  v
delay = conn.NextReconnectDelay()  [exponential backoff, capped at max]
  |
  v
timer_start(delay, RetrySubscribe(conn))
  |
  v
RetrySubscribe(conn)
  |
  +-- IsCurrent && reconnect_enabled -> Subscribe(conn)
```

## Session Management Flow

### sessions.List()
```
List() -> Refresh(PrintList, on_error)
        |
        v
Refresh(on_success, on_error)
        |
        +-- no conn -> Fail(on_error, 'not connected')
        |
        v
active.ListSessions(conn, util.Cwd(), on_success=cache update + PrintList, on_error)
        |
        v
PrintList(sessions)  [popup.Run with session list, callback -> OpenSession]
```

### sessions.Open(token)
```
Open(token)
  |
  +-- token == '' -> panel.FollowRecent()
  +-- token != '' -> ResolveToken(token) -> panel.OpenSession(id)
```

### sessions.New(title)
```
New(title)
  |
  v
active.CreateSession(conn, {title}, on_success, on_error)
  |
  v
on_success: active.SessionValue(value) -> get id
  |
  v
Refresh() + panel.OpenSession(id) + events.EmitLocal('session.created', ...)
```

### sessions.Delete(token, force)
```
Delete(token, force)
  |
  +-- !force -> input('Delete session ...? (y/N) ') -> if !'y' return
  |
  v
active.DeleteSession(conn, id, on_success, on_error)
  |
  v
on_success: cache filtered, state.Reset('') if current deleted, Refresh(), events.EmitLocal('session.deleted', ...)
```

### sessions.Fork(token)
```
Fork(token)
  |
  v
active.ForkSession(conn, id, on_success, on_error)
  |
  v
on_success: active.SessionValue(value) -> new_id
  |
  v
Refresh() + panel.OpenSession(new_id) + events.EmitLocal('session.forked', ...)
```

## Catalog/Model/Agent Flow

### catalog.RefreshModels()
```
RefreshModels(on_success, on_error)
  |
  v
active.ListModels(conn, on_success, on_error)
  |
  v
on_success: NormalizeModels(value) -> models
  |
  +-- empty -> active.ListProviders(...) -> NormalizeModels(providers)
  |
  v
Done(on_success, models)

NormalizeModels(value)
  |
  v
Unwrap(value)  [unwrap data/models/agents/commands/providers wrappers]
  |
  +-- dict with providers dict -> AddProviderModels for each
  +-- dict with providers list   -> AddProviderModels for each
  +-- dict single                -> AddModel(source, '')
  +-- list                       -> for each entry: AddModel or AddProviderModels
  |
  v
AddModel(out, raw, fallback_provider)
  |
  v
extract providerID, modelID, name, key = provider/modelID
  |
  v
dedupe by key -> push {key, providerID, modelID, name, variants, raw}
```

### catalog.SelectModel(token)
```
SelectModel(token)
  |
  v
FindModel(token)  [numeric index, key match, name match, prefix match, or '/'-direct]
  |
  v
selected_model = {providerID, modelID}
  |
  v
SavePrefs()  [write to $XDG_STATE_HOME/vim-opencode/favorites.json]
  |
  v
events.EmitLocal('model.selected', ...)
  |
  v
util.EchoInfo('model: ' .. ModelLabel())
```

## Permission Flow

### Event -> Pending Request
```
permissions.OnEvent(event)  [registered via events.AddListener in Setup]
  |
  +-- type == 'permission.asked' or 'question.asked'
  |
  v
data.kind = 'question' or 'permission'
  |
  v
permissions.Add(data)  [Normalize + push to pending + emit 'permission.pending']
```

### permissions.Accept(token) / Deny / Always
```
Reply(token, action, always)
  |
  v
item = ResolveToken(token)
  |
  +-- empty -> EchoError
  |
  v
conn = server.Current()
  |
  +-- none -> EchoError
  |
  v
active.ReplyPermission(conn, item.sessionID, item.id, reply, on_success, on_error)
  |
  v
on_success: Remove(item.id) + events.EmitLocal('permission.replied', ...) + EchoInfo
```

## Diff Review Flow

### diff.OnEvent (event-driven)
```
diff.OnEvent(event)
  |
  +-- type in ['session.diff', 'file.edited', 'edit.proposed']
  |
  v
data.file/path, data.text/content
  |
  v
Set(file, text, request_id)  [active = {file, text, requestID}]
  |
  v
events.EmitLocal('diff.pending', {file: file})
```

### :Opencode diff open/accept/reject/close
```
diff.Open()
  |
  +-- empty active -> EchoInfo
  |
  v
split original file + proposed scratch buffer
  |
  v
diffthis on both windows
  |
  v
InstallMappings()  [<Leader>da accept, <Leader>dr reject]

diff.Accept()
  |
  v
text = from proposed_buf if loaded else active.text
  |
  v
writefile(text, active.file)  [WRITES TO DISK]
  |
  v
Close() + events.EmitLocal('diff.accepted', ...) + active = {}

diff.Reject()
  |
  v
Close() + events.EmitLocal('diff.rejected', ...) + active = {}
```

## QuickChat Flow

```
quickchat.Start(instruction, line_range)
  |
  +-- Active() -> EchoError 'already running'
  |
  v
ctx = context.Capture(line_range)
  |
  +-- not filereadable -> EchoError
  +-- no range -> use current line
  |
  v
qc_state = {ctx, from, to, original, instruction, sessionID: '', cancelled: false}
  |
  v
context.Highlight(ctx)
  |
  v
conn = server.Current()
  |
  +-- exists -> Create(conn)
  +-- none   -> discovery.Connect({on_success: Create, on_error: Fail})
  |
  v
Create(conn)
  |
  v
active.CreateSession(conn, {title: 'vim-opencode quick chat'}, on_success, on_error)
  |
  v
on_success: qc_state.sessionID = id
  |
  v
prompt = 'Return only the complete replacement text...' + instruction + source
  |
  v
active.Prompt(conn, id, rendered, Noop, Fail, opts)
  |
  v
events.EmitLocal('quickchat.started', ...)

quickchat.OnEvent(event)  [registered listener]
  |
  +-- type == 'session.text.ended' && data.sessionID == qc_state.sessionID
  |
  v
Apply(text)
  |
  v
split text into replacement lines
  |
  v
deletebufline(buf, from, to) + appendbufline(buf, from-1, replacement)
  |
  v
context.Clear(ctx) + qc_state = {}
  |
  v
active.DeleteSession(conn, sessionID)  [cleanup temp session]
  |
  v
events.EmitLocal('quickchat.applied', ...)
  |
  v
util.EchoInfo('quick chat edit applied; use u to undo')
```

## Tab Flow

```
tabs.New(session_id)
  |
  v
EnsureCurrent()  [ensure at least tab-1 exists]
  |
  v
tabs->add({id: 'tab-N', sessionID, directory, draft: ''})
  |
  v
current = len(tabs) - 1
  |
  v
Save()  [write to $XDG_STATE_HOME/vim-opencode/tabs-<cwd>.json]
  |
  v
events.EmitLocal('tab.created', ...)

tabs.Select(token)
  |
  v
index = Resolve(token)
  |
  +-- < 0 -> EchoError
  |
  v
current = index
  |
  v
id = tabs[current].sessionID
  |
  +-- id != '' && conn exists -> panel.OpenSession(id)
  +-- else -> panel.Open()
  |
  v
Save() + events.EmitLocal('tab.selected', ...)

tabs.OnEvent(event)
  |
  +-- 'session.opened' -> tabs[current].sessionID = id + Save()
  +-- 'session.deleted' -> filter tabs + Save()
```

## Health Check Flow

```
health.Report()
  |
  v
Check REQUIRED_FEATURES (job, channel, timers) via has()
  |
  v
Check OPTIONAL_FEATURES (textprop, popupwin, diff, quickfix, syntax)
  |
  v
Check curl executable + CurlVersion()
  |
  v
Check config.Get()  [may throw]
  |
  v
ModuleStatus for each autoload file (globpath)
  |
  v
Check doc/tags availability
  |
  v
return lines list

health.Run() -> print lines with highlighting
health.Ok() -> true if no [FAIL] lines
```

## V1 vs V2 Protocol Flow

```
active.Protocol()  [from config.protocol, default v2]
  |
  +-- v1 -> all operations delegate to v1.vim
  |       |-> Probe: GET /global/health
  |       |-> Subscribe: GET /global/event (SSE)
  |       |-> ResolveSession: GET /global/session?directory=...
  |       |-> Events normalized: permission.requested->permission.asked, etc.
  |
  +-- v2 -> all operations delegate to v2.vim
          |-> Probe: GET /api/info
          |-> Subscribe: GET /api/event (SSE)
          |-> ResolveSession: GET /api/session?directory=...&parentID=null
          |-> Events: raw V2 types pass through
```

## Configuration Load Flow

```
plugin/vim-opencode.vim sourced
  |
  v
user_config = get(g:, 'vim_opencode_config', {})
  |
  +-- not dict -> EchoError + finish
  |
  v
config.Setup(user_config)
  |
  v
merged = DeepMerge(deepcopy(Defaults), user)
  |
  v
Validate(merged)  [throws on invalid]
  |
  v
Normalize(merged)  [strip trailing slashes]
  |
  v
g:vim_opencode_config = merged
```

## UI/Popup Flow

```
popup.Run(spec)
  |
  +-- !has('popupwin') -> RunInputlist(spec)  [inputlist fallback]
  |
  v
BuildLines(spec)  [title + border + items + footer]
  |
  v
popup_create(lines, {title, border, padding, width, height, row, col, zindex, focusable, close})
  |
  v
InstallPopupMappings(winid, spec)  [<CR> select, C-o peek, C-q close, C-e/y scroll, etc.]
  |
  v
open_popups->add(winid) + g:vim_opencode_popup_specs[winid] = spec

g:VimOpencodePopupSelect()
  |
  v
spec = g:vim_opencode_popup_specs[winid]
  |
  v
idx = popup_getpos(winid).line - title_lines - border_offset
  |
  v
cb = spec.callback -> call(cb, [items[idx-1]])
  |
  v
VimOpencodePopupCloseById()
```

## Palette Flow

```
palette.Palette(info)
  |
  v
palette_state = {filter, source: Source(), idx: 1}
  |
  v
Source()  [commands.Table() implemented entries + sub-actions]
  |
  v
Filtered()  [by filter substring on label+desc]
  |
  v
popup.Run({items, title, callback: PaletteRunSelection, ...})
  |
  v
g:PaletteRunSelection(info)
  |
  v
parse [N] from selection
  |
  v
entry = Filtered()[choice-1]
  |
  v
execute 'Opencode ' .. (entry.usage or entry.name)
```
