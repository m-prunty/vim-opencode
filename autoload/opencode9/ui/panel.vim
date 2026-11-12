vim9script

# Split-panel transcript and input.
#
# Layout: a configurable horizontal split with the transcript on top and a
# three-line input below it. Streaming events update the state model; a debounce
# timer batches redraws so the editor never blocks on every token.

import autoload 'opencode9/catalog.vim' as catalog
import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/context.vim' as context
import autoload 'opencode9/events.vim' as events
import autoload 'opencode9/prompt.vim' as prompt
import autoload 'opencode9/protocol/v2.vim' as v2
import autoload 'opencode9/server.vim' as server
import autoload 'opencode9/state.vim' as state
import autoload 'opencode9/ui/render.vim' as render
import autoload 'opencode9/util.vim' as util

const OUTPUT_NAME = 'opencode9://transcript'
const INPUT_NAME = 'opencode9://input'
const OUTPUT_FILETYPE = 'opencode9_output'
const INPUT_FILETYPE = 'opencode9_input'
const INPUT_HEIGHT = 3
const SNAPSHOT_LIMIT = 100

var output_buf = -1
var input_buf = -1
var output_win = 0
var input_win = 0
var main_win = 0
var flush_timer = 0
var rendered: list<dict<any>> = []
var draft = ''
var history: list<string> = []
var history_index = 0
var setup_done = false
var loading_session = false
var session_pinned = false

# ---------------------------------------------------------------------------
# Lifecycle

export def Setup()
  if setup_done
    return
  endif
  setup_done = true
  state.AddListener(OnStateChanged)
  events.AddListener(OnEvent)
enddef

export def IsOpen(): bool
  return output_win > 0 && win_id2win(output_win) > 0
enddef

export def Toggle()
  if IsOpen()
    Close()
  else
    Open()
  endif
enddef

export def Open()
  Setup()
  if IsOpen()
    FocusInput()
    return
  endif

  var cfg = config.Get()
  var height = cfg.panel.height
  if height < 4
    height = 4
  endif
  main_win = win_getid()
  EnsureBuffers()

  execute cfg.panel.position .. ' split'
  execute 'resize ' .. height
  output_win = win_getid()
  execute 'buffer ' .. output_buf
  ApplyOutputWindowOptions()

  execute 'belowright split'
  execute 'resize ' .. INPUT_HEIGHT
  input_win = win_getid()
  execute 'buffer ' .. input_buf
  ApplyInputWindowOptions()

  InstallMappings()
  rendered = []
  if draft !=# ''
    SetInput(draft)
  endif
  Flush()
  FocusInput()
  EnsureSessionAsync()
  events.EmitLocal('panel.opened', {sessionID: state.SessionId()})
enddef

# Build the header chunk shown above the transcript. Keeping it as a regular
# render chunk means Flush() redraws it together with the messages and the
# header updates when the server, session or model changes.
def InfoChunk(): dict<any>
  var status = server.Status()
  var session = state.SessionId()
  var model = catalog.ModelLabel()
  if model ==# ''
    model = state.Model()
  endif
  var agent = catalog.AgentLabel()
  var lines: list<string> = ['# OpenCode']
  if status.connected
    var version = status.version ==# '' ? 'unknown' : status.version
    lines->add('  server: ' .. status.url .. ' (version ' .. version .. ')')
    lines->add('  directory: ' .. status.directory)
  else
    lines->add('  server: not connected')
  endif
  lines->add('  session: ' .. (session ==# '' ? 'none' : session))
  lines->add('  model: ' .. (model ==# '' ? 'unknown' : model))
  lines->add('  agent: ' .. (agent ==# '' ? 'default' : agent))
  lines->add('  commands: :Opencode toggle | :Opencode ask <text> | :Opencode prompt <text>')
  lines->add('  env: vim ' .. v:version .. ' opencode9.vim ' .. get(g:, 'opencode9_version', '?'))
  lines->add('')
  var key = 'info:' .. join([
    status.connected ? status.url : 'offline',
    status.version,
    status.directory,
    session,
    model,
    agent,
  ], '|')
  return {
    key: key,
    kind: 'info',
    lines: lines,
    fold: false,
    props: [{offset: 0, col: 1, length: 1, group: 'Opencode9Muted'}],
  }
enddef

export def Close()
  if !IsOpen()
    return
  endif
  StopFlushTimer()
  draft = InputText()
  if input_win > 0 && win_id2win(input_win) > 0
    win_gotoid(input_win)
    close
  endif
  if output_win > 0 && win_id2win(output_win) > 0
    win_gotoid(output_win)
    close
  endif
  output_win = 0
  input_win = 0
  if main_win > 0 && win_id2win(main_win) > 0
    win_gotoid(main_win)
  endif
  events.EmitLocal('panel.closed', {sessionID: state.SessionId()})
enddef

export def FocusInput()
  if input_win > 0 && win_id2win(input_win) > 0
    win_gotoid(input_win)
    startinsert!
  endif
enddef

export def FocusOutput()
  if output_win > 0 && win_id2win(output_win) > 0
    win_gotoid(output_win)
  endif
enddef

# Focus a pane after opening the panel. target: input, output or panel.
export def OpenTarget(target: string)
  var wanted = tolower(target)
  if wanted ==# ''
    wanted = 'panel'
  endif
  Open()
  if wanted ==# 'output'
    FocusOutput()
  else
    FocusInput()
  endif
enddef

# Close one pane or the whole panel. target: input, output or panel.
export def CloseTarget(target: string)
  var wanted = tolower(target)
  if wanted ==# 'input' || wanted ==# 'output'
    var win = wanted ==# 'input' ? input_win : output_win
    if win > 0 && win_id2win(win) > 0
      win_gotoid(win)
      close
    endif
    if wanted ==# 'input'
      input_win = 0
    else
      output_win = 0
    endif
    return
  endif
  Close()
enddef

def EnsureBuffers()
  output_buf = BufferFor(OUTPUT_NAME, OUTPUT_FILETYPE)
  input_buf = BufferFor(INPUT_NAME, INPUT_FILETYPE)
  ApplyBufferOptions(output_buf, false)
  ApplyBufferOptions(input_buf, true)
enddef

def BufferFor(name: string, filetype: string): number
  var buf = bufnr(name)
  if buf < 0
    buf = bufadd(name)
  endif
  if !bufloaded(buf)
    bufload(buf)
  endif
  setbufvar(buf, '&buftype', 'nofile')
  setbufvar(buf, '&bufhidden', 'hide')
  setbufvar(buf, '&swapfile', false)
  setbufvar(buf, '&undolevels', -1)
  setbufvar(buf, '&buflisted', false)
  setbufvar(buf, '&filetype', filetype)
  return buf
enddef

def ApplyBufferOptions(buf: number, editable: bool)
  setbufvar(buf, '&buftype', 'nofile')
  setbufvar(buf, '&bufhidden', 'hide')
  setbufvar(buf, '&swapfile', false)
  setbufvar(buf, '&modifiable', editable ? v:true : v:false)
  setbufvar(buf, '&readonly', editable ? v:false : v:true)
  setbufvar(buf, '&foldmethod', 'manual')
  setbufvar(buf, '&foldcolumn', 1)
  setbufvar(buf, '&wrap', true)
  setbufvar(buf, '&linebreak', true)
  setbufvar(buf, '&number', false)
  setbufvar(buf, '&relativenumber', false)
enddef

def ApplyOutputWindowOptions()
  setlocal winfixheight
  setlocal nobuflisted
  setlocal nonumber
  setlocal norelativenumber
  setlocal wrap
  setlocal linebreak
  setlocal foldmethod=manual
  setlocal foldcolumn=1
enddef

def ApplyInputWindowOptions()
  setlocal winfixheight
  setlocal nobuflisted
  setlocal nonumber
  setlocal norelativenumber
  setlocal wrap
  setlocal linebreak
  setlocal nospell
enddef

def InstallMappings()
  if output_buf > 0
    execute 'nnoremap <buffer><silent> <CR> <Cmd>call g:Opencode9PanelJump()<CR>'
    execute 'nnoremap <buffer><silent> q <Cmd>call g:Opencode9PanelClose()<CR>'
    execute 'nnoremap <buffer><silent> ]m <Cmd>call g:Opencode9PanelNextMessage()<CR>'
    execute 'nnoremap <buffer><silent> [m <Cmd>call g:Opencode9PanelPrevMessage()<CR>'
    execute 'nnoremap <buffer><silent> ]u <Cmd>call g:Opencode9PanelNextUser()<CR>'
    execute 'nnoremap <buffer><silent> [u <Cmd>call g:Opencode9PanelPrevUser()<CR>'
  endif
  if input_buf > 0
    execute 'inoremap <buffer><silent> <CR> <Cmd>call g:Opencode9PanelSubmit()<CR>'
    execute 'nnoremap <buffer><silent> <CR> <Cmd>call g:Opencode9PanelSubmit()<CR>'
    execute 'inoremap <buffer><silent> <C-p> <Cmd>call g:Opencode9PanelHistoryPrev()<CR>'
    execute 'inoremap <buffer><silent> <C-n> <Cmd>call g:Opencode9PanelHistoryNext()<CR>'
  endif
enddef

# ---------------------------------------------------------------------------
# Input and submission

export def InputText(): string
  if input_buf <= 0
    return draft
  endif
  var lines = getbufline(input_buf, 1, '$')
  var text = join(lines, "\n")
  return substitute(text, '\n\+$', '', '')
enddef

export def SetInput(text: string)
  if input_buf <= 0
    draft = text
    return
  endif
  var lines = split(text, '\n', 1)
  if empty(lines)
    lines = ['']
  endif
  setbufvar(input_buf, '&modifiable', true)
  setbufline(input_buf, 1, lines[0])
  if len(lines) > 1
    appendbufline(input_buf, 1, lines[1 :])
  endif
  var count = len(getbufline(input_buf, 1, '$'))
  if count > len(lines)
    deletebufline(input_buf, len(lines) + 1, '$')
  endif
  if input_win > 0 && win_id2win(input_win) > 0
    win_execute(input_win, 'normal! G')
  endif
enddef

export def ClearInput()
  if input_buf <= 0
    return
  endif
  setbufvar(input_buf, '&modifiable', true)
  setbufline(input_buf, 1, '')
  var count = len(getbufline(input_buf, 1, '$'))
  if count > 1
    deletebufline(input_buf, 2, '$')
  endif
  if input_win > 0 && win_id2win(input_win) > 0
    win_execute(input_win, 'normal! gg')
  endif
enddef

# Send the current input. Called from insert and normal mode mappings.
export def Submit()
  if !IsOpen()
    return
  endif
  var text = InputText()
  if trim(text) ==# ''
    return
  endif
  if empty(history) || history[-1] !=# text
    history->add(text)
  endif
  history_index = len(history)
  var ctx = CaptureMainContext()
  ClearInput()
  prompt.SendWithContext(text, ctx)
  events.EmitLocal('panel.submitted', {text: text})
enddef

def CaptureMainContext(): dict<any>
  if main_win > 0 && win_id2win(main_win) > 0
    win_gotoid(main_win)
    var ctx = context.Capture([0, 0])
    if input_win > 0 && win_id2win(input_win) > 0
      win_gotoid(input_win)
    endif
    return ctx
  endif
  return context.Capture([0, 0])
enddef

export def HistoryPrev()
  if empty(history)
    return
  endif
  history_index = max([0, history_index - 1])
  SetInput(history[history_index])
  if input_win > 0 && win_id2win(input_win) > 0
    win_gotoid(input_win)
    startinsert!
  endif
enddef

export def HistoryNext()
  if empty(history)
    return
  endif
  if history_index < len(history) - 1
    history_index += 1
    SetInput(history[history_index])
  else
    history_index = len(history)
    SetInput('')
  endif
  if input_win > 0 && win_id2win(input_win) > 0
    win_gotoid(input_win)
    startinsert!
  endif
enddef

# ---------------------------------------------------------------------------
# Streaming and rendering

def OnStateChanged()
  MarkDirty()
enddef

export def MarkDirty()
  if !IsOpen()
    return
  endif
  StopFlushTimer()
  var delay = get(config.Get().panel, 'debounce_ms', 60)
  flush_timer = timer_start(delay, function('g:Opencode9PanelFlush'))
enddef

def StopFlushTimer()
  if flush_timer > 0
    timer_stop(flush_timer)
    flush_timer = 0
  endif
enddef

def g:Opencode9PanelFlush(timer: number)
  flush_timer = 0
  Flush()
enddef

# Redraw the transcript, rewriting only the changed suffix when possible.
export def Flush()
  if !IsOpen() || output_buf <= 0
    return
  endif

  var cfg = config.Get().panel
  var max_messages = get(cfg, 'max_messages', 200)
  var chunks = [InfoChunk()] + render.Chunks(max_messages)
  var common = CommonPrefix(chunks)
  if common == len(rendered) && common == len(chunks)
    return
  endif

  var old_count = BufferLineCount(output_buf)
  var at_bottom = ViewAtBottom(old_count)
  win_execute(output_win, 'g:opencode9_panel_saved_view = winsaveview()')

  var start_line = 1
  var i = 0
  while i < common
    start_line += len(rendered[i].lines)
    i += 1
  endwhile

  # The output buffer is readonly/nomodifiable (set by the ftplugin when the
  # window opens). Temporarily allow changes so Flush can rewrite it.
  setbufvar(output_buf, '&modifiable', v:true)
  setbufvar(output_buf, '&readonly', v:false)
  # Clearing all manual folds before a rewrite keeps stale fold regions from
  # surviving into the new content.
  setbufvar(output_buf, '&foldmethod', 'indent')
  setbufvar(output_buf, '&foldmethod', 'manual')

  var new_lines: list<string> = []
  i = common
  while i < len(chunks)
    new_lines += chunks[i].lines
    i += 1
  endwhile
  ReplaceFrom(start_line, new_lines)
  ApplyProps(chunks, common, start_line)
  CreateFolds(chunks, common)
  setbufvar(output_buf, '&modifiable', v:false)
  setbufvar(output_buf, '&readonly', v:true)

  rendered = chunks
  var message_lines = render.MessageLines(chunks)
  setbufvar(output_buf, 'opencode9_message_lines', message_lines)

  if win_id2win(output_win) > 0
    if at_bottom
      win_execute(output_win, 'normal! G')
    else
      win_execute(output_win, 'call winrestview(g:opencode9_panel_saved_view)')
    endif
  endif
enddef

def CommonPrefix(chunks: list<dict<any>>): number
  var common = 0
  while common < len(rendered) && common < len(chunks)
    if rendered[common].key !=# chunks[common].key || rendered[common].lines != chunks[common].lines
      break
    endif
    common += 1
  endwhile
  return common
enddef

def BufferLineCount(buf: number): number
  return len(getbufline(buf, 1, '$'))
enddef

def WindowView(win: number): dict<any>
  var info = getwininfo(win)
  if empty(info)
    return {}
  endif
  var position = getcurpos(win)
  return {
    lnum: position[1],
    col: position[2],
    topline: get(info[0], 'topline', 1),
    leftcol: 0,
    skipcol: 0,
  }
enddef

def ViewAtBottom(line_count: number): bool
  var info = getwininfo(output_win)
  if empty(info)
    return true
  endif
  return get(info[0], 'botline', 0) >= line_count
enddef

def ReplaceFrom(start_line: number, new_lines: list<string>)
  var lines = empty(new_lines) ? [''] : new_lines
  var count = BufferLineCount(output_buf)
  if start_line <= 1
    silent! call setbufline(output_buf, 1, lines[0])
    if len(lines) > 1
      silent! call appendbufline(output_buf, 1, lines[1 :])
    endif
    if count > len(lines)
      silent! call deletebufline(output_buf, len(lines) + 1, '$')
    endif
    return
  endif
  if start_line <= count
    silent! call deletebufline(output_buf, start_line, '$')
  endif
  silent! call appendbufline(output_buf, start_line - 1, lines)
enddef

def EnsurePropTypes()
  var groups = ['Opencode9User', 'Opencode9Tool', 'Opencode9Reasoning', 'Opencode9Error', 'Opencode9Muted']
  for group in groups
    var name = PropName(group)
    if empty(prop_type_get(name, {bufnr: output_buf}))
      try
        prop_type_add(name, {highlight: group, bufnr: output_buf, combine: false})
      catch
        # A type may have been created by an earlier panel instance.
      endtry
    endif
  endfor
enddef

def PropName(group: string): string
  return 'opencode9_' .. tolower(substitute(group, '^Opencode9', '', ''))
enddef

def ApplyProps(chunks: list<dict<any>>, common: number, start_line: number)
  EnsurePropTypes()
  var line = start_line
  var i = common
  while i < len(chunks)
    var chunk = chunks[i]
    for prop in get(chunk, 'props', [])
      var length = get(prop, 'length', 0)
      if length > 0
        try
          prop_add(line + get(prop, 'offset', 0), get(prop, 'col', 1), {
            type: PropName(get(prop, 'group', 'Opencode9Muted')),
            length: length,
            bufnr: output_buf,
          })
        catch
          # Props are decorative; never let them break a redraw.
        endtry
      endif
    endfor
    line += len(chunk.lines)
    i += 1
  endwhile
enddef

def CreateFolds(chunks: list<dict<any>>, common: number)
  var line = 1
  var i = 0
  while i < len(chunks)
    var chunk = chunks[i]
    if i >= common && get(chunk, 'fold', false) && len(chunk.lines) > 1
      # zf{count}j creates a fold from the cursor line down count lines.
      silent! win_execute(output_win, 'normal! ' .. line .. 'zf' .. len(chunk.lines) .. 'j')
    endif
    line += len(chunk.lines)
    i += 1
  endwhile
enddef

# ---------------------------------------------------------------------------
# Session attachment

# Open a specific session in the panel. The session stays pinned so a later
# reconnection or panel reopen does not silently switch back to the most
# recently updated session.
export def OpenSession(session_id: string)
  if session_id ==# ''
    return
  endif
  var conn = server.Current()
  if type(conn) == v:t_none
    util.EchoError('not connected; run :Opencode server connect')
    return
  endif
  session_pinned = true
  Open()
  state.EnsureSession(session_id)
  rendered = []
  LoadSnapshot(conn, session_id)
  Flush()
  events.EmitLocal('session.opened', {sessionID: session_id})
enddef

# Unpin the current session and follow the most recently updated session for
# the current directory again.
export def FollowRecent()
  session_pinned = false
  Open()
  EnsureSessionAsync()
enddef

def EnsureSessionAsync()
  if loading_session || session_pinned
    return
  endif
  var conn = server.Current()
  if type(conn) == v:t_none
    return
  endif
  loading_session = true
  v2.ResolveSession(conn, util.Cwd(),
    (session: any) => {
      loading_session = false
      AttachSession(conn, session)
    },
    (message: string, exit: number, status: number) => {
      loading_session = false
      util.Log('info', 'panel could not resolve a session: ' .. message)
    })
enddef

def AttachSession(conn: any, session: any)
  if session_pinned
    return
  endif
  var id = type(session) == v:t_dict ? get(session, 'id', '') : ''
  if type(id) != v:t_string || id ==# ''
    return
  endif
  var changed = state.EnsureSession(id)
  if changed || empty(state.Messages())
    LoadSnapshot(conn, id)
  else
    MarkDirty()
  endif
enddef

def LoadSnapshot(conn: any, session_id: string)
  v2.LoadMessages(conn, session_id, SNAPSHOT_LIMIT,
    (value: any, status: number) => {
      # Ignore a response that arrives after the user switched or deleted the
      # session; otherwise stale data could resurrect the old transcript.
      if state.SessionId() !=# session_id
        return
      endif
      var items = type(value) == v:t_dict ? get(value, 'data', value) : value
      state.Snapshot(session_id, items)
    },
    (message: string, exit: number, status: number) => {
      util.Log('info', 'panel could not load messages: ' .. message)
    })
enddef

def OnEvent(event: any)
  var event_type = get(event, 'type', '')
  if event_type ==# 'server.connected'
    if IsOpen()
      EnsureSessionAsync()
    endif
    return
  endif
  var catalog_event = event_type ==# 'model.selected' || event_type ==# 'model.cleared' || event_type ==# 'agent.selected' || event_type ==# 'agent.cleared'
  if catalog_event
    MarkDirty()
    return
  endif
  if event_type ==# 'prompt.sent'
    var data = get(event, 'data', {})
    if type(data) == v:t_dict
      var text = get(data, 'text', '')
      var session_id = get(data, 'sessionID', '')
      if type(text) == v:t_string && text !=# ''
        if type(session_id) == v:t_string && session_id !=# '' && session_id !=# state.SessionId()
          state.EnsureSession(session_id)
        endif
        state.AddUser(session_id, text)
      endif
    endif
    return
  endif
  if state.Apply(event)
    MarkDirty()
  endif
enddef

# ---------------------------------------------------------------------------
# Navigation

export def NextMessage()
  JumpMessage(1, false)
enddef

export def PrevMessage()
  JumpMessage(-1, false)
enddef

export def NextUser()
  JumpMessage(1, true)
enddef

export def PrevUser()
  JumpMessage(-1, true)
enddef

def JumpMessage(direction: number, user_only: bool)
  if !IsOpen()
    return
  endif
  FocusOutput()
  var lines: list<dict<any>> = getbufvar(output_buf, 'opencode9_message_lines', [])
  if empty(lines)
    return
  endif
  var current = line('.')
  var target = 0
  if direction > 0
    for item in lines
      if item.line > current && (!user_only || item.kind ==# 'user')
        target = item.line
        break
      endif
    endfor
  else
    var i = len(lines) - 1
    while i >= 0
      var item = lines[i]
      if item.line < current && (!user_only || item.kind ==# 'user')
        target = item.line
        break
      endif
      i -= 1
    endwhile
  endif
  if target > 0
    cursor(target, 1)
  endif
enddef

export def JumpToFile()
  if !IsOpen()
    return
  endif
  FocusOutput()
  var text = getline('.')
  var match = matchlist(text, '\(\S\+\):L\(\d\+\):C\(\d\+\)')
  if empty(match)
    match = matchlist(text, '\(\S\+\):\(\d\+\)')
  endif
  if empty(match)
    util.EchoInfo('no file location under the cursor')
    return
  endif
  var path = fnamemodify(match[1], ':p')
  if !filereadable(path)
    util.EchoError('file not found: ' .. match[1])
    return
  endif
  var lnum = str2nr(match[2])
  var col = len(match) > 3 && match[3] !=# '' ? str2nr(match[3]) : 1
  if main_win > 0 && win_id2win(main_win) > 0
    win_gotoid(main_win)
  endif
  execute 'edit ' .. fnameescape(path)
  cursor(lnum, max([1, col]))
enddef

# Global wrappers for buffer-local mappings. Vim's mapping layer cannot call
# script-local functions directly.
def g:Opencode9PanelSubmit()
  Submit()
enddef

def g:Opencode9PanelClose()
  Close()
enddef

def g:Opencode9PanelJump()
  JumpToFile()
enddef

def g:Opencode9PanelNextMessage()
  NextMessage()
enddef

def g:Opencode9PanelPrevMessage()
  PrevMessage()
enddef

def g:Opencode9PanelNextUser()
  NextUser()
enddef

def g:Opencode9PanelPrevUser()
  PrevUser()
enddef

def g:Opencode9PanelHistoryPrev()
  HistoryPrev()
enddef

def g:Opencode9PanelHistoryNext()
  HistoryNext()
enddef
