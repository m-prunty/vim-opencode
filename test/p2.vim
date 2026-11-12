vim9script

# P2 headless smoke test for context, sessions and prompt submission.

import autoload 'vim_opencode/config.vim' as config
import autoload 'vim_opencode/context.vim' as context
import autoload 'vim_opencode/discovery.vim' as discovery
import autoload 'vim_opencode/prompt.vim' as prompt
import autoload 'vim_opencode/protocol/v2.vim' as v2
import autoload 'vim_opencode/server.vim' as server
import autoload 'vim_opencode/transport.vim' as transport
import autoload 'vim_opencode/util.vim' as util

const PORT = '18769'
const BASE = 'http://127.0.0.1:' .. PORT

var failures: list<string> = []
var script_dir = fnamemodify(expand('<sfile>'), ':p:h')
var result_dir = script_dir .. '/results'

var connected: any = v:null
var discovery_error = ''
var session: any = v:null
var session_error = ''
var sent = false
var prompts: any = v:null

def Check(condition: bool, message: string)
  if !condition
    failures->add(message)
  endif
enddef

def DiscOk(conn: any, info: any)
  connected = conn
enddef

def DiscErr(message: string)
  discovery_error = message
enddef

def SessionOk(value: any)
  session = value
enddef

def SessionErr(message: string, exit: number, status: number)
  session_error = message
enddef

def PromptSent()
  sent = true
enddef

def PromptsOk(value: any, status: number)
  prompts = value
enddef

def RequestErr(message: string, exit: number, status: number)
  failures->add(message)
enddef

var fixture_job: any = v:null

try
  # Ensure temp dir exists.
  if !isdirectory('/tmp/opencode')
    call mkdir('/tmp/opencode', 'p')
  endif
  var sample = '/tmp/opencode/p2_sample.vim'
  writefile(['line one', 'line two', 'line three'], sample)
  execute 'edit ' .. fnameescape(sample)
  config.Setup({server_url: BASE, request_timeout_ms: 3000})

  # Context capture and rendering.
  var ctx = context.Capture([1, 2])
  Check(ctx.range.kind ==# 'line', 'capture did not create a line range')
  var rendered = context.Render('@this and @buffer and @buffers', ctx)
  Check(stridx(rendered, sample .. ':L1-L2') >= 0, '@this did not render the range')
  Check(stridx(rendered, sample) >= 0, '@buffer did not render the path')
  Check(stridx(rendered, '@') < 0, 'a placeholder was left unreplaced')

  # Quickfix-backed diagnostics.
  setqflist([{bufnr: bufnr('%'), lnum: 2, col: 1, text: 'bad thing', type: 'E'}])
  var diagnostics = context.Render('@quickfix @diagnostics', ctx)
  Check(stridx(diagnostics, 'bad thing') >= 0, 'diagnostics did not include the quickfix text')
  Check(stridx(diagnostics, 'diagnostic(s)') >= 0, 'diagnostics summary is missing')
  setqflist([])

  # Discovery and session resolution.
  fixture_job = job_start(['python3', script_dir .. '/fixtures/server.py', PORT])
  sleep 400m
  discovery.Connect({on_success: DiscOk, on_error: DiscErr})
  sleep 1
  Check(discovery_error ==# '', 'discovery failed')
  Check(type(connected) != v:t_none, 'discovery did not connect')

  v2.ResolveSession(connected, '/tmp', SessionOk, SessionErr)
  sleep 1
  Check(session_error ==# '', 'session resolution failed')
  Check(type(session) == v:t_dict && get(session, 'id', '') ==# 's1', 'session resolution returned the wrong session')

  # Prompt submission and event emission.
  augroup TP2
    autocmd!
    autocmd User OpencodeEvent:prompt.sent PromptSent()
  augroup END
  prompt.Send('@this explain', [1, 2])
  sleep 2
  Check(sent, 'prompt.sent event was not emitted')

  transport.Request({
    url: BASE .. '/api/prompts',
    method: 'GET',
    timeout_ms: 3000,
    on_success: PromptsOk,
    on_error: RequestErr,
  })
  sleep 1
  Check(type(prompts) == v:t_dict && len(get(prompts, 'data', [])) == 1, 'fixture did not receive the prompt')
  if type(prompts) == v:t_dict && len(get(prompts, 'data', [])) > 0
    var text = get(get(prompts, 'data', [])[0], 'text', '')
    Check(stridx(text, sample .. ':L1-L2') >= 0, 'prompt text did not expand @this')
  endif

  # Operator setup.
  Check(prompt.OperatorExpr('@this') ==# 'g@', 'operator expression is wrong')
  Check(&operatorfunc ==# 'g:VimOpencodeOperator', 'operatorfunc was not set')
catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

server.Shutdown()
transport.CloseAll()
if type(fixture_job) != v:t_none && job_status(fixture_job) ==# 'run'
  job_stop(fixture_job, 'term')
endif

if isdirectory(result_dir) == 0
  mkdir(result_dir, 'p')
endif

if empty(failures)
  writefile(['P2 smoke test passed'], result_dir .. '/p2.txt')
  qa!
else
  writefile(failures, result_dir .. '/p2.txt')
  execute 'cquit 1'
endif
