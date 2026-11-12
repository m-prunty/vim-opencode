vim9script

# P5 smoke test for permission/question state and V2 replies.

import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/discovery.vim' as discovery
import autoload 'opencode9/events.vim' as events
import autoload 'opencode9/permissions.vim' as permissions
import autoload 'opencode9/server.vim' as server
import autoload 'opencode9/state.vim' as state
import autoload 'opencode9/transport.vim' as transport
import autoload 'opencode9/util.vim' as util

const PORT = '18772'
const BASE = 'http://127.0.0.1:' .. PORT
var failures: list<string> = []
var script_dir = fnamemodify(expand('<sfile>'), ':p:h')
var connected: any = v:null
var replies: any = v:null
var questions: any = v:null
var job: any = v:null

def Check(condition: bool, message: string)
  if !condition
    failures->add(message)
  endif
enddef

def WaitFor(Predicate: func)
  var count = 0
  while count < 100 && !Predicate()
    sleep 30m
    count += 1
  endwhile
enddef

def OnConnected(conn: any, info: any)
  connected = conn
enddef

def OnError(message: string)
  failures->add(message)
enddef

def RepliesOk(value: any, status: number)
  replies = value
enddef

def QuestionsOk(value: any, status: number)
  questions = value
enddef

try
  config.Setup({server_url: BASE, request_timeout_ms: 3000})
  state.Reset('s1')
  permissions.Clear()
  permissions.Setup()
  job = job_start(['python3', script_dir .. '/fixtures/server.py', PORT])
  sleep 400m
  discovery.Connect({on_success: OnConnected, on_error: OnError})
  WaitFor(() => type(connected) != v:t_none)
  Check(type(connected) != v:t_none, 'fixture server did not connect')

  # Event normalization supports both permission and question requests.
  events.Emit({type: 'permission.asked', data: {sessionID: 's1', id: 'p1', permission: 'edit'}})
  events.Emit({type: 'question.asked', data: {sessionID: 's1', id: 'q1', title: 'Which file?'}})
  Check(permissions.Count() == 2, 'two pending requests should be tracked')
  Check(permissions.ResolveToken('1').id ==# 'p1', 'numeric permission token failed')
  Check(permissions.ResolveToken('q').kind ==# 'question', 'question token failed')

  permissions.Accept('p1')
  WaitFor(() => permissions.Count() == 1)
  Check(permissions.Count() == 1, 'accepted permission should be removed')
  permissions.Answer('q1', 'src/main.vim')
  WaitFor(() => permissions.Count() == 0)
  Check(permissions.Count() == 0, 'denied question should be removed')

  transport.Request({url: BASE .. '/api/permission_replies', method: 'GET', timeout_ms: 3000, on_success: RepliesOk, on_error: OnError})
  transport.Request({url: BASE .. '/api/question_replies', method: 'GET', timeout_ms: 3000, on_success: QuestionsOk, on_error: OnError})
  WaitFor(() => type(replies) != v:t_none && type(questions) != v:t_none)
  var reply_list = type(replies) == v:t_dict ? get(replies, 'data', []) : replies
  var question_list = type(questions) == v:t_dict ? get(questions, 'data', []) : questions
  Check(type(reply_list) == v:t_list && len(reply_list) == 1, 'permission reply should reach server')
  if type(reply_list) == v:t_list && len(reply_list) == 1
    Check(reply_list[0].reply ==# 'allow', 'permission reply should allow')
  endif
  Check(type(question_list) == v:t_list && len(question_list) == 1, 'question reply should reach server')
  if type(question_list) == v:t_list && len(question_list) == 1
    Check(question_list[0].answer ==# 'src/main.vim', 'question answer should reach server')
  endif

catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

server.Shutdown()
transport.CloseAll()
if type(job) != v:t_none && job_status(job) ==# 'run'
  job_stop(job, 'term')
endif

if empty(failures)
  writefile(['P5 smoke test passed'], 'test/results/p5.txt')
  qa!
else
  writefile(failures, 'test/results/p5.txt')
  execute 'cquit 1'
endif
