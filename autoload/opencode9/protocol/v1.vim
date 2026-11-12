vim9script

# OpenCode V1 protocol adapter.
#
# V1 uses a different base path and response shape from V2. This adapter
# normalizes V1 wire shapes into the shared model used by the UI, so the rest
# of the plugin never sees V1/V2 differences directly.

import autoload 'opencode9/protocol/adapter.vim' as adapter
import autoload 'opencode9/util.vim' as util

const HEALTH_PATH = '/global/health'
const EVENT_PATH = '/global/event'
const HEARTBEAT_MS = 20000

export def CanProbe(): bool
  return true
enddef

export def Probe(conn: any, on_success: any, on_error: any): number
  return conn.Request(HEALTH_PATH, 'GET', v:null,
    (response: any, status: number) => {
      var info = NormalizeInfo(response)
      Invoke(on_success, [info])
    },
    on_error)
enddef

export def Subscribe(conn: any, on_event: any, on_error: any, on_close: any): number
  return conn.Stream(EVENT_PATH, {
    heartbeat_ms: HEARTBEAT_MS,
    on_event: (event: any) => {
      Invoke(on_event, [NormalizeEvent(event)])
    },
    on_error: on_error,
    on_close: on_close,
  })
enddef

export def Version(info: any): string
  if type(info) == v:t_dict
    return get(info, 'version', '')
  endif
  return ''
enddef

export def Healthy(info: any): bool
  if type(info) != v:t_dict
    return false
  endif
  return get(info, 'healthy', true)
enddef

export def EventType(event: any): string
  if type(event) == v:t_dict
    return get(event, 'type', '')
  endif
  return ''
enddef

export def EventData(event: any): any
  if type(event) == v:t_dict
    return get(event, 'data', v:null)
  endif
  return v:null
enddef

# Resolve the most recent root session for a directory.
export def ResolveSession(conn: any, directory: string, on_success: any, on_error: any): number
  var path = '/global/session?directory=' .. util.UrlEncode(directory) .. '&order=desc'
  return conn.Request(path, 'GET', v:null,
    (response: any, status: number) => HandleSessions(response, on_success, on_error),
    on_error)
enddef

def HandleSessions(response: any, on_success: any, on_error: any)
  var sessions: any = type(response) == v:t_dict ? get(response, 'sessions', []) : response
  if type(sessions) != v:t_list || empty(sessions)
    Invoke(on_error, ['No OpenCode session found.', -1, 0])
    return
  endif
  for session in sessions
    if type(session) != v:t_dict
      continue
    endif
    var archived = get(session, 'archived', 0)
    if archived == 0
      Invoke(on_success, [NormalizeSession(session)])
      return
    endif
  endfor
  Invoke(on_error, ['No active OpenCode session found.', -1, 0])
enddef

# List non-archived sessions for a directory, newest first.
export def ListSessions(conn: any, directory: string, on_success: any, on_error: any): number
  var path = '/global/session?directory=' .. util.UrlEncode(directory) .. '&order=desc'
  return conn.Request(path, 'GET', v:null,
    (response: any, status: number) => {
      var items: any = type(response) == v:t_dict ? get(response, 'sessions', []) : response
      if type(items) != v:t_list
        Invoke(on_error, ['Unexpected session list response from the server.', -1, 0])
        return
      endif
      var sessions: list<dict<any>> = []
      for item in items
        if type(item) == v:t_dict && !IsArchived(item)
          sessions->add(NormalizeSession(item))
        endif
      endfor
      Invoke(on_success, [sessions])
    },
    on_error)
enddef

export def IsArchived(session: dict<any>): bool
  var archived = get(session, 'archived', 0)
  return archived != 0
enddef

# Create a session.
export def CreateSession(conn: any, opts: dict<any>, on_success: any, on_error: any): number
  var body: dict<any> = {}
  if type(get(opts, 'title', v:null)) != v:t_none
    body.title = opts.title
  endif
  if type(get(opts, 'directory', v:null)) != v:t_none && opts.directory !=# ''
    body.directory = opts.directory
  elseif conn.directory !=# ''
    body.directory = conn.directory
  endif
  return conn.Request('/global/session', 'POST', body, on_success, on_error)
enddef

# Rename a session.
export def RenameSession(conn: any, session_id: string, title: string, on_success: any, on_error: any): number
  return conn.Request(
    '/global/session/' .. util.UrlEncode(session_id),
    'PUT',
    {title: title},
    on_success,
    on_error)
enddef

# Delete a session.
export def DeleteSession(conn: any, session_id: string, on_success: any, on_error: any): number
  return conn.Request(
    '/global/session/' .. util.UrlEncode(session_id),
    'DELETE',
    v:null,
    on_success,
    on_error)
enddef

# Interrupt a running session.
export def InterruptSession(conn: any, session_id: string, on_success: any, on_error: any): number
  return conn.Request(
    '/global/session/' .. util.UrlEncode(session_id) .. '/interrupt',
    'POST',
    {},
    on_success,
    on_error)
enddef

# Fork a session.
export def ForkSession(conn: any, session_id: string, on_success: any, on_error: any): number
  return conn.Request(
    '/global/session/' .. util.UrlEncode(session_id) .. '/fork',
    'POST',
    {},
    on_success,
    on_error)
enddef

# Extract a session dict from a single-session response.
export def SessionValue(value: any): dict<any>
  if type(value) == v:t_dict
    var session = get(value, 'session', value)
    if type(session) == v:t_dict
      return NormalizeSession(session)
    endif
  endif
  return {}
enddef

# Extract the session id from a single-session response.
export def SessionId(value: any): string
  var session = SessionValue(value)
  var id = get(session, 'id', '')
  return type(id) == v:t_string ? id : ''
enddef

# List models.
export def ListModels(conn: any, on_success: any, on_error: any): number
  return conn.Request('/global/model', 'GET', v:null,
    (response: any, status: number) => {
      var models = type(response) == v:t_dict ? get(response, 'models', []) : response
      Invoke(on_success, [models])
    },
    on_error)
enddef

# List providers.
export def ListProviders(conn: any, on_success: any, on_error: any): number
  return conn.Request('/global/provider', 'GET', v:null,
    (response: any, status: number) => {
      var providers = type(response) == v:t_dict ? get(response, 'providers', []) : response
      Invoke(on_success, [providers])
    },
    on_error)
enddef

# List agents.
export def ListAgents(conn: any, on_success: any, on_error: any): number
  return conn.Request('/global/agent', 'GET', v:null,
    (response: any, status: number) => {
      var agents = type(response) == v:t_dict ? get(response, 'agents', []) : response
      Invoke(on_success, [agents])
    },
    on_error)
enddef

# List server commands.
export def ListCommands(conn: any, on_success: any, on_error: any): number
  return conn.Request('/global/command', 'GET', v:null,
    (response: any, status: number) => {
      var commands = type(response) == v:t_dict ? get(response, 'commands', []) : response
      Invoke(on_success, [commands])
    },
    on_error)
enddef

# Reply to a permission request.
export def ReplyPermission(conn: any, session_id: string, request_id: string, reply: string, on_success: any, on_error: any): number
  return conn.Request(
    '/global/session/' .. util.UrlEncode(session_id) .. '/permission/' .. util.UrlEncode(request_id),
    'POST',
    {action: reply},
    on_success,
    on_error)
enddef

# Reply to a question request.
export def ReplyQuestion(conn: any, session_id: string, request_id: string, answer: string, on_success: any, on_error: any): number
  return conn.Request(
    '/global/session/' .. util.UrlEncode(session_id) .. '/question/' .. util.UrlEncode(request_id),
    'POST',
    {answer: answer},
    on_success,
    on_error)
enddef

# Run a server command in a session.
export def RunCommand(conn: any, session_id: string, name: string, arguments: string, opts: dict<any>, on_success: any, on_error: any): number
  var body: dict<any> = {command: name, arguments: arguments}
  if type(get(opts, 'model', v:null)) != v:t_none
    body.model = opts.model
  endif
  if get(opts, 'agent', '') !=# ''
    body.agent = opts.agent
  endif
  return conn.Request(
    '/global/session/' .. util.UrlEncode(session_id) .. '/command',
    'POST',
    body,
    on_success,
    on_error)
enddef

# Send a prompt to a session.
export def Prompt(conn: any, session_id: string, text: string, on_success: any, on_error: any, opts: dict<any> = {}): number
  var body: dict<any> = {text: text}
  if type(get(opts, 'model', v:null)) != v:t_none
    body.model = opts.model
  endif
  if get(opts, 'agent', '') !=# ''
    body.agent = opts.agent
  endif
  return conn.Request(
    '/global/session/' .. util.UrlEncode(session_id) .. '/prompt',
    'POST',
    body,
    on_success,
    on_error)
enddef

# Load a page of messages for the transcript panel.
export def LoadMessages(conn: any, session_id: string, limit: number, on_success: any, on_error: any): number
  var path = '/global/session/' .. util.UrlEncode(session_id) .. '/message?limit=' .. limit
  return conn.Request(path, 'GET', v:null, on_success, on_error)
enddef

# Load a session diff.
export def SessionDiff(conn: any, session_id: string, on_success: any, on_error: any): number
  return conn.Request(
    '/global/session/' .. util.UrlEncode(session_id) .. '/diff',
    'GET',
    v:null,
    on_success,
    on_error)
enddef

# Normalize a V1 health response into a shared info dict.
export def NormalizeInfo(response: any): dict<any>
  if type(response) != v:t_dict
    return {version: '', healthy: false}
  endif
  return {
    version: get(response, 'version', get(response, 'server_version', '')),
    healthy: get(response, 'healthy', true),
    protocol: 'v1',
  }
enddef

# Normalize a V1 event into a shared event dict.
export def NormalizeEvent(event: any): dict<any>
  if type(event) != v:t_dict
    return {type: '', data: {}}
  endif
  var normalized = deepcopy(event)
  var data = get(event, 'data', {})
  if type(data) != v:t_dict
    data = {}
  endif
  # Map V1 event type names to shared V2-style names.
  var type = get(event, 'type', '')
  if type ==# 'session.status'
    type = 'session.status'
  elseif type ==# 'session.message'
    type = 'session.text.ended'
  elseif type ==# 'permission.requested'
    type = 'permission.asked'
  elseif type ==# 'question.requested'
    type = 'question.asked'
  endif
  normalized.type = type
  normalized.data = data
  return normalized
enddef

# Normalize a V1 session into a shared session dict.
export def NormalizeSession(session: any): dict<any>
  if type(session) != v:t_dict
    return {}
  endif
  var normalized = deepcopy(session)
  var time = get(session, 'time', {})
  if type(time) != v:t_dict
    time = {}
  endif
  normalized.time = time
  if !has_key(normalized, 'id') && has_key(normalized, 'sessionID')
    normalized.id = normalized.sessionID
  endif
  return normalized
enddef

def Invoke(callback: any, args: list<any>)
  if type(callback) == v:t_func
    call(callback, args)
  elseif type(callback) == v:t_string && callback !=# ''
    call(callback, args)
  endif
enddef
