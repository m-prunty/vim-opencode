vim9script

# P10 hardening tests: assert_equal-style checks, message capping,
# transport error handling, and config validation.

import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/context.vim' as context
import autoload 'opencode9/ui/render.vim' as render
import autoload 'opencode9/state.vim' as state
import autoload 'opencode9/transport.vim' as transport
import autoload 'opencode9/util.vim' as util

var failures: list<string> = []
var result_dir = 'test/results'

def Check(condition: bool, message: string)
  if !condition
    failures->add(message)
  endif
enddef

def AssertEqual(expected: any, actual: any, message: string)
  if expected !=# actual
    failures->add(message .. ' (expected=' .. string(expected) .. ' actual=' .. string(actual) .. ')')
  endif
enddef

try
  config.Setup({request_timeout_ms: 3000, panel: {max_messages: 2}})
  var path = '/tmp/opencode/p10_context.txt'
  writefile(['line one', 'line two', 'line three'], path)
  execute 'edit ' .. fnameescape(path)

  # --- Context: Rich() returns expected keys ---
  var ctx = context.Capture([1, 2])
  var rich = context.Rich(ctx)
  Check(has_key(rich, 'file'), 'Rich context should include file key')
  Check(has_key(rich, 'cursor'), 'Rich context should include cursor key')
  Check(has_key(rich, 'diff'), 'Rich context should include diff key')

  # --- Context: Changed() detects changes ---
  var first = context.Changed('p10', ctx)
  Check(has_key(first, 'file'), 'First change should report file')
  var second = context.Changed('p10', ctx)
  Check(empty(second), 'Unchanged context should return empty dict')

  # --- Render: Chunks() with max_messages cap ---
  state.Reset('p10-cap')
  state.Apply({type: 'session.inbox.enqueued', data: {sessionID: 'p10-cap', inboxID: 'u1', item: {type: 'user', payload: {text: 'msg1'}}}})
  state.Apply({type: 'session.inbox.enqueued', data: {sessionID: 'p10-cap', inboxID: 'u2', item: {type: 'user', payload: {text: 'msg2'}}}})
  state.Apply({type: 'session.inbox.enqueued', data: {sessionID: 'p10-cap', inboxID: 'u3', item: {type: 'user', payload: {text: 'msg3'}}}})
  Check(len(state.Messages()) == 3, 'three messages should exist')

  var capped = render.Chunks(2)
  Check(len(capped) <= 5, 'capped chunks should be limited (got ' .. string(len(capped)) .. ')')
  var capped_text = join(render.Lines(capped), "\n")
  Check(capped_text =~# 'older messages hidden', 'capped render should show truncation notice')

  var uncapped = render.Chunks(0)
  Check(len(uncapped) >= len(capped), 'uncapped render should have at least as many chunks as capped')

  # --- Transport: FormatError produces useful message ---
  var err = transport.FormatError({method: 'GET', url: 'http://example.com/api', err: 'connection refused'}, -1, 0, '')
  Check(err =~# 'GET http://example.com/api failed', 'FormatError should include method and URL')
  Check(err =~# 'curl exit: -1', 'FormatError should include curl exit code')
  Check(err =~# 'connection refused', 'FormatError should include stderr')

  # --- Transport: Truncate ---
  var long = repeat('x', 5000)
  var truncated = transport.Truncate(long, 100)
  Check(strlen(truncated) == 103, 'Truncate should produce limit + 3 chars')
  Check(truncated =~# '\.\.\.$', 'Truncate should end with ellipsis')

  # --- Transport: CloseAll cleans up ---
  var count_before = transport.Count()
  transport.CloseAll()
  var count_after = transport.Count()
  Check(count_after == 0, 'CloseAll should clear all tracked jobs')

  # --- Util: StateDir ---
  var state_dir = util.StateDir()
  Check(stridx(state_dir, 'opencode9') >= 0, 'StateDir should contain opencode9')

  # --- Config: protocol validation ---
  try
    config.Setup({protocol: 'v3'})
    Check(false, 'protocol=v3 should fail validation')
  catch
    Check(true, 'protocol=v3 should throw validation error')
  endtry

catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

if isdirectory(result_dir) == 0
  mkdir(result_dir, 'p')
endif

if empty(failures)
  writefile(['P10 smoke test passed'], result_dir .. '/p10.txt')
  qa!
else
  writefile(failures, result_dir .. '/p10.txt')
  execute 'cquit 1'
endif
