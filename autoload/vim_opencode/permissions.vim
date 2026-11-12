vim9script

# Pending permission/question requests and their small, non-blocking UI.

import autoload 'vim_opencode/events.vim' as events
import autoload 'vim_opencode/protocol/active.vim' as active
import autoload 'vim_opencode/server.vim' as server
import autoload 'vim_opencode/state.vim' as state
import autoload 'vim_opencode/ui/popup.vim' as popup
import autoload 'vim_opencode/util.vim' as util

var pending: list<dict<any>> = []
var listener_installed = false

export def Setup()
  if listener_installed
    return
  endif
  listener_installed = true
  events.AddListener(OnEvent)
enddef

export def Pending(): list<dict<any>>
  return pending
enddef

export def Count(): number
  return len(pending)
enddef

export def Add(request: dict<any>): string
  var item = Normalize(request)
  var id = item.id
  Remove(id)
  pending->add(item)
  events.EmitLocal('permission.pending', {requestID: id, kind: item.kind})
  return id
enddef

export def Remove(id: string)
  if id ==# ''
    return
  endif
  var kept: list<dict<any>> = []
  for item in pending
    if item.id !=# id
      kept->add(item)
    endif
  endfor
  pending = kept
enddef

export def Clear()
  pending = []
enddef

export def Current(): dict<any>
  return empty(pending) ? {} : pending[0]
enddef

export def ResolveToken(token: string): dict<any>
  if token ==# ''
    return Current()
  endif
  if token =~# '^\d\+$'
    var index = str2nr(token)
    if index >= 1 && index <= len(pending)
      return pending[index - 1]
    endif
  endif
  for item in pending
    if item.id ==# token || stridx(item.id, token) == 0
      return item
    endif
  endfor
  return {}
enddef

export def Accept(token: string = '')
  Reply(token, 'allow')
enddef

export def Always(token: string = '')
  Reply(token, 'allow', true)
enddef

export def Deny(token: string = '')
  Reply(token, 'deny')
enddef

export def Answer(token: string, answer: string)
  AnswerQuestion(token, answer)
enddef

export def Ask()
  if empty(pending)
    util.EchoInfo('no pending permission or question requests')
    return
  endif
  var labels: list<string> = []
  var index = 1
  for item in pending
    labels->add(printf('[%d] %s: %s', index, item.kind, item.title))
    index += 1
  endfor
  popup.Run({
    \ items: labels,
    \ title: 'OpenCode permissions',
    \ border: 'rounded',
    \ width: 60,
    \ height: min([len(labels) + 4, 15]),
    \ callback: (selection: string) => {
      var choice = 0
      var m = matchstr(selection, '^\\[\(\d\+\)\\]')
      if m !=# ''
        choice = str2nr(substitute(m, '[\\[\]]', '', 'g'))
      endif
      if choice < 1 || choice > len(pending)
        return
      endif
      var item = pending[choice - 1]
      if item.kind ==# 'question'
        var answer = input(item.title .. ': ')
        if answer !=# ''
          AnswerQuestion(item.id, answer)
        endif
      else
        popup.Run({
          \ items: ['Allow once', 'Allow always', 'Deny'],
          \ title: 'Permission: ' .. item.title,
          \ border: 'rounded',
          \ width: 40,
          \ height: 6,
          \ callback: (action: string) => {
            if action ==# 'Allow once'
              Accept(item.id)
            elseif action ==# 'Allow always'
              Always(item.id)
            elseif action ==# 'Deny'
              Deny(item.id)
            endif
          },
          \ })
      endif
    },
    \ })
enddef

def Reply(token: string, action: string, always: bool = false)
  var item = ResolveToken(token)
  if empty(item)
    util.EchoError('no matching pending permission request')
    return
  endif
  var conn = server.Current()
  if type(conn) == v:t_none
    util.EchoError('not connected; run :Opencode server connect')
    return
  endif
  var reply = always ? 'always' : action
  active.ReplyPermission(conn, item.sessionID, item.id, reply,
    (value: any, status: number) => {
      Remove(item.id)
      events.EmitLocal('permission.replied', {requestID: item.id, reply: reply})
      util.EchoInfo('permission ' .. reply .. ': ' .. item.title)
    },
    (message: string, exit: number, code: number) => util.EchoError(message))
enddef

def AnswerQuestion(id: string, answer: string)
  var item = ResolveToken(id)
  if empty(item)
    return
  endif
  var conn = server.Current()
  if type(conn) == v:t_none
    util.EchoError('not connected; run :Opencode server connect')
    return
  endif
  active.ReplyQuestion(conn, item.sessionID, item.id, answer,
    (value: any, status: number) => {
      Remove(item.id)
      events.EmitLocal('question.answered', {requestID: item.id, answer: answer})
    },
    (message: string, exit: number, code: number) => util.EchoError(message))
enddef

def OnEvent(event: any)
  var event_type = get(event, 'type', '')
  if event_type !=# 'permission.asked' && event_type !=# 'question.asked'
    return
  endif
  var data = get(event, 'data', {})
  if type(data) != v:t_dict
    return
  endif
  data.kind = event_type ==# 'question.asked' ? 'question' : 'permission'
  Add(data)
enddef

def Normalize(request: dict<any>): dict<any>
  var item = deepcopy(request)
  var id = GetString(item, 'id')
  if id ==# ''
    id = GetString(item, 'requestID')
  endif
  var session_id = GetString(item, 'sessionID')
  if session_id ==# ''
    session_id = state.SessionId()
  endif
  var title = GetString(item, 'title')
  if title ==# ''
    title = GetString(item, 'permission')
  endif
  if title ==# ''
    title = GetString(item, 'name')
  endif
  if title ==# ''
    title = 'OpenCode request'
  endif
  item.id = id
  item.sessionID = session_id
  item.title = title
  item.kind = GetString(item, 'kind') ==# '' ? 'permission' : item.kind
  return item
enddef

def GetString(dict: dict<any>, key: string): string
  var value = get(dict, key, '')
  return type(value) == v:t_string ? value : ''
enddef
