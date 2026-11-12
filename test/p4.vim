vim9script

# P4 headless smoke test for session listing and lifecycle commands.

import autoload 'opencode9/commands.vim' as commands
import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/discovery.vim' as discovery
import autoload 'opencode9/protocol/v2.vim' as v2
import autoload 'opencode9/server.vim' as server
import autoload 'opencode9/sessions.vim' as sessions
import autoload 'opencode9/state.vim' as state
import autoload 'opencode9/ui/panel.vim' as panel
import autoload 'opencode9/util.vim' as util

const PORT = '18771'
const BASE = 'http://127.0.0.1:' .. PORT

var failures: list<string> = []
var script_dir = fnamemodify(expand('<sfile>'), ':p:h')
var result_dir = 'test/results'
var connected: any = v:null
var discovery_error = ''
var listed: any = v:null
var list_error = ''
var fixture_job: any = v:null

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

def ListOk(value: any)
  listed = value
enddef

def ListErr(message: string, exit: number, status: number)
  list_error = message
enddef

def WaitFor(label: string, Predicate: func)
  var attempts = 0
  while attempts < 100
    try
      if Predicate()
        return
      endif
    catch
      failures->add(label .. ': ' .. util.ExceptionText())
      return
    endtry
    sleep 30m
    attempts += 1
  endwhile
  failures->add(label .. ': timed out')
enddef

try
  config.Setup({server_url: BASE, request_timeout_ms: 3000})

  fixture_job = job_start(['python3', script_dir .. '/fixtures/server.py', PORT])
  sleep 400m
  discovery.Connect({on_success: DiscOk, on_error: DiscErr})
  WaitFor('discovery', () => type(connected) != v:t_none)
  Check(discovery_error ==# '', 'discovery failed: ' .. discovery_error)

  # Session listing and token resolution.
  v2.ListSessions(connected, '/tmp', ListOk, ListErr)
  WaitFor('session list', () => type(listed) != v:t_none)
  Check(list_error ==# '', 'session listing failed: ' .. list_error)
  Check(type(listed) == v:t_list && len(listed) >= 1, 'session list should not be empty')
  Check(type(listed) == v:t_list && get(listed[0], 'id', '') ==# 's1', 'first session should be s1')

  sessions.Refresh()
  WaitFor('session cache', () => !empty(sessions.Cached()))
  Check(sessions.ResolveToken('1').id ==# 's1', 'numeric token did not resolve')
  Check(sessions.ResolveToken('s').id ==# 's1', 'id prefix did not resolve')
  Check(sessions.Format(sessions.Cached()[0], 1) =~# '\[1\].*s1', 'session formatting is wrong')

  # Open the fixture session in the panel and render its transcript.
  sessions.Open('s1')
  WaitFor('session open', () => panel.IsOpen() && state.SessionId() ==# 's1')
  Check(panel.IsOpen(), 'panel should be open after session open')
  WaitFor('snapshot', () => !empty(state.Messages()))
  panel.Flush()
  var lines = getbufline(bufnr('opencode9://transcript'), 1, '$')
  Check(len(lines) > 0 && lines[0] ==# '# OpenCode', 'info header should be the first line')
  Check(index(lines, '  session: s1') >= 0, 'info header should show the session id')
  Check(index(lines, 'fixture question') < 0, 'snapshot text should be prefixed')
  Check(join(lines, "\n") =~# 'fixture question', 'snapshot message should render')

  # The header follows model changes without losing the transcript.
  state.Apply({type: 'session.step.started', data: {sessionID: 's1', assistantMessageID: 'a9', model: 'anthropic/claude'}})
  panel.Flush()
  lines = getbufline(bufnr('opencode9://transcript'), 1, '$')
  Check(index(lines, '  model: anthropic/claude') >= 0, 'info header should show the model')
  Check(join(lines, "\n") =~# 'fixture question', 'transcript should survive header updates')

  # Create a new session and open it.
  sessions.New('Code review')
  WaitFor('session create', () => state.SessionId() !=# 's1' && state.SessionId() !=# '')
  var created = state.SessionId()
  Check(created !=# 's1', 'new session should be opened')
  sessions.Refresh()
  WaitFor('session cache after create', () => !empty(sessions.ResolveToken(created)))
  Check(sessions.ResolveToken(created).title ==# 'Code review', 'new session should keep its title')

  # Rename the new session.
  sessions.Rename(created, 'Renamed session')
  WaitFor('session rename', () => !empty(sessions.ResolveToken(created)) && sessions.ResolveToken(created).title ==# 'Renamed session')
  Check(sessions.ResolveToken(created).title ==# 'Renamed session', 'rename should update the cache')

  # Fork the renamed session and open the fork.
  sessions.Fork(created)
  WaitFor('session fork', () => state.SessionId() !=# created && state.SessionId() !=# '')
  var forked = state.SessionId()
  Check(forked !=# created, 'fork should open the new session')
  WaitFor('session fork cache', () => !empty(sessions.ResolveToken(forked)))
  Check(get(sessions.ResolveToken(forked), 'parentID', '') ==# created, 'fork should record its parent')

  # Delete the fork without prompting.
  sessions.Delete(forked, true)
  WaitFor('session delete', () => empty(sessions.ResolveToken(forked)))
  Check(empty(sessions.ResolveToken(forked)), 'deleted session should leave the cache')
  Check(state.SessionId() ==# '', 'deleting the current session should clear the state')

  # Command table exposes the implemented session command.
  var table = commands.Table()
  Check(table.session.implemented, 'session command should be implemented')
  commands.Dispatch('session current', [0, 0], false)

  panel.Close()
catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

server.Shutdown()
if type(fixture_job) != v:t_none && job_status(fixture_job) ==# 'run'
  job_stop(fixture_job, 'term')
endif

if isdirectory(result_dir) == 0
  mkdir(result_dir, 'p')
endif

if empty(failures)
  writefile(['P4 smoke test passed'], result_dir .. '/p4.txt')
  qa!
else
  writefile(failures, result_dir .. '/p4.txt')
  execute 'cquit 1'
endif
