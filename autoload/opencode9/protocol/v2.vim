vim9script

# OpenCode V2 protocol adapter.

import autoload 'opencode9/util.vim' as util

const INFO_PATH = '/api/info'
const EVENT_PATH = '/api/event'
const HEARTBEAT_MS = 20000

export def Probe(conn: any, on_success: any, on_error: any): number
  return conn.Request(INFO_PATH, 'GET', v:null, on_success, on_error)
enddef

export def Subscribe(conn: any, on_event: any, on_error: any, on_close: any): number
  return conn.Stream(EVENT_PATH, {
    heartbeat_ms: HEARTBEAT_MS,
    on_event: on_event,
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
  var path = '/api/session?directory=' .. util.UrlEncode(directory) .. '&order=desc&parentID=null'
  return conn.Request(path, 'GET', v:null,
    (response: any, status: number) => HandleSessions(response, directory, on_success, on_error),
    on_error)
enddef

def HandleSessions(response: any, directory: string, on_success: any, on_error: any)
  var sessions: any = type(response) == v:t_dict ? get(response, 'data', []) : response
  if type(sessions) != v:t_list || empty(sessions)
    Invoke(on_error, ['No OpenCode session found for `' .. directory .. '`. Start one in the TUI.', -1, 0])
    return
  endif
  for session in sessions
    if type(session) != v:t_dict
      continue
    endif
    var time = get(session, 'time', {})
    var archived = type(time) == v:t_dict ? get(time, 'archived', 0) : 0
    if archived == 0
      Invoke(on_success, [session])
      return
    endif
  endfor
  Invoke(on_error, ['No active OpenCode session found for `' .. directory .. '`.', -1, 0])
enddef

# List the non-archived sessions for a directory, newest first.
export def ListSessions(conn: any, directory: string, on_success: any, on_error: any): number
  var path = '/api/session?directory=' .. util.UrlEncode(directory) .. '&order=desc'
  return conn.Request(path, 'GET', v:null,
    (response: any, status: number) => HandleSessionList(response, on_success, on_error),
    on_error)
enddef

def HandleSessionList(response: any, on_success: any, on_error: any)
  var items: any = type(response) == v:t_dict ? get(response, 'data', []) : response
  if type(items) != v:t_list
    Invoke(on_error, ['Unexpected session list response from the server.', -1, 0])
    return
  endif
  var sessions: list<dict<any>> = []
  for item in items
    if type(item) == v:t_dict && !IsArchived(item)
      sessions->add(item)
    endif
  endfor
  Invoke(on_success, [sessions])
enddef

export def IsArchived(session: dict<any>): bool
  var time = get(session, 'time', {})
  var archived = type(time) == v:t_dict ? get(time, 'archived', 0) : 0
  return archived != 0
enddef

# Create a session for the connection directory. opts may carry a title and
# parentID; the directory is added when the caller did not provide one.
export def CreateSession(conn: any, opts: dict<any>, on_success: any, on_error: any): number
  var body = deepcopy(opts)
  if !has_key(body, 'directory')
    body.directory = conn.directory
  endif
  return conn.Request('/api/session', 'POST', body, on_success, on_error)
enddef

export def RenameSession(conn: any, session_id: string, title: string, on_success: any, on_error: any): number
  return conn.Request(
    '/api/session/' .. util.UrlEncode(session_id),
    'PATCH',
    {title: title},
    on_success,
    on_error)
enddef

export def DeleteSession(conn: any, session_id: string, on_success: any, on_error: any): number
  return conn.Request(
    '/api/session/' .. util.UrlEncode(session_id),
    'DELETE',
    v:null,
    on_success,
    on_error)
enddef

export def ForkSession(conn: any, session_id: string, on_success: any, on_error: any): number
  return conn.Request(
    '/api/session/' .. util.UrlEncode(session_id) .. '/fork',
    'POST',
    {},
    on_success,
    on_error)
enddef

# Extract a session dictionary from a single-session response.
export def SessionValue(value: any): dict<any>
  if type(value) == v:t_dict
    var data = get(value, 'data', value)
    if type(data) == v:t_dict
      return data
    endif
  endif
  return {}
enddef

# Extract the id from a single-session response.
export def SessionId(value: any): string
  var session = SessionValue(value)
  var id = get(session, 'id', '')
  return type(id) == v:t_string ? id : ''
enddef

# Send a plain-text prompt to a session.
export def Prompt(conn: any, session_id: string, text: string, on_success: any, on_error: any): number
  return conn.Request(
    '/api/session/' .. util.UrlEncode(session_id) .. '/prompt',
    'POST',
    {text: text},
    on_success,
    on_error)
enddef

# Load a page of messages for the transcript panel.
export def LoadMessages(conn: any, session_id: string, limit: number, on_success: any, on_error: any): number
  var path = '/api/session/' .. util.UrlEncode(session_id) .. '/message?limit=' .. limit
  return conn.Request(path, 'GET', v:null, on_success, on_error)
enddef

def Invoke(callback: any, args: list<any>)
  if type(callback) == v:t_func
    call(callback, args)
  elseif type(callback) == v:t_string && callback !=# ''
    call(callback, args)
  endif
enddef
