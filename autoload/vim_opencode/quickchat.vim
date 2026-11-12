vim9script

# Small inline-edit workflow. It deliberately replaces whole lines only and
# keeps Vim's native undo as the recovery mechanism.

import autoload 'vim_opencode/catalog.vim' as catalog
import autoload 'vim_opencode/context.vim' as context
import autoload 'vim_opencode/discovery.vim' as discovery
import autoload 'vim_opencode/events.vim' as events
import autoload 'vim_opencode/protocol/active.vim' as active
import autoload 'vim_opencode/server.vim' as server
import autoload 'vim_opencode/util.vim' as util

var qc_state: dict<any> = {}
var installed = false

export def Setup()
  if installed
    return
  endif
  installed = true
  events.AddListener(OnEvent)
enddef

export def Active(): bool
  return !empty(qc_state)
enddef

export def Start(instruction: string, line_range: list<number>)
  if Active()
    util.EchoError('a quick chat edit is already running')
    return
  endif
  if trim(instruction) ==# ''
    util.EchoError('quick chat requires an instruction')
    return
  endif
  var ctx = context.Capture(line_range)
  if !filereadable(bufname(ctx.buf))
    util.EchoError('quick chat requires a writable file buffer')
    return
  endif
  if type(ctx.range) == v:t_none
    var line = ctx.cursor[1]
    ctx.range = {from: [line, 1], to: [line, LineLength(ctx.buf, line)], kind: 'line'}
  endif
  var from = ctx.range.from[0]
  var to = ctx.range.to[0]
  if from <= 0 || to < from
    util.EchoError('quick chat could not determine a line range')
    return
  endif
  qc_state = {ctx: ctx, from: from, to: to, original: getbufline(ctx.buf, from, to), instruction: instruction, sessionID: '', cancelled: false}
  context.Highlight(ctx)
  var conn = server.Current()
  if type(conn) != v:t_none
    Create(conn)
  else
    discovery.Connect({on_success: (current: any, info: any) => Create(current), on_error: (message: string) => Fail(message)})
  endif
  util.EchoInfo('quick chat: preparing an inline edit')
enddef

export def Cancel()
  if empty(qc_state)
    return
  endif
  var item = qc_state
  qc_state = {}
  context.Resume(item.ctx)
  var conn = server.Current()
  if type(conn) != v:t_none && item.sessionID !=# ''
    active.DeleteSession(conn, item.sessionID, Noop, Noop)
  endif
  events.EmitLocal('quickchat.cancelled', {})
  util.EchoInfo('quick chat cancelled; buffer unchanged')
enddef

def Create(conn: any)
  if empty(qc_state)
    return
  endif
  active.CreateSession(conn, {title: 'vim-opencode quick chat'},
    (value: any, status: number) => {
      var id = active.SessionId(value)
      if id ==# ''
        Fail('temporary session did not return an id')
        return
      endif
      qc_state.sessionID = id
      var ctx = qc_state.ctx
      var source = join(qc_state.original, "\n")
      var prompt = 'Return only the complete replacement text for this line range. Do not explain.\n\nInstruction: ' .. qc_state.instruction .. '\n\nText:\n' .. source
      var rendered = context.Render(prompt, ctx)
      var opts = catalog.PromptOptions()
      active.Prompt(conn, id, rendered, Noop, (message: string, exit: number, code: number) => Fail(message), opts)
      events.EmitLocal('quickchat.started', {sessionID: id, from: qc_state.from, to: qc_state.to})
    },
    (message: string, exit: number, status: number) => Fail(message))
enddef

def OnEvent(event: any)
  if empty(qc_state) || get(event, 'type', '') !=# 'session.text.ended'
    return
  endif
  var data = get(event, 'data', {})
  if type(data) != v:t_dict || get(data, 'sessionID', '') !=# qc_state.sessionID
    return
  endif
  var text = get(data, 'text', '')
  if type(text) != v:t_string || text ==# ''
    return
  endif
  Apply(text)
enddef

def Apply(text: string)
  if empty(qc_state) || qc_state.cancelled
    return
  endif
  var item = qc_state
  var replacement = split(substitute(text, '^\s*\|\s*$', '', 'g'), '\n', 1)
  var buf = item.ctx.buf
  if !bufloaded(buf) || len(replacement) == 0
    Fail('quick chat returned no replacement text')
    return
  endif
  setbufvar(buf, '&modifiable', true)
  deletebufline(buf, item.from, item.to)
  appendbufline(buf, item.from - 1, replacement)
  context.Clear(item.ctx)
  qc_state = {}
  var conn = server.Current()
  if type(conn) != v:t_none && item.sessionID !=# ''
    active.DeleteSession(conn, item.sessionID, Noop, Noop)
  endif
  events.EmitLocal('quickchat.applied', {from: item.from, to: item.to})
  util.EchoInfo('quick chat edit applied; use u to undo')
enddef

def Fail(message: string)
  if empty(qc_state)
    return
  endif
  var item = qc_state
  qc_state = {}
  context.Resume(item.ctx)
  util.EchoError(message)
  events.EmitLocal('quickchat.failed', {message: message})
enddef

def LineLength(buf: number, line: number): number
  return max([1, strlen(getbufline(buf, line)[0])])
enddef

def Noop(value: any, status: number)
enddef
