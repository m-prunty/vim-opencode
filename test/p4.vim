vim9script

# P4 headless smoke test for session listing and lifecycle commands.

import autoload 'vim_opencode/catalog.vim' as catalog
import autoload 'vim_opencode/commands.vim' as commands
import autoload 'vim_opencode/config.vim' as config
import autoload 'vim_opencode/discovery.vim' as discovery
import autoload 'vim_opencode/prompt.vim' as prompt
import autoload 'vim_opencode/protocol/v2.vim' as v2
import autoload 'vim_opencode/server.vim' as server
import autoload 'vim_opencode/sessions.vim' as sessions
import autoload 'vim_opencode/state.vim' as state
import autoload 'vim_opencode/transport.vim' as transport
import autoload 'vim_opencode/ui/panel.vim' as panel
import autoload 'vim_opencode/util.vim' as util

const PORT = '18771'
const BASE = 'http://127.0.0.1:' .. PORT

var failures: list<string> = []
var script_dir = fnamemodify(expand('<sfile>'), ':p:h')
var result_dir = 'test/results'
var connected: any = v:null
var discovery_error = ''
var listed: any = v:null
var list_error = ''
var runs: any = v:null
var runs_error = ''
var prompts: any = v:null
var prompts_error = ''
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

def RunsOk(value: any, status: number)
  runs = value
enddef

def RunsErr(message: string, exit: number, status: number)
  runs_error = message
enddef

def PromptsOk(value: any, status: number)
  prompts = value
enddef

def PromptsErr(message: string, exit: number, status: number)
  prompts_error = message
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
  setenv('XDG_STATE_HOME', '/tmp/opencode/p4-state')
  var prefs = catalog.PreferencesFile()
  if filereadable(prefs)
    delete(prefs)
  endif
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
  var lines = getbufline(bufnr('vim-opencode://transcript'), 1, '$')
  Check(len(lines) > 0 && lines[0] ==# '# OpenCode', 'info header should be the first line')
  Check(index(lines, '  session: s1') >= 0, 'info header should show the session id')
  Check(index(lines, 'fixture question') < 0, 'snapshot text should be prefixed')
  Check(join(lines, "\n") =~# 'fixture question', 'snapshot message should render')

  # The header follows model changes without losing the transcript.
  state.Apply({type: 'session.step.started', data: {sessionID: 's1', assistantMessageID: 'a9', model: 'anthropic/claude'}})
  panel.Flush()
  lines = getbufline(bufnr('vim-opencode://transcript'), 1, '$')
  Check(index(lines, '  model: anthropic/claude') >= 0, 'info header should show the model')
  Check(join(lines, "\n") =~# 'fixture question', 'transcript should survive header updates')

  # Model, agent and command catalogs.
  catalog.RefreshModels()
  WaitFor('models', () => !empty(catalog.Models()))
  Check(catalog.Models()[0].key ==# 'anthropic/claude-3', 'first model key is wrong')
  Check(catalog.FindModel('2').key ==# 'openai/gpt-4o', 'numeric model token did not resolve')
  Check(catalog.SelectModel('anthropic/claude-3'), 'model selection failed')
  Check(catalog.ModelLabel() ==# 'anthropic/claude-3', 'model label is wrong')
  Check(filereadable(prefs), 'preferences file should be written')
  var prefs_data = util.JsonDecode(join(readfile(prefs), "\n"))
  Check(get(get(prefs_data, 'model', {}), 'providerID', '') ==# 'anthropic', 'preferences should store the model provider')

  catalog.RefreshAgents()
  WaitFor('agents', () => !empty(catalog.Agents()))
  Check(catalog.SelectAgent('build'), 'agent selection failed')
  Check(catalog.AgentLabel() ==# 'build', 'agent label is wrong')
  prefs_data = util.JsonDecode(join(readfile(prefs), "\n"))
  Check(get(prefs_data, 'agent', '') ==# 'build', 'preferences should store the agent')

  catalog.RefreshCommands()
  WaitFor('commands', () => !empty(catalog.Commands()))
  var command_names: list<string> = []
  for entry in catalog.Commands()
    command_names->add(entry.name)
  endfor
  Check(index(command_names, 'review') >= 0, 'command catalog should contain review')
  Check(index(catalog.Complete('/re'), '/review') >= 0, 'command completion should offer /review')
  Check(index(catalog.Complete('@th'), '@this') >= 0, 'completion should offer context placeholders')

  panel.Flush()
  lines = getbufline(bufnr('vim-opencode://transcript'), 1, '$')
  Check(index(lines, '  model: anthropic/claude-3') >= 0, 'info header should show the selected model')
  Check(index(lines, '  agent: build') >= 0, 'info header should show the selected agent')

  # :Opencode open renders the complete environment header, including the
  # active session, model, agent and Vim/plugin versions.
  panel.Close()
  commands.Dispatch('open', [0, 0], false)
  Check(panel.IsOpen(), ':Opencode open should reopen the panel')
  panel.Flush()
  lines = getbufline(bufnr('vim-opencode://transcript'), 1, '$')
  Check(index(lines, '  server: ' .. BASE .. ' (version 2.0.0)') >= 0, 'open header should show the server and version')
  Check(index(lines, '  directory: ' .. util.Cwd()) >= 0, 'open header should show the directory')
  Check(join(lines, "\n") =~# '  env: vim ', 'open header should show environment versions: ' .. join(lines, ' | '))
  Check(index(lines, '  session: s1') >= 0, 'open header should show the session')
  Check(index(lines, '  model: anthropic/claude-3') >= 0, 'open header should show the model')
  Check(index(lines, '  agent: build') >= 0, 'open header should show the agent')

  # Server command execution uses the current session and selections.
  catalog.RunCommand('review', 'src')
  sleep 300m
  transport.Request({
    url: BASE .. '/api/command_runs',
    method: 'GET',
    timeout_ms: 3000,
    on_success: RunsOk,
    on_error: RunsErr,
  })
  WaitFor('command runs', () => type(runs) != v:t_none)
  Check(runs_error ==# '', 'command run query failed: ' .. runs_error)
  var run_list = type(runs) == v:t_dict ? get(runs, 'data', []) : runs
  Check(type(run_list) == v:t_list && len(run_list) == 1, 'fixture should record one command run')
  if type(run_list) == v:t_list && len(run_list) == 1
    Check(get(run_list[0], 'command', '') ==# 'review', 'command name was not sent')
    Check(get(run_list[0], 'arguments', '') ==# 'src', 'command arguments were not sent')
    Check(get(run_list[0], 'sessionID', '') ==# 's1', 'command used the wrong session')
    Check(get(get(run_list[0], 'model', {}), 'providerID', '') ==# 'anthropic', 'command did not include the model')
    Check(get(run_list[0], 'agent', '') ==# 'build', 'command did not include the agent')
  endif

  # Prompts include the selected model and agent.
  prompt.Send('catalog prompt', [0, 0])
  sleep 300m
  transport.Request({
    url: BASE .. '/api/prompts',
    method: 'GET',
    timeout_ms: 3000,
    on_success: PromptsOk,
    on_error: PromptsErr,
  })
  WaitFor('prompts', () => type(prompts) != v:t_none)
  Check(prompts_error ==# '', 'prompt query failed: ' .. prompts_error)
  var plist = type(prompts) == v:t_dict ? get(prompts, 'data', []) : prompts
  Check(type(plist) == v:t_list && len(plist) == 1, 'fixture should record one prompt')
  if type(plist) == v:t_list && len(plist) == 1
    Check(get(plist[0], 'text', '') ==# 'catalog prompt', 'prompt text was not sent')
    Check(get(get(plist[0], 'model', {}), 'providerID', '') ==# 'anthropic', 'prompt did not include the model')
    Check(get(plist[0], 'agent', '') ==# 'build', 'prompt did not include the agent')
  endif

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
