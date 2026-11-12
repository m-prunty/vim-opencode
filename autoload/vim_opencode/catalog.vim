vim9script

# Model, agent and server-command catalogs.
#
# The V2 endpoints can return lists directly or wrap them in a data key, and
# provider responses sometimes nest their models. Normalize all of those shapes
# into stable entries with a display key, then cache the result. The selected
# model and agent are persisted under XDG_STATE_HOME so they survive restarts.

import autoload 'vim_opencode/events.vim' as events
import autoload 'vim_opencode/protocol/active.vim' as active
import autoload 'vim_opencode/server.vim' as server
import autoload 'vim_opencode/state.vim' as state
import autoload 'vim_opencode/ui/popup.vim' as popup
import autoload 'vim_opencode/util.vim' as util

const PLACEHOLDERS: list<string> = [
  '@this', '@buffer', '@buffers', '@visible', '@quickfix', '@marks', '@diagnostics',
]

var models: list<dict<any>> = []
var agents: list<dict<any>> = []
var commands: list<dict<any>> = []
var selected_model: dict<any> = {}
var selected_agent = ''
var prefs_loaded = false

# ---------------------------------------------------------------------------
# Catalogs

export def Models(): list<dict<any>>
  return models
enddef

export def Agents(): list<dict<any>>
  return agents
enddef

export def Commands(): list<dict<any>>
  return commands
enddef

export def RefreshModels(on_success: any = v:null, on_error: any = v:null)
  var conn = RequireConnection(on_error)
  if type(conn) == v:t_none
    return
  endif
  active.ListModels(conn,
    (value: any, status: number) => {
      var normalized = NormalizeModels(value)
      if empty(normalized)
        active.ListProviders(conn,
          (providers: any, provider_status: number) => {
            models = NormalizeModels(providers)
            Done(on_success, models)
          },
          (message: string, exit: number, code: number) => Fail(on_error, message))
        return
      endif
      models = normalized
      Done(on_success, models)
    },
    (message: string, exit: number, status: number) => Fail(on_error, message))
enddef

export def RefreshAgents(on_success: any = v:null, on_error: any = v:null)
  var conn = RequireConnection(on_error)
  if type(conn) == v:t_none
    return
  endif
  active.ListAgents(conn,
    (value: any, status: number) => {
      agents = NormalizeAgents(value)
      Done(on_success, agents)
    },
    (message: string, exit: number, status: number) => Fail(on_error, message))
enddef

export def RefreshCommands(on_success: any = v:null, on_error: any = v:null)
  var conn = RequireConnection(on_error)
  if type(conn) == v:t_none
    return
  endif
  active.ListCommands(conn,
    (value: any, status: number) => {
      commands = NormalizeCommands(value)
      Done(on_success, commands)
    },
    (message: string, exit: number, status: number) => Fail(on_error, message))
enddef

# ---------------------------------------------------------------------------
# Selection

export def CurrentModel(): dict<any>
  LoadPrefs()
  return selected_model
enddef

export def ModelLabel(): string
  LoadPrefs()
  if empty(selected_model)
    return ''
  endif
  var provider = GetString(selected_model, 'providerID')
  var model = GetString(selected_model, 'modelID')
  if provider !=# '' && model !=# ''
    return provider .. '/' .. model
  endif
  return model !=# '' ? model : provider
enddef

export def CurrentAgent(): string
  LoadPrefs()
  return selected_agent
enddef

export def AgentLabel(): string
  return CurrentAgent()
enddef

export def SelectModel(token: string): bool
  var entry = FindModel(token)
  if empty(entry)
    util.EchoError('unknown model "' .. token .. '"; run :Opencode model list')
    return false
  endif
  var chosen: dict<any> = {}
  var provider = GetString(entry, 'providerID')
  var model = GetString(entry, 'modelID')
  if provider !=# ''
    chosen.providerID = provider
  endif
  if model !=# ''
    chosen.modelID = model
  endif
  selected_model = chosen
  SavePrefs()
  events.EmitLocal('model.selected', {model: ModelLabel(), providerID: provider, modelID: model})
  util.EchoInfo('model: ' .. ModelLabel())
  return true
enddef

export def ClearModel()
  selected_model = {}
  SavePrefs()
  events.EmitLocal('model.cleared', {})
  util.EchoInfo('model selection cleared')
enddef

export def SelectAgent(token: string): bool
  var entry = FindAgent(token)
  if empty(entry)
    util.EchoError('unknown agent "' .. token .. '"; run :Opencode agent list')
    return false
  endif
  selected_agent = GetString(entry, 'name')
  SavePrefs()
  events.EmitLocal('agent.selected', {agent: selected_agent})
  util.EchoInfo('agent: ' .. selected_agent)
  return true
enddef

export def ClearAgent()
  selected_agent = ''
  SavePrefs()
  events.EmitLocal('agent.cleared', {})
  util.EchoInfo('agent selection cleared')
enddef

# Options passed to prompt and command requests.
export def PromptOptions(): dict<any>
  LoadPrefs()
  var opts: dict<any> = {}
  if !empty(selected_model)
    opts.model = deepcopy(selected_model)
  endif
  if selected_agent !=# ''
    opts.agent = selected_agent
  endif
  return opts
enddef

export def FindModel(token: string): dict<any>
  if token ==# ''
    return {}
  endif
  if token =~# '^\d\+$'
    var index = str2nr(token)
    if index >= 1 && index <= len(models)
      return models[index - 1]
    endif
  endif
  for entry in models
    if GetString(entry, 'key') ==# token
      return entry
    endif
  endfor
  for entry in models
    if GetString(entry, 'name') ==# token
      return entry
    endif
  endfor
  for entry in models
    var key = GetString(entry, 'key')
    if key !=# '' && stridx(key, token) == 0
      return entry
    endif
  endfor
  # Accept provider/model directly even before the catalog was fetched.
  if token =~# '/'
    var parts = split(token, '/', 1)
    return {key: token, providerID: parts[0], modelID: join(parts[1 :], '/'), name: token}
  endif
  return {}
enddef

export def FindAgent(token: string): dict<any>
  if token ==# ''
    return {}
  endif
  if token =~# '^\d\+$'
    var index = str2nr(token)
    if index >= 1 && index <= len(agents)
      return agents[index - 1]
    endif
  endif
  for entry in agents
    var name = GetString(entry, 'name')
    if name ==# token
      return entry
    endif
  endfor
  for entry in agents
    var name = GetString(entry, 'name')
    if name !=# '' && stridx(name, token) == 0
      return entry
    endif
  endfor
  return {}
enddef

# ---------------------------------------------------------------------------
# Listing and pickers

export def ListModels()
  RefreshModels((items: any) => ListPopup('model', items),
    (message: string) => util.EchoError(message))
enddef

export def ListAgents()
  RefreshAgents((items: any) => ListPopup('agent', items),
    (message: string) => util.EchoError(message))
enddef

export def ListCommands()
  RefreshCommands((items: any) => ListPopup('command', items),
    (message: string) => util.EchoError(message))
enddef

# Render a list of catalog entries in a popup (no action on Enter).
def ListPopup(kind: string, items: any)
  if type(items) != v:t_list || empty(items)
    util.EchoInfo('no ' .. kind .. 's available')
    return
  endif
  var labels: list<string> = []
  var index = 1
  for entry in items
    labels->add(FormatEntry(kind, entry, index, ''))
    index += 1
  endfor
  var title = 'OpenCode ' .. kind .. 's'
  var footer = 'C-Q close'
  var spec: dict<any> = {
    \ items: labels,
    \ title: title,
    \ border: 'rounded',
    \ width: 70,
    \ height: min([len(labels) + 4, 20]),
    \ callback: (sel: string) => {},
    \ footer: footer,
    \ }
  popup.Run(spec)
enddef

export def PickModel()
  RefreshModels((items: any) => ShowPicker('model', items),
    (message: string) => util.EchoError(message))
enddef

export def PickAgent()
  RefreshAgents((items: any) => ShowPicker('agent', items),
    (message: string) => util.EchoError(message))
enddef

export def PickCommand()
  RefreshCommands((items: any) => ShowPicker('command', items),
    (message: string) => util.EchoError(message))
enddef

def PrintEntries(kind: string, items: any, current: string)
  if type(items) != v:t_list || empty(items)
    util.EchoInfo('no ' .. kind .. 's available')
    return
  endif
  var lines: list<string> = []
  var index = 1
  for entry in items
    lines->add(FormatEntry(kind, entry, index, current))
    index += 1
  endfor
  echomsg join(lines, "\n")
enddef

def FormatEntry(kind: string, entry: dict<any>, index: number, current: string): string
  var key = GetString(entry, 'key')
  var marker = key ==# current ? '*' : ' '
  var label = printf('%s [%d] %s', marker, index, key)
  if kind ==# 'agent' || kind ==# 'command'
    var description = GetString(entry, 'description')
    if description !=# ''
      label ..= '  ' .. description
    endif
  endif
  if kind ==# 'command'
    var hint = GetString(entry, 'hint')
    if hint !=# ''
      label ..= '  ' .. hint
    endif
  endif
  return label
enddef

def ShowPicker(kind: string, items: any)
  if type(items) != v:t_list || empty(items)
    util.EchoInfo('no ' .. kind .. 's available')
    return
  endif
  var labels: list<string> = []
  var index = 1
  for entry in items
    var current = kind ==# 'model' ? ModelLabel() : (kind ==# 'agent' ? AgentLabel() : '')
    labels->add(FormatEntry(kind, entry, index, current))
    index += 1
  endfor
  var title = 'OpenCode ' .. kind .. 's'
  var footer = 'Enter pick | C-P preview | C-Q quit'
  popup.Run({
    \ items: labels,
    \ title: title,
    \ border: 'rounded',
    \ width: 70,
    \ height: min([len(labels) + 4, 20]),
    \ callback: (selection: string) => {
      var choice = 0
      var m = matchstr(selection, '^\\[\(\d\+\)\\]')
      if m !=# ''
        choice = str2nr(substitute(m, '[\\[\]]', '', 'g'))
      endif
      if choice < 1 || choice > len(items)
        return
      endif
      var entry = items[choice - 1]
      if kind ==# 'model'
        SelectModel(GetString(entry, 'key'))
      elseif kind ==# 'agent'
        SelectAgent(GetString(entry, 'name'))
      else
        RunFromPicker(entry)
      endif
    },
    \ footer: footer,
    \ })
enddef

def ChooseEntry(kind: string, index: number)
  var items = kind ==# 'model' ? models : (kind ==# 'agent' ? agents : commands)
  if index < 1 || index > len(items)
    return
  endif
  var entry = items[index - 1]
  if kind ==# 'model'
    SelectModel(GetString(entry, 'key'))
  elseif kind ==# 'agent'
    SelectAgent(GetString(entry, 'name'))
  else
    RunFromPicker(entry)
  endif
enddef

# ---------------------------------------------------------------------------
# Server commands

export def RunCommand(name: string, arguments: string = '')
  if name ==# ''
    util.EchoError('a command name is required; run :Opencode command list')
    return
  endif
  var conn = server.Current()
  if type(conn) == v:t_none
    util.EchoError('not connected; run :Opencode server connect')
    return
  endif
  var id = state.SessionId()
  if id !=# ''
    RunInSession(conn, id, name, arguments)
    return
  endif
  active.ResolveSession(conn, util.Cwd(),
    (session: any) => {
      var session_id = type(session) == v:t_dict ? get(session, 'id', '') : ''
      if type(session_id) != v:t_string || session_id ==# ''
        util.EchoError('resolved session has no id')
        return
      endif
      RunInSession(conn, session_id, name, arguments)
    },
    (message: string, exit: number, status: number) => util.EchoError(message))
enddef

def RunInSession(conn: any, session_id: string, name: string, arguments: string)
  active.RunCommand(conn, session_id, name, arguments, PromptOptions(),
    (value: any, status: number) => {
      events.EmitLocal('command.ran', {sessionID: session_id, command: name, arguments: arguments})
      util.EchoInfo('ran /' .. name .. (arguments ==# '' ? '' : ' ' .. arguments))
    },
    (message: string, exit: number, status: number) => util.EchoError(message))
enddef

def RunFromPicker(entry: dict<any>)
  var name = GetString(entry, 'name')
  var hint = GetString(entry, 'hint')
  var arguments = input('/' .. name .. (hint ==# '' ? ' ' : ' ' .. hint .. ' '), '')
  RunCommand(name, arguments)
enddef

# Candidates for input-buffer completion. Commands use the familiar leading
# slash but are not parsed as a separate DSL.
export def Complete(base: string): list<string>
  var candidates: list<string> = []
  if base ==# '' || base[0] ==# '@'
    for placeholder in PLACEHOLDERS
      if stridx(placeholder, base) == 0
        candidates->add(placeholder)
      endif
    endfor
  endif
  if base ==# '' || base[0] ==# '/'
    var prefix = base ==# '' ? '' : strpart(base, 1)
    for entry in commands
      var name = GetString(entry, 'name')
      if name !=# '' && stridx(name, prefix) == 0
        candidates->add('/' .. name)
      endif
    endfor
  endif
  return candidates
enddef

# ---------------------------------------------------------------------------
# Persistence

export def PreferencesFile(): string
  return util.StateDir() .. '/favorites.json'
enddef

def LoadPrefs()
  if prefs_loaded
    return
  endif
  prefs_loaded = true
  var file = PreferencesFile()
  if !filereadable(file)
    return
  endif
  try
    var data = util.JsonDecode(join(readfile(file), "\n"))
    if type(data) != v:t_dict
      return
    endif
    var model = get(data, 'model', v:null)
    if type(model) == v:t_dict
      selected_model = deepcopy(model)
    endif
    var agent = get(data, 'agent', '')
    if type(agent) == v:t_string
      selected_agent = agent
    endif
  catch
    util.Log('warn', 'could not read preferences: ' .. util.ExceptionText())
  endtry
enddef

def SavePrefs()
  try
    var file = PreferencesFile()
    util.EnsureDir(fnamemodify(file, ':h'))
    writefile([util.JsonEncode({model: selected_model, agent: selected_agent})], file)
  catch
    util.Log('warn', 'could not save preferences: ' .. util.ExceptionText())
  endtry
enddef

# ---------------------------------------------------------------------------
# Normalization

def NormalizeModels(value: any): list<dict<any>>
  var out: list<dict<any>> = []
  var source = Unwrap(value)
  if type(source) == v:t_dict
    var providers: any = get(source, 'providers', source)
    if type(providers) == v:t_dict
      for [provider_id, provider] in items(providers)
        AddProviderModels(out, provider_id, provider)
      endfor
      return out
    endif
    if type(providers) == v:t_list
      for provider in providers
        AddProviderModels(out, '', provider)
      endfor
      return out
    endif
    AddModel(out, source, '')
    return out
  endif
  if type(source) == v:t_list
    for entry in source
      if type(entry) != v:t_dict
        continue
      endif
      if has_key(entry, 'models') || has_key(entry, 'providers')
        AddProviderModels(out, '', entry)
      else
        AddModel(out, entry, '')
      endif
    endfor
  endif
  return out
enddef

def AddProviderModels(out: list<dict<any>>, provider_id: string, provider: any)
  if type(provider) != v:t_dict
    return
  endif
  var id = provider_id
  if id ==# ''
    id = GetString(provider, 'id')
  endif
  if id ==# ''
    id = GetString(provider, 'providerID')
  endif
  var nested = get(provider, 'models', v:null)
  if type(nested) == v:t_list
    for model in nested
      if type(model) == v:t_dict
        AddModel(out, model, id)
      endif
    endfor
    return
  endif
  if type(nested) == v:t_dict
    for [model_id, model] in items(nested)
      if type(model) == v:t_dict
        if !has_key(model, 'id') && !has_key(model, 'modelID')
          model.modelID = model_id
        endif
        AddModel(out, model, id)
      endif
    endfor
    return
  endif
  AddModel(out, provider, id)
enddef

def AddModel(out: list<dict<any>>, raw: dict<any>, fallback_provider: string)
  var provider = GetString(raw, 'providerID')
  if provider ==# ''
    provider = GetString(raw, 'provider')
  endif
  if provider ==# ''
    provider = fallback_provider
  endif
  var model_id = GetString(raw, 'modelID')
  if model_id ==# ''
    model_id = GetString(raw, 'model')
  endif
  if model_id ==# ''
    model_id = GetString(raw, 'id')
  endif
  if model_id ==# ''
    return
  endif
  if provider ==# '' && model_id =~# '/'
    var parts = split(model_id, '/', 1)
    provider = parts[0]
    model_id = join(parts[1 :], '/')
  endif
  var key = provider ==# '' ? model_id : provider .. '/' .. model_id
  if !empty(FindByKey(out, key))
    return
  endif
  var name = GetString(raw, 'name')
  out->add({
    key: key,
    providerID: provider,
    modelID: model_id,
    name: name ==# '' ? key : name,
    variants: get(raw, 'variants', []),
    raw: raw,
  })
enddef

def NormalizeAgents(value: any): list<dict<any>>
  var out: list<dict<any>> = []
  for entry in Collection(value)
    if type(entry) != v:t_dict
      continue
    endif
    var name = GetString(entry, 'name')
    if name ==# ''
      name = GetString(entry, 'id')
    endif
    if name ==# '' || !empty(FindByKey(out, name))
      continue
    endif
    out->add({
      key: name,
      name: name,
      description: GetString(entry, 'description'),
      mode: GetString(entry, 'mode'),
      raw: entry,
    })
  endfor
  return out
enddef

def NormalizeCommands(value: any): list<dict<any>>
  var out: list<dict<any>> = []
  for entry in Collection(value)
    if type(entry) != v:t_dict
      continue
    endif
    var name = GetString(entry, 'name')
    if name ==# ''
      name = GetString(entry, 'id')
    endif
    if name ==# '' || !empty(FindByKey(out, name))
      continue
    endif
    var hint = GetString(entry, 'argumentHint')
    if hint ==# ''
      hint = GetString(entry, 'hint')
    endif
    out->add({
      key: name,
      name: name,
      description: GetString(entry, 'description'),
      hint: hint,
      agent: GetString(entry, 'agent'),
      raw: entry,
    })
  endfor
  return out
enddef

# Unwrap data/collection wrappers used by the V2 endpoints.
def Unwrap(value: any): any
  if type(value) != v:t_dict
    return value
  endif
  if has_key(value, 'data')
    return value.data
  endif
  if has_key(value, 'models')
    return value.models
  endif
  if has_key(value, 'agents')
    return value.agents
  endif
  if has_key(value, 'commands')
    return value.commands
  endif
  if has_key(value, 'providers')
    return value.providers
  endif
  return value
enddef

def Collection(value: any): list<any>
  var source = Unwrap(value)
  return type(source) == v:t_list ? source : []
enddef

def FindByKey(items: list<dict<any>>, key: string): dict<any>
  for item in items
    if GetString(item, 'key') ==# key
      return item
    endif
  endfor
  return {}
enddef

# ---------------------------------------------------------------------------
# Helpers

def RequireConnection(on_error: any): any
  var conn = server.Current()
  if type(conn) == v:t_none
    Fail(on_error, 'not connected; run :Opencode server connect')
    return v:null
  endif
  return conn
enddef

def Done(on_success: any, value: any)
  Invoke(on_success, [value])
enddef

def Fail(on_error: any, message: string)
  if type(on_error) == v:t_func || (type(on_error) == v:t_string && on_error !=# '')
    Invoke(on_error, [message])
  else
    util.EchoError(message)
  endif
enddef

def Invoke(callback: any, args: list<any>)
  if type(callback) == v:t_func
    call(callback, args)
  elseif type(callback) == v:t_string && callback !=# ''
    call(callback, args)
  endif
enddef

def GetString(dict: dict<any>, key: string): string
  var value = get(dict, key, '')
  return type(value) == v:t_string ? value : ''
enddef
