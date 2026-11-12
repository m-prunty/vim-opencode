vim9script

# Configuration defaults and validation for vim-opencode.vim.

import autoload 'vim_opencode/util.vim' as util

export const Defaults: dict<any> = {
  server_url: '',
  server_command: [],
  auto_start: true,
  protocol: 'v2',
  directory: '',
  request_timeout_ms: 30000,
  stream_timeout_ms: 120000,
  connect_timeout_ms: 5000,
  reconnect_delay_ms: 1000,
  max_reconnect_delay_ms: 30000,
  default_mappings: true,
  log_level: 'warn',
  log_file: '',
  keymaps: {
    help: '<Leader>oh',
    health: '<Leader>oH',
    prompt: '<Leader>op',
    ask: '<Leader>oa',
    operator: '<Leader>or',
    toggle: '<Leader>ot',
    open: '<Leader>oo',
    explain: '<Leader>ox',
    session_list: '<Leader>osl',
    session_pick: '<Leader>osp',
    session_new: '<Leader>osn',
    session_open: '<Leader>oso',
    model_list: '<Leader>oml',
    model_pick: '<Leader>omp',
    agent_list: '<Leader>ogl',
    agent_pick: '<Leader>ogp',
    server_connect: '<Leader>osc',
    server_status: '<Leader>oss',
    server_disconnect: '<Leader>osd',
    permission_list: '<Leader>oql',
    permission_accept: '<Leader>oqa',
    permission_deny: '<Leader>oqd',
    diff_open: '<Leader>odo',
    diff_accept: '<Leader>oda',
    diff_reject: '<Leader>odr',
    command_list: '<Leader>ocl',
    palette: '<Leader>ocp',
  },
  gui: {
    popup_border: 'rounded',
    popup_title: v:true,
    footer_hint: v:true,
    preview_width: 60,
    colors: v:true,
    default_position: 'right',
  },
  server: {
    username: '',
    password: '',
    headers: {},
  },
  context: {
    max_file_bytes: 262144,
    max_buffers: 20,
    include_diagnostics: true,
    diagnostics_source: 'quickfix',
  },
  panel: {
    height: 20,
    width: 80,
    position: 'botright',
    debounce_ms: 60,
    max_messages: 200,
  },
  diff: {
    close_on_reply: true,
    mappings: true,
  },
}

# Merge user settings into the defaults, validate them and install the result.
export def Setup(user: dict<any>): dict<any>
  var merged = DeepMerge(deepcopy(Defaults), user)
  Validate(merged)
  Normalize(merged)
  g:vim_opencode_config = merged
  return merged
enddef

# Return the active configuration, creating defaults when necessary.
export def Get(): dict<any>
  if !exists('g:vim_opencode_config')
    return Setup({})
  endif
  if type(g:vim_opencode_config) != v:t_dict
    throw 'vim-opencode config: g:vim_opencode_config must be a dictionary'
  endif
  return g:vim_opencode_config
enddef

# Look up a dotted configuration path, returning v:null when it is absent.
export def GetPath(path: string): any
  var node: any = Get()
  if path ==# ''
    return node
  endif
  for part in split(path, '\.')
    if type(node) != v:t_dict || !has_key(node, part)
      return v:null
    endif
    node = node[part]
  endfor
  return node
enddef

# Recursively merge override into base without mutating either input.
export def DeepMerge(base: dict<any>, override: dict<any>): dict<any>
  var merged = deepcopy(base)
  for [key, value] in items(override)
    if type(value) == v:t_dict && type(get(merged, key, 0)) == v:t_dict
      merged[key] = DeepMerge(merged[key], value)
    else
      merged[key] = deepcopy(value)
    endif
  endfor
  return merged
enddef

# Validate a merged configuration. Throws an actionable error on failure.
export def Validate(config: dict<any>): bool
  RequireString(config, 'server_url')
  RequireString(config, 'directory')
  RequireString(config, 'log_file')
  RequireBool(config, 'auto_start')
  RequireBool(config, 'default_mappings')

  if config.server_url !=# '' && config.server_url !~# '^https\?://'
    Fail('server_url must start with http:// or https://')
  endif

  if type(config.protocol) != v:t_string || index(['v1', 'v2'], config.protocol) < 0
    Fail('protocol must be v1 or v2')
  endif

  RequirePositiveNumber(config, 'request_timeout_ms')
  RequirePositiveNumber(config, 'stream_timeout_ms')
  RequirePositiveNumber(config, 'connect_timeout_ms')
  RequirePositiveNumber(config, 'reconnect_delay_ms')
  RequirePositiveNumber(config, 'max_reconnect_delay_ms')

  if config.max_reconnect_delay_ms < config.reconnect_delay_ms
    Fail('max_reconnect_delay_ms must be greater than or equal to reconnect_delay_ms')
  endif

  var levels = util.LogLevels()
  if type(config.log_level) != v:t_string || !has_key(levels, config.log_level)
    Fail('log_level must be one of: ' .. join(keys(levels), ', '))
  endif

  ValidateServerCommand(config.server_command)
  ValidateKeymaps(config.keymaps)
  ValidateServer(config.server)
  ValidateContext(config.context)
  ValidatePanel(config.panel)
  ValidateDiff(config.diff)
  ValidateGui(config.gui)
  return true
enddef

# Remove the trailing slash from URLs and normalize configured directories.
def Normalize(config: dict<any>)
  if config.server_url !=# ''
    config.server_url = substitute(config.server_url, '/\+$', '', '')
  endif
  if config.directory !=# ''
    config.directory = util.NormalizePath(config.directory)
  endif
enddef

def ValidateServerCommand(value: any)
  if type(value) == v:t_string
    return
  endif
  if type(value) != v:t_list
    Fail('server_command must be a string or a list of strings')
  endif
  for item in value
    if type(item) != v:t_string
      Fail('server_command list items must be strings')
    endif
  endfor
enddef

def ValidateKeymaps(value: any)
  RequireDict(value, 'keymaps')
  for [action, mapping] in items(value)
    if type(mapping) != v:t_string
      Fail('keymaps.' .. action .. ' must be a string')
    endif
  endfor
enddef

def ValidateServer(value: any)
  RequireDict(value, 'server')
  RequireString(value, 'username', 'server')
  RequireString(value, 'password', 'server')
  RequireDict(get(value, 'headers', {}), 'server.headers')
  for [name, header] in items(get(value, 'headers', {}))
    if type(name) != v:t_string || type(header) != v:t_string
      Fail('server.headers must map strings to strings')
    endif
  endfor
enddef

def ValidateContext(value: any)
  RequireDict(value, 'context')
  RequirePositiveNumber(value, 'max_file_bytes', 'context')
  RequirePositiveNumber(value, 'max_buffers', 'context')
  RequireBool(value, 'include_diagnostics', 'context')
  RequireString(value, 'diagnostics_source', 'context')
  if index(['quickfix', 'loclist', 'none'], value.diagnostics_source) < 0
    Fail('context.diagnostics_source must be quickfix, loclist or none')
  endif
enddef

def ValidatePanel(value: any)
  RequireDict(value, 'panel')
  RequirePositiveNumber(value, 'height', 'panel')
  RequirePositiveNumber(value, 'width', 'panel')
  RequireString(value, 'position', 'panel')
  RequirePositiveNumber(value, 'debounce_ms', 'panel')
  RequirePositiveNumber(value, 'max_messages', 'panel')
  if index(['botright', 'belowright', 'topleft', 'aboveleft'], value.position) < 0
    Fail('panel.position must be botright, belowright, topleft or aboveleft')
  endif
enddef

def ValidateDiff(value: any)
  RequireDict(value, 'diff')
  RequireBool(value, 'close_on_reply', 'diff')
  RequireBool(value, 'mappings', 'diff')
enddef

def ValidateGui(value: any)
  RequireDict(value, 'gui')
  if type(get(value, 'popup_border', v:null)) != v:t_string
    Fail('gui.popup_border must be a string')
  endif
  if index(['rounded', 'single', 'none'], value.popup_border) < 0
    Fail('gui.popup_border must be rounded, single or none')
  endif
  if type(get(value, 'popup_title', v:null)) != v:t_bool
    Fail('gui.popup_title must be true or false')
  endif
  if type(get(value, 'footer_hint', v:null)) != v:t_bool
    Fail('gui.footer_hint must be true or false')
  endif
  if type(get(value, 'preview_width', v:null)) != v:t_number || value.preview_width <= 0
    Fail('gui.preview_width must be a positive number')
  endif
  if type(get(value, 'colors', v:null)) != v:t_bool
    Fail('gui.colors must be true or false')
  endif
  if type(get(value, 'default_position', v:null)) != v:t_string
    Fail('gui.default_position must be a string')
  endif
  if index(['right', 'horizontal', 'popup'], value.default_position) < 0
    Fail('gui.default_position must be right, horizontal or popup')
  endif
enddef

def RequireDict(value: any, name: string, parent: string = '')
  if type(value) != v:t_dict
    Fail(Prefix(parent, name) .. ' must be a dictionary')
  endif
enddef

def RequireString(dict: dict<any>, key: string, parent: string = '')
  if type(get(dict, key, v:null)) != v:t_string
    Fail(Prefix(parent, key) .. ' must be a string')
  endif
enddef

def RequireBool(dict: dict<any>, key: string, parent: string = '')
  if type(get(dict, key, v:null)) != v:t_bool
    Fail(Prefix(parent, key) .. ' must be true or false')
  endif
enddef

def RequirePositiveNumber(dict: dict<any>, key: string, parent: string = '')
  var value = get(dict, key, v:null)
  if type(value) != v:t_number || value <= 0
    Fail(Prefix(parent, key) .. ' must be a positive number')
  endif
enddef

def Prefix(parent: string, key: string): string
  return parent ==# '' ? key : parent .. '.' .. key
enddef

def Fail(message: string)
  throw 'vim-opencode config: ' .. message
enddef

# Restore an unconfigured state. Primarily useful for tests.
export def Reset()
  if exists('g:vim_opencode_config')
    unlet g:vim_opencode_config
  endif
enddef
