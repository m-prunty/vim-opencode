vim9script

# Active protocol adapter dispatcher.
#
# Delegates to the V1 or V2 adapter based on g:vim_opencode_config.protocol.
# Each function below explicitly calls v1 or v2, because Vim9 does not allow
# imported module namespaces to be passed around as first-class values.

import autoload 'vim_opencode/config.vim' as config
import autoload 'vim_opencode/protocol/v1.vim' as v1
import autoload 'vim_opencode/protocol/v2.vim' as v2
import autoload 'vim_opencode/util.vim' as util

# Return the configured protocol, defaulting to v2.
export def Protocol(): string
  var cfg = config.Get()
  if type(cfg.protocol) != v:t_string || (cfg.protocol !=# 'v1' && cfg.protocol !=# 'v2')
    return 'v2'
  endif
  return cfg.protocol
enddef

# Re-select the active protocol when config changes.
export def SetProtocol(p: string)
  config.Setup(config.DeepMerge(config.Get(), {protocol: p}))
enddef

# Return true when the active protocol is V1.
export def IsV1(): bool
  return Protocol() ==# 'v1'
enddef

# ---- adapter interface (explicit v1/v2 dispatch) ----

export def Probe(conn: any, on_success: any, on_error: any): number
  if IsV1()
    return v1.Probe(conn, on_success, on_error)
  endif
  return v2.Probe(conn, on_success, on_error)
enddef

export def Subscribe(conn: any, on_event: any, on_error: any, on_close: any): number
  if IsV1()
    return v1.Subscribe(conn, on_event, on_error, on_close)
  endif
  return v2.Subscribe(conn, on_event, on_error, on_close)
enddef

export def Version(info: any): string
  if IsV1()
    return v1.Version(info)
  endif
  return v2.Version(info)
enddef

export def Healthy(info: any): bool
  if IsV1()
    return v1.Healthy(info)
  endif
  return v2.Healthy(info)
enddef

export def EventType(event: any): string
  if IsV1()
    return v1.EventType(event)
  endif
  return v2.EventType(event)
enddef

export def EventData(event: any): any
  if IsV1()
    return v1.EventData(event)
  endif
  return v2.EventData(event)
enddef

export def ResolveSession(conn: any, directory: string, on_success: any, on_error: any): number
  if IsV1()
    return v1.ResolveSession(conn, directory, on_success, on_error)
  endif
  return v2.ResolveSession(conn, directory, on_success, on_error)
enddef

export def ListSessions(conn: any, directory: string, on_success: any, on_error: any): number
  if IsV1()
    return v1.ListSessions(conn, directory, on_success, on_error)
  endif
  return v2.ListSessions(conn, directory, on_success, on_error)
enddef

export def CreateSession(conn: any, opts: dict<any>, on_success: any, on_error: any): number
  if IsV1()
    return v1.CreateSession(conn, opts, on_success, on_error)
  endif
  return v2.CreateSession(conn, opts, on_success, on_error)
enddef

export def RenameSession(conn: any, session_id: string, title: string, on_success: any, on_error: any): number
  if IsV1()
    return v1.RenameSession(conn, session_id, title, on_success, on_error)
  endif
  return v2.RenameSession(conn, session_id, title, on_success, on_error)
enddef

export def DeleteSession(conn: any, session_id: string, on_success: any, on_error: any): number
  if IsV1()
    return v1.DeleteSession(conn, session_id, on_success, on_error)
  endif
  return v2.DeleteSession(conn, session_id, on_success, on_error)
enddef

export def InterruptSession(conn: any, session_id: string, on_success: any, on_error: any): number
  if IsV1()
    return v1.InterruptSession(conn, session_id, on_success, on_error)
  endif
  return v2.InterruptSession(conn, session_id, on_success, on_error)
enddef

export def ForkSession(conn: any, session_id: string, on_success: any, on_error: any): number
  if IsV1()
    return v1.ForkSession(conn, session_id, on_success, on_error)
  endif
  return v2.ForkSession(conn, session_id, on_success, on_error)
enddef

export def SessionValue(value: any): dict<any>
  if IsV1()
    return v1.SessionValue(value)
  endif
  return v2.SessionValue(value)
enddef

export def SessionId(value: any): string
  if IsV1()
    return v1.SessionId(value)
  endif
  return v2.SessionId(value)
enddef

export def ListModels(conn: any, on_success: any, on_error: any): number
  if IsV1()
    return v1.ListModels(conn, on_success, on_error)
  endif
  return v2.ListModels(conn, on_success, on_error)
enddef

export def ListProviders(conn: any, on_success: any, on_error: any): number
  if IsV1()
    return v1.ListProviders(conn, on_success, on_error)
  endif
  return v2.ListProviders(conn, on_success, on_error)
enddef

export def ListAgents(conn: any, on_success: any, on_error: any): number
  if IsV1()
    return v1.ListAgents(conn, on_success, on_error)
  endif
  return v2.ListAgents(conn, on_success, on_error)
enddef

export def ListCommands(conn: any, on_success: any, on_error: any): number
  if IsV1()
    return v1.ListCommands(conn, on_success, on_error)
  endif
  return v2.ListCommands(conn, on_success, on_error)
enddef

export def ReplyPermission(conn: any, session_id: string, request_id: string, reply: string, on_success: any, on_error: any): number
  if IsV1()
    return v1.ReplyPermission(conn, session_id, request_id, reply, on_success, on_error)
  endif
  return v2.ReplyPermission(conn, session_id, request_id, reply, on_success, on_error)
enddef

export def ReplyQuestion(conn: any, session_id: string, request_id: string, answer: string, on_success: any, on_error: any): number
  if IsV1()
    return v1.ReplyQuestion(conn, session_id, request_id, answer, on_success, on_error)
  endif
  return v2.ReplyQuestion(conn, session_id, request_id, answer, on_success, on_error)
enddef

export def RunCommand(conn: any, session_id: string, name: string, arguments: string, opts: dict<any>, on_success: any, on_error: any): number
  if IsV1()
    return v1.RunCommand(conn, session_id, name, arguments, opts, on_success, on_error)
  endif
  return v2.RunCommand(conn, session_id, name, arguments, opts, on_success, on_error)
enddef

export def Prompt(conn: any, session_id: string, text: string, on_success: any, on_error: any, opts: dict<any> = {}): number
  if IsV1()
    return v1.Prompt(conn, session_id, text, on_success, on_error, opts)
  endif
  return v2.Prompt(conn, session_id, text, on_success, on_error, opts)
enddef

export def LoadMessages(conn: any, session_id: string, limit: number, on_success: any, on_error: any): number
  if IsV1()
    return v1.LoadMessages(conn, session_id, limit, on_success, on_error)
  endif
  return v2.LoadMessages(conn, session_id, limit, on_success, on_error)
enddef

export def SessionDiff(conn: any, session_id: string, on_success: any, on_error: any): number
  if IsV1()
    return v1.SessionDiff(conn, session_id, on_success, on_error)
  endif
  return v2.SessionDiff(conn, session_id, on_success, on_error)
enddef
