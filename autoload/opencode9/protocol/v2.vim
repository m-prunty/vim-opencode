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
