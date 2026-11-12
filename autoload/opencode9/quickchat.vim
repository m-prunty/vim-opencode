vim9script

# Small inline-edit workflow. It deliberately replaces whole lines only and
# keeps Vim's native undo as the recovery mechanism.

import autoload 'opencode9/catalog.vim' as catalog
import autoload 'opencode9/context.vim' as context
import autoload 'opencode9/discovery.vim' as discovery
import autoload 'opencode9/events.vim' as events
import autoload 'opencode9/protocol/v2.vim' as v2
import autoload 'opencode9/server.vim' as server
import autoload 'opencode9/util.vim' as util

var active: dict<any> = {}
var installed = false

export def Setup()
  if installed
    return
  endif
  installed = true
  events.AddListener(OnEvent)
enddef

export def Active(): bool
  return !empty(active)
enddef

export def Start(instruction: string, line_range: list<number>)
  if Active()
    util.EchoError('a quick chat edit is already running')
    return
  endif
  var ctx = context.Capture(line_range)
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
  active = {ctx: ctx, from: from, to: to, original: getbufline(ctx.buf, from, to), instruction: instruction, sessionID: '', cancelled: false}
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
  if empty(active)
    return
  endif
  var item = active
  active = {}
  context.Resume(item.ctx)
  var conn = server.Current()
  if type(conn) != v:t_none && item.sessionID !=# ''
    v2.DeleteSession(conn, item.sessionID, Noop, Noop)
  endif
  events.EmitLocal('quickchat.cancelled', {})
  util.EchoInfo('quick chat cancelled; buffer unchanged')
enddef

def Create(conn: any)
  if empty(active)
    return
  endif
  v2.CreateSession(conn, {title: 'opencode9 quick chat'},
    (value: any, status: number) => {
      var id = v2.SessionId(value)
      if id ==# ''
        Fail('temporary session did not return an id')
        return
      endif
      active.sessionID = id
      var ctx = active.ctx
      var source = join(active.original, "\n")
      var prompt = 'Return only the complete replacement text for this line range. Do not explain.\n\nInstruction: ' .. active.instruction .. '\n\nText:\n' .. source
      v2.Prompt(conn, id, context.Render(prompt, ctx), (result: any, code: number) => {}, (message: string, exit: number, status: number) => Fail(message), catalog.PromptOptions())
      events.EmitLocal('quickchat.started', {sessionID: id, from: active.from, to: active.to})
    },
    (message: string, exit: number, status: number) => Fail(message))
enddef

def OnEvent(event: any)
  if empty(active) || get(event, 'type', '') !=# 'session.text.ended'
    return
  endif
  var data = get(event, 'data', {})
  if type(data) != v:t_dict || get(data, 'sessionID', '') !=# active.sessionID
    return
  endif
  var text = get(data, 'text', '')
  if type(text) != v:t_string || text ==# ''
    return
  endif
  Apply(text)
enddef

def Apply(text: string)
  if empty(active) || active.cancelled
    return
  endif
  var item = active
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
  active = {}
  var conn = server.Current()
  if type(conn) != v:t_none && item.sessionID !=# ''
    v2.DeleteSession(conn, item.sessionID, Noop, Noop)
  endif
  events.EmitLocal('quickchat.applied', {from: item.from, to: item.to})
  util.EchoInfo('quick chat edit applied; use u to undo')
enddef

def Fail(message: string)
  if empty(active)
    return
  endif
  var item = active
  active = {}
  context.Resume(item.ctx)
  util.EchoError(message)
  events.EmitLocal('quickchat.failed', {message: message})
enddef

def LineLength(buf: number, line: number): number
  return max([1, strlen(getbufline(buf, line)[0])])
enddef

def Noop(value: any, status: number)
enddef
