vim9script

# Connection state and lifecycle for an OpenCode server.

import autoload 'vim_opencode/transport.vim' as transport
import autoload 'vim_opencode/util.vim' as util

export class Connection
  var url: string
  var username: string
  var password: string
  var directory: string
  var headers: dict<string>
  var timeout_ms: number
  var version: string
  var info: dict<any>
  var stream_id: number
  var connected: bool
  var reconnect_enabled: bool
  var reconnect_initial: number
  var reconnect_delay: number
  var reconnect_max: number
  var reconnect_timer: number

  def new(url: string, opts: dict<any>)
    this.url = substitute(url, '/\+$', '', '')
    var username = get(opts, 'username', '')
    this.username = username ==# '' ? 'opencode' : username
    this.password = get(opts, 'password', '')
    var directory = get(opts, 'directory', '')
    this.directory = directory ==# '' ? util.Cwd() : util.NormalizePath(directory)
    this.headers = deepcopy(get(opts, 'headers', {}))
    this.timeout_ms = get(opts, 'timeout_ms', 30000)
    this.version = ''
    this.info = {}
    this.stream_id = 0
    this.connected = false
    this.reconnect_enabled = true
    this.reconnect_initial = get(opts, 'reconnect_delay_ms', 1000)
    this.reconnect_delay = this.reconnect_initial
    this.reconnect_max = get(opts, 'max_reconnect_delay_ms', 30000)
    this.reconnect_timer = 0
  enddef

  def Url(): string
    return this.url
  enddef

  def Version(): string
    return this.version
  enddef

  def Info(): dict<any>
    return this.info
  enddef

  def SetInfo(value: dict<any>)
    this.info = value
    this.version = get(value, 'version', '')
  enddef

  def IsConnected(): bool
    return this.connected
  enddef

  def SetConnected(value: bool)
    this.connected = value
  enddef

  def Request(path: string, method: string, body: any, on_success: any, on_error: any): number
    var opts: dict<any> = {
      url: this.url .. path,
      method: method,
      body: body,
      username: this.username,
      password: this.password,
      directory: this.directory,
      headers: this.headers,
      timeout_ms: this.timeout_ms,
      on_success: on_success,
      on_error: on_error,
    }
    return transport.Request(opts)
  enddef

  def Stream(path: string, callbacks: dict<any>): number
    var opts: dict<any> = {
      url: this.url .. path,
      username: this.username,
      password: this.password,
      directory: this.directory,
      headers: this.headers,
      heartbeat_ms: get(callbacks, 'heartbeat_ms', 20000),
      on_event: get(callbacks, 'on_event', v:null),
      on_error: get(callbacks, 'on_error', v:null),
      on_close: get(callbacks, 'on_close', v:null),
    }
    this.stream_id = transport.Stream(opts)
    return this.stream_id
  enddef

  def CloseStream()
    if this.stream_id > 0
      transport.Close(this.stream_id)
    endif
    this.stream_id = 0
    this.connected = false
  enddef

  def SetReconnect(enabled: bool)
    this.reconnect_enabled = enabled
  enddef

  def ResetReconnect()
    this.reconnect_delay = this.reconnect_initial
  enddef

  def NextReconnectDelay(): number
    var delay = this.reconnect_delay
    this.reconnect_delay = min([this.reconnect_delay * 2, this.reconnect_max])
    return delay
  enddef

  def ReconnectTimer(): number
    return this.reconnect_timer
  enddef

  def SetReconnectTimer(timer: number)
    this.reconnect_timer = timer
  enddef
endclass

var current: any = v:null

export def New(url: string, opts: dict<any>): any
  return Connection.new(url, opts)
enddef

export def Current(): any
  return current
enddef

export def SetCurrent(conn: any)
  current = conn
  g:vim_opencode_connection = conn
enddef

export def ClearCurrent()
  current = v:null
  if exists('g:vim_opencode_connection')
    unlet g:vim_opencode_connection
  endif
enddef

# Stop reconnecting, close the stream and clear the active connection.
export def Disconnect(conn: any)
  if type(conn) == v:t_none
    return
  endif
  conn.SetReconnect(false)
  var timer = conn.ReconnectTimer()
  if timer > 0
    timer_stop(timer)
    conn.SetReconnectTimer(0)
  endif
  conn.CloseStream()
  if type(current) != v:t_none && current is conn
    ClearCurrent()
  endif
enddef

# Stop every connection and pending transport job. Used by VimLeavePre.
export def Shutdown()
  var conn = current
  if type(conn) != v:t_none
    Disconnect(conn)
  endif
  ClearCurrent()
  transport.CloseAll()
enddef

export def Status(): dict<any>
  if type(current) == v:t_none
    return {connected: false, url: '', version: '', directory: ''}
  endif
  return {
    connected: current.IsConnected(),
    url: current.Url(),
    version: current.Version(),
    directory: current.directory,
  }
enddef
