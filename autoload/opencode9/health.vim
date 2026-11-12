vim9script

# Health checks exposed through :Opencode health.

import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/util.vim' as util

const REQUIRED_FEATURES: list<string> = ['job', 'channel', 'timers']
const OPTIONAL_FEATURES: list<string> = ['textprop', 'popupwin', 'diff', 'quickfix', 'syntax']

# Build a human-readable health report without changing editor state.
export def Report(): list<string>
  var lines: list<string> = []
  var version = get(g:, 'opencode9_version', '0.1.0-dev')
  lines->add('opencode9.vim health')
  lines->add('version: ' .. version)
  lines->add('vim: ' .. VimVersion())
  lines->add('')

  for feature in REQUIRED_FEATURES
    lines->add(Status(has(feature), '+' .. feature, 'required for transport and timers'))
  endfor
  for feature in OPTIONAL_FEATURES
    lines->add(Status(has(feature), '+' .. feature, 'enables later UI phases'))
  endfor

  if executable('curl')
    lines->add('[OK]   curl: ' .. CurlVersion())
  else
    lines->add('[FAIL] curl: not found on PATH (required for HTTP and SSE)')
  endif

  try
    var cfg = config.Get()
    lines->add('[OK]   config: loaded (' .. len(cfg) .. ' top-level settings)')
  catch
    lines->add('[FAIL] config: ' .. util.ExceptionText())
  endtry

  lines->add(ModuleStatus('transport', 'autoload/opencode9/transport.vim', 'P1'))
  lines->add(ModuleStatus('discovery', 'autoload/opencode9/discovery.vim', 'P1'))
  lines->add(ModuleStatus('prompt', 'autoload/opencode9/prompt.vim', 'P2'))
  lines->add(ModuleStatus('state', 'autoload/opencode9/state.vim', 'P3'))
  lines->add(ModuleStatus('render', 'autoload/opencode9/ui/render.vim', 'P3'))
  lines->add(ModuleStatus('panel', 'autoload/opencode9/ui/panel.vim', 'P3'))
  lines->add(ModuleStatus('sessions', 'autoload/opencode9/sessions.vim', 'P4'))
  lines->add(ModuleStatus('permissions', 'autoload/opencode9/permissions.vim', 'P5'))
  lines->add(ModuleStatus('diff', 'autoload/opencode9/ui/diff.vim', 'P5'))
  lines->add(ModuleStatus('review', 'autoload/opencode9/review.vim', 'P6'))
  lines->add(ModuleStatus('quickchat', 'autoload/opencode9/quickchat.vim', 'P7'))
  lines->add(ModuleStatus('tabs', 'autoload/opencode9/tabs.vim', 'P8'))

  var doc = globpath(&runtimepath, 'doc/opencode9.txt', true, true)
  lines->add(Status(!empty(doc), 'documentation', 'doc/opencode9.txt'))
  return lines
enddef

# Print the report. The result is also stored in g:opencode9_health_lines.
export def Run()
  var lines = Report()
  g:opencode9_health_lines = lines
  for line in lines
    if util.StartsWith(line, '[FAIL]')
      echohl ErrorMsg
    elseif util.StartsWith(line, '[WARN]')
      echohl WarningMsg
    endif
    echomsg line
    echohl None
  endfor
enddef

# Return true when no check failed.
export def Ok(): bool
  for line in Report()
    if util.StartsWith(line, '[FAIL]')
      return false
    endif
  endfor
  return true
enddef

def Status(ok: bool, label: string, note: string): string
  if ok
    return '[OK]   ' .. label .. ': ' .. note
  endif
  return '[FAIL] ' .. label .. ': ' .. note
enddef

def ModuleStatus(name: string, path: string, phase: string): string
  if !empty(globpath(&runtimepath, path, true, true))
    return '[OK]   ' .. name .. ': available'
  endif
  return '[INFO] ' .. name .. ': not installed yet (' .. phase .. ')'
enddef

def VimVersion(): string
  var major = v:versionlong / 1000000
  var minor = (v:versionlong / 10000) % 100
  var patch = v:versionlong % 10000
  return printf('%d.%d.%04d', major, minor, patch)
enddef

def CurlVersion(): string
  try
    var lines = systemlist('curl --version')
    return empty(lines) ? 'unknown version' : lines[0]
  catch
    return 'version unavailable'
  endtry
enddef
