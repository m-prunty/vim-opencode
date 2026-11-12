vim9script

# P1 headless smoke test for transport, discovery and the server connection.

import autoload 'vim_opencode/config.vim' as config
import autoload 'vim_opencode/discovery.vim' as discovery
import autoload 'vim_opencode/health.vim' as health
import autoload 'vim_opencode/server.vim' as server
import autoload 'vim_opencode/transport.vim' as transport
import autoload 'vim_opencode/util.vim' as util

const PORT = '18767'
const BASE = 'http://127.0.0.1:' .. PORT

var failures: list<string> = []
var script_dir = fnamemodify(expand('<sfile>'), ':p:h')
var result_dir = script_dir .. '/results'

var info_value: any = v:null
var info_status = 0
var error_message = ''
var error_status = 0
var echo_value: any = v:null
var stream_events: list<string> = []
var connected: any = v:null
var discovery_error = ''

def Check(condition: bool, message: string)
  if !condition
    failures->add(message)
  endif
enddef

def InfoOk(value: any, status: number)
  info_value = value
  info_status = status
enddef

def RequestErr(message: string, exit: number, status: number)
  error_message = message
  error_status = status
enddef

def EchoOk(value: any, status: number)
  echo_value = value
enddef

def StreamEvent(event: any)
  stream_events->add(get(event, 'type', ''))
enddef

def StreamErr(message: string, exit: number, status: number)
  failures->add('stream error: ' .. message)
enddef

def DiscOk(conn: any, info: any)
  connected = conn
enddef

def DiscErr(message: string)
  discovery_error = message
enddef

var fixture_job: any = v:null

try
  config.Setup({request_timeout_ms: 3000, connect_timeout_ms: 3000})

  fixture_job = job_start(['python3', script_dir .. '/fixtures/server.py', PORT])
  sleep 400m

  if job_status(fixture_job) !=# 'run'
    failures->add('fixture server did not start')
  else
    # Ordinary GET request and JSON decoding.
    transport.Request({
      url: BASE .. '/api/info',
      method: 'GET',
      timeout_ms: 3000,
      on_success: InfoOk,
      on_error: RequestErr,
    })
    sleep 1
    Check(info_status == 200, 'info request did not return 200')
    Check(type(info_value) == v:t_dict && get(info_value, 'version', '') ==# '2.0.0', 'info version is wrong')

    # HTTP error mapping keeps the status and body.
    transport.Request({
      url: BASE .. '/api/error',
      method: 'GET',
      timeout_ms: 3000,
      on_success: InfoOk,
      on_error: RequestErr,
    })
    sleep 1
    Check(error_status == 400, 'error request did not report HTTP 400')
    Check(stridx(error_message, 'bad request') >= 0, 'error body was not included')

    # JSON POST body round trip.
    transport.Request({
      url: BASE .. '/api/echo',
      method: 'POST',
      body: {text: 'hello'},
      timeout_ms: 3000,
      on_success: EchoOk,
      on_error: RequestErr,
    })
    sleep 1
    Check(type(echo_value) == v:t_dict && get(echo_value, 'text', '') ==# 'hello', 'POST body round trip failed')

    # SSE frame parsing.
    var stream_id = transport.Stream({
      url: BASE .. '/api/event',
      heartbeat_ms: 5000,
      on_event: StreamEvent,
      on_error: StreamErr,
      on_close: () => stream_events->add('closed'),
    })
    sleep 1
    Check(index(stream_events, 'server.connected') >= 0, 'SSE server.connected event was not parsed')
    Check(index(stream_events, 'session.status') >= 0, 'SSE session.status event was not parsed')
    transport.Close(stream_id)
    Check(transport.Count() == 0, 'stream close left a tracked transport job')

    # Discovery through a configured URL and connection lifecycle.
    config.Setup({server_url: BASE, request_timeout_ms: 3000})
    discovery.Connect({on_success: DiscOk, on_error: DiscErr})
    sleep 1
    Check(discovery_error ==# '', 'discovery reported an error')
    Check(type(connected) != v:t_none, 'discovery did not return a connection')
    Check(server.Current() is connected, 'discovery did not make the connection current')
    Check(server.Status().version ==# '2.0.0', 'discovery did not record the server version')

    server.Disconnect(connected)
    Check(type(server.Current()) == v:t_none, 'disconnect did not clear the current connection')

    # Health sees the modules added in this phase.
    var report = join(health.Report(), "\n")
    Check(report =~# 'transport: available', 'health did not find transport')
    Check(report =~# 'discovery: available', 'health did not find discovery')
  endif
catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

transport.CloseAll()
if type(fixture_job) != v:t_none && job_status(fixture_job) ==# 'run'
  job_stop(fixture_job, 'term')
endif

if isdirectory(result_dir) == 0
  mkdir(result_dir, 'p')
endif

if empty(failures)
  writefile(['P1 smoke test passed'], result_dir .. '/p1.txt')
  qa!
else
  writefile(failures, result_dir .. '/p1.txt')
  execute 'cquit 1'
endif
