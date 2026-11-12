vim9script

# Lightweight project-scoped panel tabs. A tab stores only durable metadata;
# transcript content remains owned by the server/session state model.

import autoload 'vim_opencode/events.vim' as events
import autoload 'vim_opencode/server.vim' as server
import autoload 'vim_opencode/sessions.vim' as sessions
import autoload 'vim_opencode/state.vim' as state
import autoload 'vim_opencode/ui/panel.vim' as panel
import autoload 'vim_opencode/util.vim' as util

var tabs: list<dict<any>> = []
var current = 0
var loaded = false

export def Setup()
  if loaded
    return
  endif
  loaded = true
  Restore()
  events.AddListener(OnEvent)
enddef

export def List(): list<dict<any>>
  EnsureCurrent()
  return tabs
enddef

export def Current(): dict<any>
  EnsureCurrent()
  return empty(tabs) ? {} : tabs[current]
enddef

export def New(session_id: string = '')
  EnsureCurrent()
  var id = session_id ==# '' ? state.SessionId() : session_id
  tabs->add({id: 'tab-' .. (len(tabs) + 1), sessionID: id, directory: util.Cwd(), draft: ''})
  current = len(tabs) - 1
  Save()
  events.EmitLocal('tab.created', {index: current + 1, sessionID: id})
enddef

export def Select(token: string)
  EnsureCurrent()
  var index = Resolve(token)
  if index < 0
    util.EchoError('unknown tab "' .. token .. '"')
    return
  endif
  current = index
  var id = get(tabs[current], 'sessionID', '')
  if id !=# '' && type(server.Current()) != v:t_none
    panel.OpenSession(id)
  else
    panel.Open()
  endif
  Save()
  events.EmitLocal('tab.selected', {index: current + 1, sessionID: id})
enddef

export def Close(token: string = '')
  EnsureCurrent()
  var index = token ==# '' ? current : Resolve(token)
  if index < 0 || empty(tabs)
    return
  endif
  remove(tabs, index)
  if empty(tabs)
    current = 0
  else
    current = min([current, len(tabs) - 1])
  endif
  Save()
  events.EmitLocal('tab.closed', {index: index + 1})
enddef

export def Format(tab: dict<any>, index: number): string
  var marker = index - 1 == current ? '*' : ' '
  var id = get(tab, 'sessionID', '')
  return printf('%s [%d] %s', marker, index, id ==# '' ? '(new)' : id)
enddef

export def File(): string
  return util.StateDir() .. '/tabs-' .. substitute(util.Cwd(), '[^A-Za-z0-9._-]', '_', 'g') .. '.json'
enddef

def EnsureCurrent()
  if empty(tabs)
    tabs->add({id: 'tab-1', sessionID: state.SessionId(), directory: util.Cwd(), draft: ''})
    current = 0
  endif
enddef

def Resolve(token: string): number
  if token =~# '^\d\+$'
    var index = str2nr(token) - 1
    return index >= 0 && index < len(tabs) ? index : -1
  endif
  for index in range(len(tabs))
    if tabs[index].id ==# token || get(tabs[index], 'sessionID', '') ==# token
      return index
    endif
  endfor
  return -1
enddef

def Save()
  try
    var file = File()
    util.EnsureDir(fnamemodify(file, ':h'))
    writefile([util.JsonEncode({current: current, tabs: tabs})], file)
  catch
    util.Log('warn', 'could not save panel tabs: ' .. util.ExceptionText())
  endtry
enddef

def Restore()
  var file = File()
  if !filereadable(file)
    return
  endif
  try
    var value = util.JsonDecode(join(readfile(file), "\n"))
    if type(value) != v:t_dict || type(get(value, 'tabs', [])) != v:t_list
      return
    endif
    tabs = value.tabs
    current = get(value, 'current', 0)
    if current < 0 || current >= len(tabs)
      current = 0
    endif
  catch
    util.Log('warn', 'could not restore panel tabs: ' .. util.ExceptionText())
  endtry
enddef

def OnEvent(event: any)
  var kind = get(event, 'type', '')
  if kind ==# 'session.opened'
    var id = get(get(event, 'data', {}), 'sessionID', '')
    EnsureCurrent()
    tabs[current].sessionID = id
    Save()
  elseif kind ==# 'session.deleted'
    var id = get(get(event, 'data', {}), 'sessionID', '')
    tabs = filter(tabs, (_, tab: dict<any>) => get(tab, 'sessionID', '') !=# id)
    current = min([current, max([0, len(tabs) - 1])])
    Save()
  endif
enddef
