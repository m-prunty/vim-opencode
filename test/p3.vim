vim9script

# P3 headless smoke test for the split panel and streaming renderer.

import autoload 'vim_opencode/config.vim' as config
import autoload 'vim_opencode/server.vim' as server
import autoload 'vim_opencode/state.vim' as state
import autoload 'vim_opencode/ui/panel.vim' as panel
import autoload 'vim_opencode/ui/render.vim' as render
import autoload 'vim_opencode/util.vim' as util

var failures: list<string> = []
var result_dir = 'test/results'

def Check(condition: bool, message: string)
  if !condition
    failures->add(message)
  endif
enddef

try
  config.Setup({request_timeout_ms: 3000})

  # State model: events apply to the transcript.
  state.Reset('s1')
  state.Apply({type: 'session.inbox.enqueued', data: {sessionID: 's1', inboxID: 'u1', item: {type: 'user', payload: {text: 'hello there'}}}})
  state.Apply({type: 'session.step.started', data: {sessionID: 's1', assistantMessageID: 'a1', agent: 'build'}})
  state.Apply({type: 'session.text.started', data: {sessionID: 's1', assistantMessageID: 'a1', ordinal: 0}})
  state.Apply({type: 'session.text.delta', data: {sessionID: 's1', assistantMessageID: 'a1', ordinal: 0, delta: 'Hi '}})
  state.Apply({type: 'session.text.delta', data: {sessionID: 's1', assistantMessageID: 'a1', ordinal: 0, delta: 'there'}})
  state.Apply({type: 'session.text.ended', data: {sessionID: 's1', assistantMessageID: 'a1', ordinal: 0, text: 'Hi there'}})

  Check(len(state.Messages()) == 2, 'expected two messages')
  Check(state.Messages()[0].kind ==# 'user', 'first message should be user')
  Check(state.Messages()[1].kind ==# 'assistant', 'second message should be assistant')
  Check(state.Messages()[1].parts[0].text ==# 'Hi there', 'streaming text should accumulate')
  Check(state.Version() > 0, 'version should bump on change')

  # Renderer: chunks and message line markers.
  var chunks = render.Chunks()
  Check(len(chunks) >= 2, 'expected at least two chunks')
  var kinds: list<string> = []
  for chunk in chunks
    if chunk.kind ==# 'user' || chunk.kind ==# 'text'
      kinds->add(chunk.kind)
    endif
  endfor
  Check(index(kinds, 'user') >= 0, 'user chunk present')
  Check(index(kinds, 'text') >= 0, 'text chunk present')

  # Panel open/close.
  panel.Open()
  Check(panel.IsOpen(), 'panel should be open')
  Check(bufnr('vim-opencode://transcript') > 0, 'transcript buffer should exist')
  Check(bufnr('vim-opencode://input') > 0, 'input buffer should exist')

  panel.Flush()
  var lines = getbufline(bufnr('vim-opencode://transcript'), 1, '$')
  Check(index(lines, '> hello there') >= 0, 'user message should render')
  Check(index(lines, 'Hi there') >= 0, 'assistant text should render')

  # Focus/input.
  panel.SetInput('draft message')
  Check(panel.InputText() ==# 'draft message', 'input draft should be settable')
  panel.ClearInput()
  Check(panel.InputText() ==# '', 'input should clear')

  # Streaming update.
  state.Apply({type: 'session.text.delta', data: {sessionID: 's1', assistantMessageID: 'a1', ordinal: 0, delta: ' more'}})
  panel.Flush()
  lines = getbufline(bufnr('vim-opencode://transcript'), 1, '$')
  Check(index(lines, 'Hi there more') >= 0, 'streamed delta should appear')

  # Navigation markers.
  var msg_lines = getbufvar(bufnr('vim-opencode://transcript'), 'vim_opencode_message_lines', [])
  Check(!empty(msg_lines), 'message line markers should exist')

  panel.Close()
  Check(!panel.IsOpen(), 'panel should be closed')

  # Toggle reopens.
  panel.Toggle()
  Check(panel.IsOpen(), 'toggle should reopen panel')
  panel.Close()

  # Close target variants.
  panel.Open()
  panel.CloseTarget('input')
  Check(panel.IsOpen(), 'panel should still be open after closing input')
  panel.CloseTarget('panel')
  Check(!panel.IsOpen(), 'close panel should close everything')

catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

server.Shutdown()

if isdirectory(result_dir) == 0
  mkdir(result_dir, 'p')
endif

if empty(failures)
  writefile(['P3 smoke test passed'], result_dir .. '/p3.txt')
  qa!
else
  writefile(failures, result_dir .. '/p3.txt')
  execute 'cquit 1'
endif
