vim9script

# Command table, parsing and dispatch for :Opencode.

import autoload 'opencode9/catalog.vim' as catalog
import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/context.vim' as context
import autoload 'opencode9/discovery.vim' as discovery
import autoload 'opencode9/health.vim' as health
import autoload 'opencode9/prompt.vim' as prompt
import autoload 'opencode9/quickchat.vim' as quickchat
import autoload 'opencode9/permissions.vim' as permissions
import autoload 'opencode9/server.vim' as server
import autoload 'opencode9/sessions.vim' as sessions
import autoload 'opencode9/state.vim' as state
import autoload 'opencode9/tabs.vim' as tabs
import autoload 'opencode9/ui/panel.vim' as panel
import autoload 'opencode9/ui/diff.vim' as diff
import autoload 'opencode9/review.vim' as review
import autoload 'opencode9/util.vim' as util

const COMMANDS: dict<dict<any>> = {
  help: {phase: 'P0', usage: 'help [doc]', description: 'Show this summary or open the help file', implemented: true},
  version: {phase: 'P0', usage: 'version', description: 'Show plugin and Vim versions', implemented: true},
  health: {phase: 'P0', usage: 'health', description: 'Run environment checks', implemented: true},
  config: {phase: 'P0', usage: 'config [path|validate]', description: 'Show or validate configuration', implemented: true},
  server: {phase: 'P1', usage: 'server [status|connect|disconnect|start|stop]', description: 'Manage the OpenCode connection', implemented: true},
  session: {phase: 'P4', usage: 'session [list|pick|new|open|rename|delete|fork]', description: 'Manage conversations', implemented: true},
  model: {phase: 'P4', usage: 'model [list|pick|current|clear|<model>]', description: 'List or select a model', implemented: true},
  agent: {phase: 'P4', usage: 'agent [list|pick|current|clear|<agent>]', description: 'List or select an agent', implemented: true},
  command: {phase: 'P4', usage: 'command [list|pick|run|<name> [args]]', description: 'List or run a server command', implemented: true},
  prompt: {phase: 'P2', usage: 'prompt [text]', description: 'Send a prompt with context placeholders', implemented: true},
  ask: {phase: 'P2', usage: 'ask [text]', description: 'Prompt for text and send it', implemented: true},
  operator: {phase: 'P2', usage: 'operator', description: 'Send the selected range', implemented: true},
  context: {phase: 'P2', usage: 'context [show|clear]', description: 'Inspect or clear captured context', implemented: true},
  toggle: {phase: 'P3', usage: 'toggle', description: 'Toggle the conversation panel', implemented: true},
  open: {phase: 'P3', usage: 'open [input|output|panel]', description: 'Open a panel window', implemented: true},
  close: {phase: 'P3', usage: 'close [input|output|panel]', description: 'Close a panel window', implemented: true},
  permission: {phase: 'P5', usage: 'permission [list|accept|always|accept_all|deny|ask]', description: 'Answer pending permission requests', implemented: true},
  diff: {phase: 'P5', usage: 'diff [open|accept|reject|close]', description: 'Review the active edit diff', implemented: true},
  review: {phase: 'P6', usage: 'review [list|add|clear]', description: 'Manage review comments', implemented: true},
  quickchat: {phase: 'P7', usage: 'quickchat [instruction]', description: 'Edit the current range in place', implemented: true},
  tab: {phase: 'P8', usage: 'tab [list|new|open|close]', description: 'Manage panel tabs', implemented: true},
  debug: {phase: 'P10', usage: 'debug [on|off|dump]', description: 'Inspect plugin state', implemented: false},
}

const ARG_COMPLETIONS: dict<list<string>> = {
  help: ['doc'],
  config: ['show', 'validate', 'server', 'panel', 'context', 'diff', 'keymaps', 'log_level'],
  prompt: ['@this', '@buffer', '@buffers', '@visible', '@quickfix', '@marks', '@diagnostics'],
  ask: ['@this', '@buffer', '@buffers', '@visible', '@quickfix', '@marks', '@diagnostics'],
  server: ['status', 'connect', 'disconnect', 'start', 'stop'],
  session: ['list', 'pick', 'new', 'open', 'rename', 'delete', 'fork'],
  model: ['list', 'pick', 'current', 'clear'],
  agent: ['list', 'pick', 'current', 'clear'],
  command: ['list', 'pick', 'run'],
  open: ['input', 'output', 'panel'],
  close: ['input', 'output', 'panel', 'diff'],
  permission: ['accept', 'accept_all', 'deny'],
  context: ['show', 'clear'],
  debug: ['on', 'off', 'dump'],
}

# Dispatch :Opencode arguments. Errors are reported instead of escaping.
export def Dispatch(args: string, range: list<number>, bang: bool)
  var trimmed = substitute(args, '^\s\+', '', '')
  var name = matchstr(trimmed, '^\S\+')
  var rest = substitute(trimmed, '^\S\+\s*', '', '')

  if name ==# ''
    name = 'help'
  endif

  try
    if name ==# 'help'
      Help(rest)
    elseif name ==# 'version'
      Version()
    elseif name ==# 'health'
      health.Run()
    elseif name ==# 'config'
      ShowConfig(rest)
    elseif name ==# 'server'
      Server(rest)
    elseif name ==# 'session'
      Session(rest, bang)
    elseif name ==# 'model'
      Model(rest)
    elseif name ==# 'agent'
      Agent(rest)
    elseif name ==# 'command'
      Command(rest)
    elseif name ==# 'permission'
      Permission(rest)
    elseif name ==# 'diff'
      Diff(rest)
    elseif name ==# 'review'
      Review(rest)
    elseif name ==# 'quickchat'
      quickchat.Start(trim(rest), range)
    elseif name ==# 'tab'
      Tab(rest)
    elseif name ==# 'prompt'
      PromptCommand(rest, range)
    elseif name ==# 'ask'
      AskCommand(rest, range)
    elseif name ==# 'operator'
      OperatorCommand(rest)
    elseif name ==# 'context'
      ContextCommand(rest, range)
    elseif name ==# 'toggle'
      panel.Toggle()
    elseif name ==# 'open'
      panel.OpenTarget(trim(rest))
    elseif name ==# 'close'
      panel.CloseTarget(trim(rest))
    elseif has_key(COMMANDS, name)
      NotImplemented(name, COMMANDS[name].phase)
    else
      util.EchoError('unknown command "' .. name .. '"; try :Opencode help')
    endif
  catch
    util.EchoError(util.ExceptionText())
  endtry

  # Keep the parsed values referenced so later phases can extend dispatch
  # without changing the command signature.
  if bang && range[0] < 0
    util.EchoError('invalid range')
  endif
enddef

# Complete subcommands and common arguments without touching the network.
export def Complete(arglead: string, cmdline: string, cursorpos: number): list<string>
  var before = strpart(cmdline, 0, cursorpos)
  var first_space = match(before, '\s')
  var candidates: list<string> = []

  if first_space < 0
    candidates = keys(COMMANDS)
  else
    var rest = strpart(before, first_space + 1)
    if rest ==# '' || match(rest, '\s') < 0
      candidates = keys(COMMANDS)
    else
      var command = matchstr(rest, '^\S\+')
      if has_key(ARG_COMPLETIONS, command)
        candidates = ARG_COMPLETIONS[command]
      endif
    endif
  endif

  var matches: list<string> = []
  for candidate in candidates
    if stridx(candidate, arglead) == 0
      matches->add(candidate)
    endif
  endfor
  sort(matches)
  return matches
enddef

# Return the command table. Used by help and tests.
export def Table(): dict<dict<any>>
  return deepcopy(COMMANDS)
enddef

def Help(rest: string)
  if rest ==# 'doc'
    try
      execute 'help opencode9'
    catch
      util.EchoError('help file is not available; run :helptags doc')
    endtry
    return
  endif

  echomsg 'opencode9.vim ' .. PluginVersion() .. ' on Vim ' .. VimVersion()
  echomsg ''
  echomsg 'Usage: :Opencode [command] [arguments]'
  echomsg ''
  echomsg 'Commands:'
  for name in sort(keys(COMMANDS))
    var meta = COMMANDS[name]
    var marker = meta.implemented ? '' : ' (' .. meta.phase .. ')'
    echomsg printf('  %-12s %s%s', name, meta.description, marker)
  endfor
  echomsg ''
  echomsg 'Run :Opencode help doc for the full help file.'
enddef

def Version()
  echomsg 'opencode9.vim ' .. PluginVersion() .. ' on Vim ' .. VimVersion()
enddef

def ShowConfig(rest: string)
  var argument = substitute(rest, '^\s*\(.\{-}\)\s*$', '\1', '')
  if argument ==# '' || argument ==# 'show'
    echomsg util.JsonEncode(config.Get())
    return
  endif
  if argument ==# 'validate'
    config.Validate(config.Get())
    echomsg 'opencode9: configuration is valid'
    return
  endif

  var value = config.GetPath(argument)
  if type(value) == v:t_none
    util.EchoError('unknown configuration path "' .. argument .. '"')
    return
  endif
  if type(value) == v:t_string
    echomsg value
  else
    echomsg util.JsonEncode(value)
  endif
enddef

def ContextCommand(rest: string, range: list<number>)
  var argument = trim(rest)
  if argument ==# '' || argument ==# 'show'
    var ctx = context.Capture(range)
    var lines: list<string> = []
    for placeholder in context.Placeholders()
      var rendered = context.Render(placeholder, ctx)
      if rendered ==# placeholder
        lines->add(placeholder .. ': (unavailable)')
      else
        lines->add(placeholder .. ': ' .. rendered)
      endif
    endfor
    echomsg join(lines, "\n")
    return
  endif
  if argument ==# 'clear'
    state.Clear()
    var session = state.SessionId()
    echomsg 'opencode9: transcript cleared' .. (session ==# '' ? '' : ' for ' .. session)
    return
  endif
  util.EchoError('unknown context command "' .. argument .. '"; try show or clear')
enddef

def PromptCommand(rest: string, range: list<number>)
  var text = trim(rest)
  if text ==# ''
    prompt.AskWithRange('', range)
  else
    prompt.Send(text, range)
  endif
enddef

def AskCommand(rest: string, range: list<number>)
  prompt.AskWithRange(rest, range)
enddef

def OperatorCommand(rest: string)
  var text = trim(rest)
  prompt.OperatorCommand(text ==# '' ? '@this' : text)
enddef

def Server(rest: string)
  var argument = substitute(rest, '^\s*\(.\{-}\)\s*$', '\1', '')
  if argument ==# '' || argument ==# 'status'
    ShowServerStatus()
  elseif argument ==# 'connect'
    ConnectServer()
  elseif argument ==# 'disconnect'
    DisconnectServer()
  elseif argument ==# 'start'
    StartServer()
  elseif argument ==# 'stop'
    StopServer()
  else
    util.EchoError('unknown server command "' .. argument .. '"; try :Opencode help')
  endif
enddef

def Session(rest: string, bang: bool)
  var argument = trim(rest)
  var action = matchstr(argument, '^\S\+')
  var tail = trim(substitute(argument, '^\S\+\s*', '', ''))
  if action ==# '' || action ==# 'list'
    sessions.List()
  elseif action ==# 'pick'
    sessions.Pick()
  elseif action ==# 'new'
    sessions.New(tail)
  elseif action ==# 'open'
    sessions.Open(tail)
  elseif action ==# 'rename'
    var id = matchstr(tail, '^\S\+')
    var title = trim(substitute(tail, '^\S\+\s*', '', ''))
    sessions.Rename(id, title)
  elseif action ==# 'delete'
    sessions.Delete(tail, bang)
  elseif action ==# 'fork'
    sessions.Fork(tail)
  elseif action ==# 'current'
    var id = sessions.Current()
    echomsg 'opencode9: session ' .. (id ==# '' ? 'none' : id)
  else
    util.EchoError('unknown session command "' .. action .. '"; try :Opencode session list')
  endif
enddef

def Permission(rest: string)
  var argument = trim(rest)
  var action = matchstr(argument, '^\S\+')
  var token = trim(substitute(argument, '^\S\+\s*', '', ''))
  if action ==# '' || action ==# 'list'
    var lines: list<string> = []
    var index = 1
    for item in permissions.Pending()
      lines->add(printf('[%d] %s  %s', index, item.id, item.title))
      index += 1
    endfor
    echomsg empty(lines) ? 'opencode9: no pending permission requests' : join(lines, "\n")
  elseif action ==# 'ask'
    permissions.Ask()
  elseif action ==# 'accept'
    permissions.Accept(token)
  elseif action ==# 'always' || action ==# 'accept_all'
    permissions.Always(token)
  elseif action ==# 'deny'
    permissions.Deny(token)
  else
    util.EchoError('unknown permission action "' .. action .. '"')
  endif
enddef

def Diff(rest: string)
  var action = trim(rest)
  if action ==# '' || action ==# 'open'
    diff.Open()
  elseif action ==# 'accept'
    diff.Accept()
  elseif action ==# 'reject'
    diff.Reject()
  elseif action ==# 'close'
    diff.Close()
  else
    util.EchoError('unknown diff action "' .. action .. '"')
  endif
enddef

def Review(rest: string)
  var argument = trim(rest)
  var action = matchstr(argument, '^\S+')
  var tail = trim(substitute(argument, '^\S+\s*', '', ''))
  if action ==# '' || action ==# 'list'
    var text = review.Text()
    echomsg text ==# '' ? 'opencode9: no review comments' : text
  elseif action ==# 'clear'
    review.Clear()
  elseif action ==# 'add'
    if tail ==# ''
      util.EchoError('review add requires a comment')
    else
      review.AddCurrent(tail)
      util.EchoInfo('review comment added')
    endif
  else
    util.EchoError('unknown review action "' .. action .. '"')
  endif
enddef

def Tab(rest: string)
  var argument = trim(rest)
  var action = matchstr(argument, '^\S+')
  var token = trim(substitute(argument, '^\S+\s*', '', ''))
  if action ==# '' || action ==# 'list'
    var lines: list<string> = []
    var index = 1
    for item in tabs.List()
      lines->add(tabs.Format(item, index))
      index += 1
    endfor
    echomsg join(lines, "\n")
  elseif action ==# 'new'
    tabs.New(token)
  elseif action ==# 'open' || action ==# 'select'
    tabs.Select(token)
  elseif action ==# 'close'
    tabs.Close(token)
  else
    util.EchoError('unknown tab action "' .. action .. '"')
  endif
enddef

def Model(rest: string)
  var argument = trim(rest)
  var action = matchstr(argument, '^\S\+')
  if action ==# '' || action ==# 'list'
    catalog.ListModels()
  elseif action ==# 'pick'
    catalog.PickModel()
  elseif action ==# 'current'
    var label = catalog.ModelLabel()
    echomsg 'opencode9: model ' .. (label ==# '' ? 'not selected' : label)
  elseif action ==# 'clear'
    catalog.ClearModel()
  else
    catalog.SelectModel(argument)
  endif
enddef

def Agent(rest: string)
  var argument = trim(rest)
  var action = matchstr(argument, '^\S\+')
  if action ==# '' || action ==# 'list'
    catalog.ListAgents()
  elseif action ==# 'pick'
    catalog.PickAgent()
  elseif action ==# 'current'
    var label = catalog.AgentLabel()
    echomsg 'opencode9: agent ' .. (label ==# '' ? 'not selected' : label)
  elseif action ==# 'clear'
    catalog.ClearAgent()
  else
    catalog.SelectAgent(argument)
  endif
enddef

def Command(rest: string)
  var argument = trim(rest)
  var action = matchstr(argument, '^\S\+')
  var tail = trim(substitute(argument, '^\S\+\s*', '', ''))
  if action ==# '' || action ==# 'list'
    catalog.ListCommands()
  elseif action ==# 'pick'
    catalog.PickCommand()
  elseif action ==# 'run'
    var name = matchstr(tail, '^\S\+')
    var arguments = trim(substitute(tail, '^\S\+\s*', '', ''))
    catalog.RunCommand(name, arguments)
  else
    catalog.RunCommand(action, tail)
  endif
enddef

def ShowServerStatus()
  var conn = server.Current()
  if type(conn) == v:t_none
    echomsg 'opencode9: not connected'
    return
  endif
  var status = server.Status()
  echomsg printf('opencode9: %s version=%s connected=%s directory=%s',
    status.url,
    status.version ==# '' ? 'unknown' : status.version,
    status.connected ? 'yes' : 'no',
    status.directory)
enddef

def ConnectServer()
  discovery.Connect({
    on_success: (conn: any, info: any) => ServerConnected(conn),
    on_error: (message: string) => util.EchoError(message),
  })
  echomsg 'opencode9: discovering an OpenCode server...'
enddef

def ServerConnected(conn: any)
  echomsg 'opencode9: connected to ' .. conn.Url() .. ' (version ' .. conn.Version() .. ')'
enddef

def DisconnectServer()
  var conn = server.Current()
  if type(conn) == v:t_none
    echomsg 'opencode9: not connected'
    return
  endif
  server.Disconnect(conn)
  echomsg 'opencode9: disconnected'
enddef

def StartServer()
  if !discovery.HasStartCommand()
    util.EchoError('server_command is empty; configure one before starting a server')
    return
  endif
  if discovery.Start((message: string) => util.EchoError(message))
    echomsg 'opencode9: server start requested'
  endif
enddef

def StopServer()
  discovery.StopStarted()
  echomsg 'opencode9: server start job stopped (if one was running)'
enddef

def NotImplemented(name: string, phase: string)
  util.EchoError(name .. ' is not implemented yet (' .. phase .. '); see :Opencode help')
enddef

def PluginVersion(): string
  return get(g:, 'opencode9_version', '0.1.0-dev')
enddef

def VimVersion(): string
  var major = v:versionlong / 1000000
  var minor = (v:versionlong / 10000) % 100
  var patch = v:versionlong % 10000
  return printf('%d.%d.%04d', major, minor, patch)
enddef
