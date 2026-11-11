vim9script

# Command table, parsing and dispatch for :Opencode.

import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/health.vim' as health
import autoload 'opencode9/util.vim' as util

const COMMANDS: dict<dict<any>> = {
  help: {phase: 'P0', usage: 'help [doc]', description: 'Show this summary or open the help file', implemented: true},
  version: {phase: 'P0', usage: 'version', description: 'Show plugin and Vim versions', implemented: true},
  health: {phase: 'P0', usage: 'health', description: 'Run environment checks', implemented: true},
  config: {phase: 'P0', usage: 'config [path|validate]', description: 'Show or validate configuration', implemented: true},
  server: {phase: 'P1', usage: 'server [status|connect|disconnect|start|stop]', description: 'Manage the OpenCode connection', implemented: false},
  session: {phase: 'P4', usage: 'session [list|new|open|rename|delete|fork]', description: 'Manage conversations', implemented: false},
  prompt: {phase: 'P2', usage: 'prompt [text]', description: 'Send a prompt with context placeholders', implemented: false},
  ask: {phase: 'P2', usage: 'ask [text]', description: 'Prompt for text and send it', implemented: false},
  operator: {phase: 'P2', usage: 'operator', description: 'Send the selected range', implemented: false},
  context: {phase: 'P2', usage: 'context [show|clear]', description: 'Inspect or clear captured context', implemented: false},
  toggle: {phase: 'P3', usage: 'toggle', description: 'Toggle the conversation panel', implemented: false},
  open: {phase: 'P3', usage: 'open [input|output|panel]', description: 'Open a panel window', implemented: false},
  close: {phase: 'P3', usage: 'close [input|output|panel]', description: 'Close a panel window', implemented: false},
  permission: {phase: 'P5', usage: 'permission [accept|accept_all|deny]', description: 'Answer pending permission requests', implemented: false},
  diff: {phase: 'P5', usage: 'diff [accept|reject]', description: 'Review the active edit diff', implemented: false},
  quickchat: {phase: 'P7', usage: 'quickchat', description: 'Edit the current range in place', implemented: false},
  debug: {phase: 'P10', usage: 'debug [on|off|dump]', description: 'Inspect plugin state', implemented: false},
}

const ARG_COMPLETIONS: dict<list<string>> = {
  help: ['doc'],
  config: ['show', 'validate', 'server', 'panel', 'context', 'diff', 'keymaps', 'log_level'],
  server: ['status', 'connect', 'disconnect', 'start', 'stop'],
  session: ['list', 'new', 'open', 'rename', 'delete', 'fork'],
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
