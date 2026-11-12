vim9script

# Shared protocol adapter interface.
#
# Both V1 and V2 adapters expose the same functions so the UI never sees raw
# protocol differences. Each adapter normalizes its wire shapes into the
# shared session/message/event model used by the rest of the plugin.

import autoload 'opencode9/util.vim' as util

# Return true when the adapter can probe a server for protocol information.
export def CanProbe(): bool
  return true
enddef

# Probe a server for protocol information. on_success receives an info dict.
export def Probe(conn: any, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Subscribe to server events. on_event receives normalized event dicts.
export def Subscribe(conn: any, on_event: any, on_error: any, on_close: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Return the server version string from a probe info dict.
export def Version(info: any): string
  return ''
enddef

# Return true when the probe info indicates a healthy server.
export def Healthy(info: any): bool
  return true
enddef

# Return the event type string from a raw event.
export def EventType(event: any): string
  return ''
enddef

# Return the event data payload from a raw event.
export def EventData(event: any): any
  return v:null
enddef

# Resolve the most recent root session for a directory.
export def ResolveSession(conn: any, directory: string, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# List non-archived sessions for a directory, newest first.
export def ListSessions(conn: any, directory: string, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Create a session.
export def CreateSession(conn: any, opts: dict<any>, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Rename a session.
export def RenameSession(conn: any, session_id: string, title: string, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Delete a session.
export def DeleteSession(conn: any, session_id: string, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Interrupt a running session.
export def InterruptSession(conn: any, session_id: string, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Fork a session.
export def ForkSession(conn: any, session_id: string, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Extract a session dict from a single-session response.
export def SessionValue(value: any): dict<any>
  return {}
enddef

# Extract the session id from a single-session response.
export def SessionId(value: any): string
  return ''
enddef

# List models.
export def ListModels(conn: any, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# List providers.
export def ListProviders(conn: any, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# List agents.
export def ListAgents(conn: any, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# List server commands.
export def ListCommands(conn: any, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Reply to a permission request.
export def ReplyPermission(conn: any, session_id: string, request_id: string, reply: string, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Reply to a question request.
export def ReplyQuestion(conn: any, session_id: string, request_id: string, answer: string, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Run a server command in a session.
export def RunCommand(conn: any, session_id: string, name: string, arguments: string, opts: dict<any>, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Send a prompt to a session.
export def Prompt(conn: any, session_id: string, text: string, on_success: any, on_error: any, opts: dict<any> = {}): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Load a page of messages for the transcript panel.
export def LoadMessages(conn: any, session_id: string, limit: number, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

# Load a session diff.
export def SessionDiff(conn: any, session_id: string, on_success: any, on_error: any): number
  Fail(on_error, 'not implemented')
  return 0
enddef

def Fail(on_error: any, message: string)
  if type(on_error) == v:t_func
    call(on_error, [message, -1, 0])
  elseif type(on_error) == v:t_string && on_error !=# ''
    call(on_error, [message, -1, 0])
  endif
enddef
