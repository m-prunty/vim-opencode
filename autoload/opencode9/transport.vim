vim9script

# HTTP and SSE transport built on curl jobs.
#
# Normal requests write the body and response headers to temporary files. The
# SSE stream consumes newline-delimited curl output and dispatches complete
# frames. Callbacks are global functions so Vim's job layer can reach them.

import autoload 'opencode9/util.vim' as util

var next_id = 0
var requests: dict<dict<any>> = {}
var channels: dict<string> = {}
var timers: dict<string> = {}

# Start a JSON request. Returns a request id that can be passed to Close().
export def Request(opts: dict<any>): number
  var id = NextId()
  var key = string(id)
  var timeout = get(opts, 'timeout_ms', 30000)
  var req: dict<any> = {
    id: id,
    key: key,
    kind: 'request',
    url: RequireString(opts, 'url'),
    method: toupper(get(opts, 'method', 'GET')),
    bodyfile: util.TempFile('oc9-body'),
    headerfile: util.TempFile('oc9-headers'),
    out: '',
    err: '',
    timeout_ms: timeout,
    on_success: get(opts, 'on_success', v:null),
    on_error: get(opts, 'on_error', v:null),
    cancelled: false,
    chkey: '',
  }
  requests[key] = req

  var args = BuildArgs(req, opts, false)
  var job = job_start(args, {
    out_cb: 'g:Opencode9TransportOut',
    err_cb: 'g:Opencode9TransportErr',
    exit_cb: 'g:Opencode9TransportExit',
    out_mode: 'nl',
    stoponexit: 'term',
  })
  req.job = job

  if job_status(job) ==# 'fail'
    Finish(key, -1)
    return id
  endif

  req.chkey = ChannelKey(job_getchannel(job))
  channels[req.chkey] = key
  ArmTimer(req, timeout)
  return id
enddef

# Start an SSE stream. on_event receives each decoded event dictionary.
export def Stream(opts: dict<any>): number
  var id = NextId()
  var key = string(id)
  var heartbeat = get(opts, 'heartbeat_ms', 20000)
  var req: dict<any> = {
    id: id,
    key: key,
    kind: 'stream',
    url: RequireString(opts, 'url'),
    method: 'GET',
    bodyfile: '',
    headerfile: '',
    out: '',
    err: '',
    heartbeat_ms: heartbeat,
    sse_data: [],
    on_event: get(opts, 'on_event', v:null),
    on_error: get(opts, 'on_error', v:null),
    on_close: get(opts, 'on_close', v:null),
    cancelled: false,
    chkey: '',
  }
  requests[key] = req

  var args = BuildArgs(req, opts, true)
  var job = job_start(args, {
    out_cb: 'g:Opencode9TransportOut',
    err_cb: 'g:Opencode9TransportErr',
    exit_cb: 'g:Opencode9TransportExit',
    out_mode: 'nl',
    stoponexit: 'term',
  })
  req.job = job

  if job_status(job) ==# 'fail'
    Finish(key, -1)
    return id
  endif

  req.chkey = ChannelKey(job_getchannel(job))
  channels[req.chkey] = key
  ArmTimer(req, heartbeat)
  return id
enddef

# Stop a request or stream without invoking its close callback.
export def Close(id: number)
  var key = string(id)
  if !has_key(requests, key)
    return
  endif
  var req = requests[key]
  req.cancelled = true
  if has_key(req, 'job') && job_status(req.job) ==# 'run'
    job_stop(req.job, 'term')
  endif
  Cleanup(req)
  unlet requests[key]
enddef

# Stop every tracked job. Safe to call on VimLeavePre.
export def CloseAll()
  for key in keys(requests)
    var req = requests[key]
    req.cancelled = true
    if has_key(req, 'job') && job_status(req.job) ==# 'run'
      job_stop(req.job, 'term')
    endif
    Cleanup(req)
  endfor
  requests = {}
  channels = {}
  timers = {}
enddef

export def Count(): number
  return len(requests)
enddef

export def IsActive(id: number): bool
  return has_key(requests, string(id))
enddef

def NextId(): number
  next_id += 1
  return next_id
enddef

def RequireString(opts: dict<any>, key: string): string
  var value = get(opts, key, v:null)
  if type(value) != v:t_string || value ==# ''
    throw 'opencode9 transport: ' .. key .. ' must be a non-empty string'
  endif
  return value
enddef

def BuildArgs(req: dict<any>, opts: dict<any>, stream: bool): list<string>
  var args: list<string> = ['curl', '-sS', '--fail-with-body']
  var method = req.method
  if method !=# 'GET'
    args->add('-X')
    args->add(method)
  endif

  args->add('-H')
  args->add('Content-Type: application/json')
  args->add('-H')
  args->add(stream ? 'Accept: text/event-stream' : 'Accept: application/json')

  if stream
    args->add('-N')
  else
    args->add('-o')
    args->add(req.bodyfile)
    args->add('-D')
    args->add(req.headerfile)
    var timeout = get(opts, 'timeout_ms', req.timeout_ms)
    args->add('--max-time')
    args->add(printf('%.3f', timeout / 1000.0))
  endif

  var username = get(opts, 'username', '')
  var password = get(opts, 'password', '')
  if type(password) == v:t_string && password !=# ''
    args->add('--user')
    args->add((type(username) == v:t_string && username !=# '' ? username : 'opencode') .. ':' .. password)
  endif

  var directory = get(opts, 'directory', '')
  if type(directory) == v:t_string && directory !=# ''
    args->add('-H')
    args->add('x-opencode-directory: ' .. util.UrlEncode(directory))
  endif

  var headers = get(opts, 'headers', {})
  if type(headers) == v:t_dict
    for [name, value] in items(headers)
      if type(name) == v:t_string && type(value) == v:t_string && name !~# '[\r\n]' && value !~# '[\r\n]'
        args->add('-H')
        args->add(name .. ': ' .. value)
      endif
    endfor
  endif

  if has_key(opts, 'body') && type(opts.body) != v:t_none
    var encoded = type(opts.body) == v:t_string ? opts.body : util.JsonEncode(opts.body)
    args->add('-d')
    args->add(encoded)
  endif

  args->add(req.url)
  return args
enddef

def ChannelKey(ch: channel): string
  try
    return string(ch_info(ch).id)
  catch
    return ''
  endtry
enddef

def ArmTimer(req: dict<any>, timeout_ms: number)
  if get(req, 'timer', 0) > 0
    timer_stop(req.timer)
    if has_key(timers, string(req.timer))
      unlet timers[string(req.timer)]
    endif
  endif
  var timer = timer_start(timeout_ms, function('g:Opencode9TransportTimeout'))
  req.timer = timer
  timers[string(timer)] = req.key
enddef

# job callbacks ---------------------------------------------------------------

def g:Opencode9TransportOut(ch: channel, msg: string)
  var key = get(channels, ChannelKey(ch), '')
  if key ==# '' || !has_key(requests, key)
    return
  endif
  var req = requests[key]
  if req.kind ==# 'stream'
    HandleStreamLine(req, msg)
  else
    req.out ..= msg
  endif
enddef

def g:Opencode9TransportErr(ch: channel, msg: string)
  var key = get(channels, ChannelKey(ch), '')
  if key ==# '' || !has_key(requests, key)
    return
  endif
  var req = requests[key]
  if msg !=# ''
    req.err ..= msg .. "\n"
  endif
enddef

def g:Opencode9TransportExit(job: job, status: number)
  var key = get(channels, ChannelKey(job_getchannel(job)), '')
  if key ==# '' || !has_key(requests, key)
    return
  endif
  Finish(key, status)
enddef

def g:Opencode9TransportTimeout(timer: number)
  var timer_key = string(timer)
  var key = get(timers, timer_key, '')
  if key ==# ''
    return
  endif
  unlet timers[timer_key]
  var req = get(requests, key, {})
  if empty(req)
    return
  endif
  if req.kind ==# 'stream'
    Fail(key, 'stream idle timeout after ' .. req.heartbeat_ms .. 'ms')
  else
    Fail(key, 'request timed out after ' .. req.timeout_ms .. 'ms')
  endif
enddef

# stream parsing --------------------------------------------------------------

def HandleStreamLine(req: dict<any>, line: string)
  var text = substitute(line, '\r$', '', '')
  if text ==# ''
    DispatchFrame(req)
    return
  endif
  ArmTimer(req, req.heartbeat_ms)
  if text =~# '^:'
    return
  endif
  if text =~# '^data:'
    req.sse_data->add(substitute(text, '^data: \=', '', ''))
  endif
enddef

def DispatchFrame(req: dict<any>)
  if empty(req.sse_data)
    return
  endif
  var payload = join(req.sse_data, "\n")
  req.sse_data = []
  try
    var event = util.JsonDecode(payload)
    Invoke(req.on_event, [event])
  catch
    Invoke(req.on_error, ['invalid SSE event: ' .. util.ExceptionText() .. ' payload=' .. Truncate(payload, 500), -1, 0])
  endtry
enddef

# completion and cleanup ------------------------------------------------------

def Finish(key: string, exit_status: number)
  var req = get(requests, key, {})
  if empty(req)
    return
  endif

  StopTimer(req)
  if req.chkey !=# '' && has_key(channels, req.chkey)
    unlet channels[req.chkey]
  endif
  unlet requests[key]

  if req.kind ==# 'stream'
    CleanupFiles(req)
    if req.cancelled
      return
    endif
    if exit_status == 0
      Invoke(req.on_close, [])
    else
      Invoke(req.on_error, [FormatError(req, exit_status, 0, ''), exit_status, 0])
    endif
    return
  endif

  var body = ReadBody(req.bodyfile)
  var status = ReadStatus(req.headerfile)
  CleanupFiles(req)

  if exit_status == 0 && status >= 200 && status < 300
    var value: any = v:null
    if body !=# ''
      try
        value = util.JsonDecode(body)
      catch
        Invoke(req.on_error, ['invalid JSON response: ' .. util.ExceptionText(), exit_status, status])
        return
      endtry
    endif
    Invoke(req.on_success, [value, status])
    return
  endif

  Invoke(req.on_error, [FormatError(req, exit_status, status, body), exit_status, status])
enddef

def Fail(key: string, message: string)
  var req = get(requests, key, {})
  if empty(req)
    return
  endif
  req.cancelled = true
  if has_key(req, 'job') && job_status(req.job) ==# 'run'
    job_stop(req.job, 'term')
  endif
  StopTimer(req)
  if req.chkey !=# '' && has_key(channels, req.chkey)
    unlet channels[req.chkey]
  endif
  CleanupFiles(req)
  unlet requests[key]
  Invoke(req.on_error, [message, -1, 0])
enddef

def StopTimer(req: dict<any>)
  var timer = get(req, 'timer', 0)
  if timer > 0
    timer_stop(timer)
    if has_key(timers, string(timer))
      unlet timers[string(timer)]
    endif
  endif
enddef

def Cleanup(req: dict<any>)
  StopTimer(req)
  if req.chkey !=# '' && has_key(channels, req.chkey)
    unlet channels[req.chkey]
  endif
  CleanupFiles(req)
enddef

def CleanupFiles(req: dict<any>)
  for file in [get(req, 'bodyfile', ''), get(req, 'headerfile', '')]
    if type(file) == v:t_string && file !=# '' && filereadable(file)
      try
        delete(file)
      catch
        # Temporary-file cleanup must not mask the original result.
      endtry
    endif
  endfor
enddef

def ReadBody(file: string): string
  if file ==# '' || !filereadable(file)
    return ''
  endif
  return join(readfile(file), "\n")
enddef

def ReadStatus(file: string): number
  if file ==# '' || !filereadable(file)
    return 0
  endif
  var status = 0
  for line in readfile(file)
    var match = matchlist(line, '^HTTP/\S\+\s\+\(\d\+\)')
    if !empty(match)
      status = str2nr(match[1])
    endif
  endfor
  return status
enddef

export def FormatError(req: dict<any>, exit_status: number, status: number, body: string): string
  var lines: list<string> = [req.method .. ' ' .. req.url .. ' failed']
  lines->add('curl exit: ' .. exit_status)
  if status > 0
    lines->add('HTTP status: ' .. status)
  endif
  if body !=# ''
    lines->add('response: ' .. Truncate(body, 2000))
  endif
  if req.err !=# ''
    lines->add('stderr: ' .. Truncate(req.err, 2000))
  endif
  return join(lines, "\n")
enddef

export def Truncate(value: string, limit: number): string
  if strlen(value) <= limit
    return value
  endif
  return strpart(value, 0, limit) .. '...'
enddef

def Invoke(callback: any, args: list<any>)
  if type(callback) == v:t_func
    call(callback, args)
  elseif type(callback) == v:t_string && callback !=# ''
    call(callback, args)
  endif
enddef
