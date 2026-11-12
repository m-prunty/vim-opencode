vim9script

# Context-aware prompt, ask and operator workflows.

import autoload 'opencode9/context.vim' as context
import autoload 'opencode9/discovery.vim' as discovery
import autoload 'opencode9/events.vim' as events
import autoload 'opencode9/protocol/v2.vim' as v2
import autoload 'opencode9/server.vim' as server
import autoload 'opencode9/util.vim' as util

# Send a prompt using the range from the :Opencode command.
export def Send(text: string, line_range: list<number>)
  SendWithContext(text, context.Capture(line_range))
enddef

export def SendWithContext(text: string, ctx: dict<any>)
  if text =~# '\.\.\.$'
    AskWithContext(strpart(text, 0, strlen(text) - 3), ctx)
    return
  endif
  if trim(text) ==# ''
    util.EchoError('prompt is empty')
    context.Resume(ctx)
    return
  endif

  context.Highlight(ctx)
  EnsureConnection(
    (conn: any) => Continue(conn, text, ctx),
    (message: string) => Fail(ctx, message))
enddef

# Open the input prompt with an optional initial value and command range.
export def AskWithRange(initial: string, line_range: list<number>)
  AskWithContext(initial, context.Capture(line_range))
enddef

export def AskWithContext(initial: string, ctx: dict<any>)
  context.Highlight(ctx)
  var answer = input('OpenCode: ', initial, 'customlist,g:Opencode9AskComplete')
  if trim(answer) ==# ''
    context.Resume(ctx)
    return
  endif
  SendWithContext(answer, ctx)
enddef

# Set operatorfunc and return the g@ motion for an <expr> mapping.
export def OperatorExpr(prompt_text: string = '@this'): string
  g:opencode9_operator_prompt = prompt_text
  &operatorfunc = 'g:Opencode9Operator'
  return 'g@'
enddef

# Implement :Opencode operator by entering operator-pending mode.
export def OperatorCommand(prompt_text: string)
  OperatorExpr(prompt_text)
  normal! g@
enddef

def g:Opencode9Operator(operator_type: string)
  SendWithContext(get(g:, 'opencode9_operator_prompt', '@this'), context.CaptureOperator(operator_type))
enddef

# Completion for input() during ask.
def g:Opencode9AskComplete(arglead: string, cmdline: string, cursorpos: number): list<string>
  var candidates = ['@this ', '@buffer ', '@buffers ', '@visible ', '@quickfix ', '@marks ', '@diagnostics ']
  var matches: list<string> = []
  for candidate in candidates
    if stridx(candidate, arglead) == 0
      matches->add(candidate)
    endif
  endfor
  return matches
enddef

def EnsureConnection(on_ready: any, on_error: any)
  var conn = server.Current()
  if type(conn) != v:t_none
    Invoke(on_ready, [conn])
    return
  endif
  discovery.Connect({
    on_success: (current: any, info: any) => Invoke(on_ready, [current]),
    on_error: on_error,
  })
enddef

def Continue(conn: any, text: string, ctx: dict<any>)
  v2.ResolveSession(conn, ctx.cwd,
    (session: any) => Submit(conn, session, text, ctx),
    (message: string, exit: number, status: number) => Fail(ctx, message))
enddef

def Submit(conn: any, session: any, text: string, ctx: dict<any>)
  var session_id = type(session) == v:t_dict ? get(session, 'id', '') : ''
  if type(session_id) != v:t_string || session_id ==# ''
    Fail(ctx, 'resolved session has no id')
    return
  endif

  var rendered = context.Render(text, ctx)
  v2.Prompt(conn, session_id, rendered,
    (result: any, status: number) => Succeeded(ctx, session_id, rendered),
    (message: string, exit: number, status: number) => Fail(ctx, message))
enddef

def Succeeded(ctx: dict<any>, session_id: string, text: string)
  context.Clear(ctx)
  events.EmitLocal('prompt.sent', {sessionID: session_id, text: text})
  echomsg 'opencode9: prompt sent to session ' .. session_id
enddef

def Fail(ctx: dict<any>, message: string)
  context.Resume(ctx)
  events.EmitLocal('prompt.failed', {message: message})
  util.EchoError(message)
enddef

def Invoke(callback: any, args: list<any>)
  if type(callback) == v:t_func
    call(callback, args)
  elseif type(callback) == v:t_string && callback !=# ''
    call(callback, args)
  endif
enddef
