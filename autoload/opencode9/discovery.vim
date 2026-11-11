vim9script

# Server discovery and reconnecting V2 subscriptions.
#
# Order: configured URL, OpenCode background registrations (newest first),
# then an optional configured start command followed by polling.

import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/events.vim' as events
import autoload 'opencode9/protocol/v2.vim' as v2
import autoload 'opencode9/server.vim' as server
import autoload 'opencode9/util.vim' as util

const POLL_INTERVAL_MS = 500
const POLL_ATTEMPTS = 10

var poll_timer = 0
var poll_attempts = 0
var poll_callbacks: dict<any> = {}
var start_job: any = v:null

# Return OpenCode's state directory using the same XDG fallback it uses.
export def StateDir(): string
  var state_home = $XDG_STATE_HOME
  if state_home !=# ''
    return util.NormalizePath(state_home .. '/opencode')
  endif
  var home = $HOME
  if home ==# ''
    home = expand('~')
  endif
  return util.NormalizePath(home .. '/.local/state/opencode')
enddef

# Read service registrations, newest first.
export def Registrations(): list<dict<any>>
  var directory = StateDir()
  if !isdirectory(directory)
    return []
  endif

  var candidates: list<dict<any>> = []
  for path in glob(directory .. '/service*.json', true, true)
    var name = fnamemodify(path, ':t')
    if name !=# 'service.json' && name !~# '^service-.*\.json$'
      continue
    endif
    var registration = ReadRegistration(path)
    if type(registration) == v:t_none
      continue
    endif
    registration.name = name
    registration.mtime = getftime(path)
    registration.path = path
    candidates->add(registration)
  endfor

  sort(candidates, (a: dict<any>, b: dict<any>): number => CompareRegistrations(a, b))
  return candidates
enddef

def ReadRegistration(path: string): any
  try
    var text = join(readfile(path), "\n")
    var decoded = util.JsonDecode(text)
    if type(decoded) != v:t_dict
      return v:null
    endif
    var url = get(decoded, 'url', '')
    if type(url) != v:t_string || url ==# ''
      return v:null
    endif
    return {
      url: url,
      username: get(decoded, 'username', 'opencode'),
      password: get(decoded, 'password', ''),
      pid: get(decoded, 'pid', 0),
      version: get(decoded, 'version', ''),
    }
  catch
    return v:null
  endtry
enddef

def CompareRegistrations(a: dict<any>, b: dict<any>): number
  if a.mtime != b.mtime
    return a.mtime > b.mtime ? -1 : 1
  endif
  var a_default = a.name ==# 'service.json'
  var b_default = b.name ==# 'service.json'
  if a_default != b_default
    return a_default ? -1 : 1
  endif
  return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
enddef

# Return the configured server URL as a candidate, or v:null.
export def Configured(): any
  var cfg = config.Get()
  if type(cfg.server_url) != v:t_string || cfg.server_url ==# ''
    return v:null
  endif
  return {
    url: cfg.server_url,
    username: get(cfg.server, 'username', 'opencode'),
    password: get(cfg.server, 'password', ''),
  }
enddef

export def HasStartCommand(): bool
  var command = config.Get().server_command
  if type(command) == v:t_string
    return command !=# ''
  endif
  return type(command) == v:t_list && !empty(command)
enddef

# Start the configured OpenCode server command without waiting for it.
export def Start(on_error: any): bool
  if !HasStartCommand()
    Invoke(on_error, ['server_command is empty; cannot start a server'])
    return false
  endif

  var command = config.Get().server_command
  try
    start_job = job_start(command)
  catch
    Invoke(on_error, ['failed to start server: ' .. util.ExceptionText()])
    return false
  endtry

  if job_status(start_job) ==# 'fail'
    Invoke(on_error, ['failed to start server command'])
    start_job = v:null
    return false
  endif
  g:opencode9_server_job = start_job
  return true
enddef

export def StopStarted()
  if type(start_job) != v:t_none && job_status(start_job) ==# 'run'
    job_stop(start_job, 'term')
  endif
  start_job = v:null
  if exists('g:opencode9_server_job')
    unlet g:opencode9_server_job
  endif
enddef

# Discover, probe and subscribe. callbacks: on_success(conn, info), on_error(msg).
export def Connect(callbacks: dict<any>)
  var configured = Configured()
  if type(configured) != v:t_none
    # A configured URL is authoritative: never start a different server.
    TryCandidates([configured], 0, callbacks, false)
    return
  endif

  var registrations = Registrations()
  if !empty(registrations)
    TryCandidates(registrations, 0, callbacks, false)
    return
  endif

  if !HasStartCommand()
    Invoke(get(callbacks, 'on_error', v:null), ['no OpenCode server found and server_command is empty'])
    return
  endif

  if !Start(get(callbacks, 'on_error', v:null))
    return
  endif
  BeginPoll(callbacks)
enddef

def TryCandidates(candidates: list<dict<any>>, index: number, callbacks: dict<any>, polling: bool)
  if index >= len(candidates)
    if polling
      SchedulePoll(callbacks)
    else
      Invoke(get(callbacks, 'on_error', v:null), ['failed to connect to any OpenCode server'])
    endif
    return
  endif

  var candidate = candidates[index]
  var cfg = config.Get()
  var conn = server.New(candidate.url, {
    username: get(candidate, 'username', get(cfg.server, 'username', 'opencode')),
    password: get(candidate, 'password', get(cfg.server, 'password', '')),
    directory: cfg.directory,
    timeout_ms: cfg.request_timeout_ms,
    reconnect_delay_ms: cfg.reconnect_delay_ms,
    max_reconnect_delay_ms: cfg.max_reconnect_delay_ms,
  })

  v2.Probe(conn,
    (info: any, status: number) => CandidateSucceeded(conn, info, callbacks),
    (message: string, exit: number, status: number) => TryCandidates(candidates, index + 1, callbacks, polling))
enddef

def CandidateSucceeded(conn: any, info: any, callbacks: dict<any>)
  StopPoll()
  conn.SetInfo(type(info) == v:t_dict ? info : {})
  conn.SetConnected(true)
  conn.ResetReconnect()
  server.SetCurrent(conn)
  Subscribe(conn)
  Invoke(get(callbacks, 'on_success', v:null), [conn, info])
enddef

def Subscribe(conn: any)
  v2.Subscribe(conn,
    (event: any) => OnEvent(conn, event),
    (message: string, exit: number, status: number) => OnStreamError(conn, message),
    () => OnStreamClose(conn))
enddef

def OnEvent(conn: any, event: any)
  var event_type = events.Type(event)
  if event_type ==# 'server.connected'
    conn.SetConnected(true)
    conn.ResetReconnect()
  elseif event_type ==# 'global.disposed' || event_type ==# 'server.instance.disposed'
    server.Disconnect(conn)
  endif
  events.Emit(event)
enddef

def OnStreamError(conn: any, message: string)
  conn.SetConnected(false)
  if IsCurrent(conn) && conn.reconnect_enabled
    ScheduleReconnect(conn)
  endif
  events.EmitLocal('server.disconnected', {message: message})
  util.Log('warn', 'stream disconnected: ' .. FirstLine(message))
enddef

def OnStreamClose(conn: any)
  if IsCurrent(conn) && conn.reconnect_enabled
    ScheduleReconnect(conn)
  endif
enddef

def ScheduleReconnect(conn: any)
  var timer = conn.ReconnectTimer()
  if timer > 0
    timer_stop(timer)
  endif
  var delay = conn.NextReconnectDelay()
  conn.SetReconnectTimer(timer_start(delay, (t: number) => RetrySubscribe(conn)))
  util.Log('info', printf('reconnecting to %s in %dms', conn.Url(), delay))
enddef

def RetrySubscribe(conn: any)
  conn.SetReconnectTimer(0)
  if IsCurrent(conn) && conn.reconnect_enabled
    Subscribe(conn)
  endif
enddef

def BeginPoll(callbacks: dict<any>)
  poll_attempts = 0
  poll_callbacks = callbacks
  poll_timer = timer_start(POLL_INTERVAL_MS, (t: number) => PollTick())
enddef

def PollTick()
  poll_timer = 0
  poll_attempts += 1
  var registrations = Registrations()
  if !empty(registrations)
    TryCandidates(registrations, 0, poll_callbacks, true)
  else
    SchedulePoll(poll_callbacks)
  endif
enddef

def SchedulePoll(callbacks: dict<any>)
  if poll_attempts >= POLL_ATTEMPTS
    var failed = poll_callbacks
    StopPoll()
    Invoke(get(failed, 'on_error', v:null), ['timed out waiting for an OpenCode server'])
    return
  endif
  poll_callbacks = callbacks
  poll_timer = timer_start(POLL_INTERVAL_MS, (t: number) => PollTick())
enddef

def StopPoll()
  if poll_timer > 0
    timer_stop(poll_timer)
    poll_timer = 0
  endif
  poll_callbacks = {}
enddef

def FirstLine(value: string): string
  return matchstr(value, '^[^\n]*')
enddef

def IsCurrent(conn: any): bool
  var current = server.Current()
  return type(current) != v:t_none && current is conn
enddef

def Invoke(callback: any, args: list<any>)
  if type(callback) == v:t_func
    call(callback, args)
  elseif type(callback) == v:t_string && callback !=# ''
    call(callback, args)
  endif
enddef
