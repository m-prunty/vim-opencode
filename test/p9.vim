vim9script

# P9 smoke test: V1 adapter normalization shapes.

import autoload 'opencode9/protocol/adapter.vim' as adapter
import autoload 'opencode9/protocol/v1.vim' as v1
import autoload 'opencode9/util.vim' as util

var failures: list<string> = []
var result_dir = 'test/results'

def Check(condition: bool, message: string)
  if !condition
    failures->add(message)
  endif
enddef

try
  # Adapter interface exposes all required functions.
  var fn_names = [
    'Probe', 'Subscribe', 'Version', 'Healthy',
    'EventType', 'EventData', 'ResolveSession', 'ListSessions',
    'CreateSession', 'RenameSession', 'DeleteSession', 'InterruptSession',
    'ForkSession', 'SessionValue', 'SessionId',
    'ListModels', 'ListProviders', 'ListAgents', 'ListCommands',
    'ReplyPermission', 'ReplyQuestion', 'RunCommand', 'Prompt',
    'LoadMessages', 'SessionDiff',
  ]
  for name in fn_names
    Check(function('adapter.' .. name) != v:null, 'adapter exposes ' .. name)
  endfor

  # V1 NormalizeInfo normalizes health responses.
  var info = v1.NormalizeInfo({version: '1.0.0', healthy: true})
  Check(info.version ==# '1.0.0', 'V1 NormalizeInfo preserves version')
  Check(info.healthy == v:true, 'V1 NormalizeInfo preserves healthy')

  # V1 NormalizeEvent maps permission.requested -> permission.asked.
  var event = v1.NormalizeEvent({type: 'permission.requested', data: {sessionID: 's1', id: 'p1', permission: 'edit'}})
  Check(event.type ==# 'permission.asked', 'V1 NormalizeEvent maps permission.requested to permission.asked')

  # V1 NormalizeEvent maps question.requested -> question.asked.
  event = v1.NormalizeEvent({type: 'question.requested', data: {sessionID: 's1', id: 'q1', title: 'Which file?'}})
  Check(event.type ==# 'question.asked', 'V1 NormalizeEvent maps question.requested to question.asked')

  # V1 NormalizeSession normalizes session id alias.
  var session = v1.NormalizeSession({sessionID: 's1', title: 'Test', archived: 0})
  Check(session.id ==# 's1', 'V1 NormalizeSession maps sessionID to id')

  # V1 IsArchived.
  Check(v1.IsArchived({archived: 0}) == v:false, 'V1 IsArchived(0) is false')
  Check(v1.IsArchived({archived: 1}) == v:true, 'V1 IsArchived(1) is true')

catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

if isdirectory(result_dir) == 0
  mkdir(result_dir, 'p')
endif

if empty(failures)
  writefile(['P9 smoke test passed'], result_dir .. '/p9.txt')
  qa!
else
  writefile(failures, result_dir .. '/p9.txt')
  execute 'cquit 1'
endif
