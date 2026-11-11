vim9script

# OpenCode V2 protocol adapter.

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
