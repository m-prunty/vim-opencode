vim9script

# Session listing, creation and lifecycle helpers for :Opencode session.
#
# The module keeps a small cache of the sessions for the current directory so
# numeric tokens (`:Opencode session open 2`) and id prefixes resolve without a
# round trip. Network failures are reported through the caller's error handler
# or echoed directly.

import autoload 'vim_opencode/events.vim' as events
import autoload 'vim_opencode/protocol/active.vim' as active
import autoload 'vim_opencode/server.vim' as server
import autoload 'vim_opencode/state.vim' as state
import autoload 'vim_opencode/ui/panel.vim' as panel
import autoload 'vim_opencode/ui/popup.vim' as popup
import autoload 'vim_opencode/util.vim' as util

var cache: list<dict<any>> = []

export def Cached(): list<dict<any>>
  return cache
enddef

export def Current(): string
  return state.SessionId()
enddef

export def Title(session: dict<any>): string
  var title = get(session, 'title', '')
  return type(title) == v:t_string && title !=# '' ? title : '(untitled)'
enddef

export def Format(session: dict<any>, index: number = 0): string
  var id = get(session, 'id', '')
  var marker = id ==# state.SessionId() ? '*' : ' '
  var label = index > 0 ? printf('[%d] ', index) : ''
  return printf('%s %s%s  %s', marker, label, id, Title(session))
enddef

# Refresh the cache. on_success receives the session list.
export def Refresh(on_success: any = v:null, on_error: any = v:null)
  var conn = server.Current()
  if type(conn) == v:t_none
    Fail(on_error, 'not connected; run :Opencode server connect')
    return
  endif
  active.ListSessions(conn, util.Cwd(),
    (sessions: any) => {
      cache = type(sessions) == v:t_list ? sessions : []
      Invoke(on_success, [cache])
    },
    (message: string, exit: number, status: number) => {
      Fail(on_error, message)
    })
enddef

# Resolve a numeric index, full id or unique id prefix against the cache.
export def ResolveToken(token: string): dict<any>
  if token ==# ''
    return {}
  endif
  if token =~# '^\d\+$'
    var index = str2nr(token)
    if index >= 1 && index <= len(cache)
      return cache[index - 1]
    endif
  endif
  for session in cache
    if get(session, 'id', '') ==# token
      return session
    endif
  endfor
  for session in cache
    var id = get(session, 'id', '')
    if id !=# '' && stridx(id, token) == 0
      return session
    endif
  endfor
  return {}
enddef

export def List()
  Refresh((sessions: any) => PrintList(sessions),
    (message: string) => util.EchoError(message))
enddef

def PrintList(sessions: any)
  if type(sessions) != v:t_list || empty(sessions)
    util.EchoInfo('no sessions for ' .. util.Cwd())
    return
  endif
  var lines: list<string> = []
  var index = 1
  for session in sessions
    lines->add(Format(session, index))
    index += 1
  endfor
  var footer = 'Enter pick | C-P preview | C-Q quit'
  popup.Run({
    \ items: lines,
    \ title: 'OpenCode sessions',
    \ border: 'rounded',
    \ width: 70,
    \ height: min([len(lines) + 4, 20]),
    \ callback: (selection: string) => {
      var session = {}
      for s in cache
        if stridx(selection, get(s, 'id', '')) >= 0
          session = s
          break
        endif
      endfor
      if !empty(session)
        OpenSession(session)
      endif
    },
    \ footer: footer,
    \ })
enddef

# Show a popup menu of cached sessions and open the chosen one.
export def Pick()
  Refresh((sessions: any) => ShowPicker(sessions),
    (message: string) => util.EchoError(message))
enddef

def ShowPicker(sessions: any)
  if type(sessions) != v:t_list || empty(sessions)
    util.EchoInfo('no sessions for ' .. util.Cwd())
    return
  endif
  var labels: list<string> = []
  var index = 1
  for session in sessions
    labels->add(Format(session, index))
    index += 1
  endfor
  var footer = 'Enter pick | C-P preview | C-Q quit'
  popup.Run({
    \ items: labels,
    \ title: 'OpenCode sessions',
    \ border: 'rounded',
    \ width: 70,
    \ height: min([len(labels) + 4, 20]),
    \ callback: (selection: string) => {
      var session = {}
      for s in cache
        if stridx(selection, get(s, 'id', '')) >= 0
          session = s
          break
        endif
      endfor
      if !empty(session)
        OpenSession(session)
      endif
    },
    \ footer: footer,
    \ })
enddef

# Open a session by id, numeric index or id prefix. With an empty token, follow
# the most recently updated session for the directory.
export def Open(token: string = '')
  var conn = server.Current()
  if type(conn) == v:t_none
    util.EchoError('not connected; run :Opencode server connect')
    return
  endif
  if token ==# ''
    panel.FollowRecent()
    return
  endif
  var session = ResolveToken(token)
  var id = get(session, 'id', '')
  if id ==# ''
    id = token
  endif
  panel.OpenSession(id)
enddef

# Create a session and show it in the panel. An empty title lets the server
# choose a default.
export def New(title: string = '')
  var conn = server.Current()
  if type(conn) == v:t_none
    util.EchoError('not connected; run :Opencode server connect')
    return
  endif
  var opts: dict<any> = {}
  if title !=# ''
    opts.title = title
  endif
  active.CreateSession(conn, opts,
    (value: any, status: number) => {
      var session = active.SessionValue(value)
      var id = get(session, 'id', '')
      if id ==# ''
        util.EchoError('the server did not return a session id')
        return
      endif
      Refresh()
      panel.OpenSession(id)
      events.EmitLocal('session.created', {sessionID: id, title: Title(session)})
    },
    (message: string, exit: number, status: number) => util.EchoError(message))
enddef

export def Rename(token: string, title: string = '')
  var conn = server.Current()
  if type(conn) == v:t_none
    util.EchoError('not connected; run :Opencode server connect')
    return
  endif
  var session = ResolveToken(token)
  var id = get(session, 'id', '')
  if id ==# ''
    id = token
  endif
  if id ==# ''
    util.EchoError('a session id is required; run :Opencode session list')
    return
  endif
  var new_title = title
  if new_title ==# ''
    new_title = input('New title: ')
    if new_title ==# ''
      return
    endif
  endif
  active.RenameSession(conn, id, new_title,
    (value: any, status: number) => {
      UpdateCachedTitle(id, new_title)
      Refresh()
      events.EmitLocal('session.renamed', {sessionID: id, title: new_title})
      util.EchoInfo('renamed session ' .. id)
    },
    (message: string, exit: number, status: number) => util.EchoError(message))
enddef

export def Delete(token: string, force: bool = false)
  var conn = server.Current()
  if type(conn) == v:t_none
    util.EchoError('not connected; run :Opencode server connect')
    return
  endif
  var session = ResolveToken(token)
  var id = get(session, 'id', '')
  if id ==# ''
    id = token
  endif
  if id ==# ''
    util.EchoError('a session id is required; run :Opencode session list')
    return
  endif
  if !force
    var answer = input('Delete session ' .. id .. '? (y/N) ')
    if tolower(answer) !=# 'y'
      return
    endif
  endif
  active.DeleteSession(conn, id,
    (value: any, status: number) => {
      cache = filter(cache, (_, item: dict<any>) => get(item, 'id', '') !=# id)
      if state.SessionId() ==# id
        state.Reset('')
        Refresh()
      endif
      events.EmitLocal('session.deleted', {sessionID: id})
      util.EchoInfo('deleted session ' .. id)
    },
    (message: string, exit: number, status: number) => util.EchoError(message))
enddef

export def Fork(token: string = '')
  var conn = server.Current()
  if type(conn) == v:t_none
    util.EchoError('not connected; run :Opencode server connect')
    return
  endif
  var id = token
  if id ==# ''
    id = state.SessionId()
  else
    var session = ResolveToken(token)
    if !empty(session)
      id = get(session, 'id', '')
    endif
  endif
  if id ==# ''
    util.EchoError('no session to fork; run :Opencode session open')
    return
  endif
  active.ForkSession(conn, id,
    (value: any, status: number) => {
      var created = active.SessionValue(value)
      var new_id = get(created, 'id', '')
      Refresh()
      if new_id !=# ''
        panel.OpenSession(new_id)
      endif
      events.EmitLocal('session.forked', {sessionID: id, newSessionID: new_id})
      util.EchoInfo(new_id ==# '' ? 'forked session ' .. id : 'forked session ' .. id .. ' into ' .. new_id)
    },
    (message: string, exit: number, status: number) => util.EchoError(message))
enddef

def OpenSession(session: dict<any>)
  var id = get(session, 'id', '')
  if id !=# ''
    Open(id)
  endif
enddef

def UpdateCachedTitle(id: string, title: string)
  for session in cache
    if get(session, 'id', '') ==# id
      session.title = title
      return
    endif
  endfor
enddef

def Fail(on_error: any, message: string)
  if type(on_error) == v:t_func || (type(on_error) == v:t_string && on_error !=# '')
    Invoke(on_error, [message])
  else
    util.EchoError(message)
  endif
enddef

def Invoke(callback: any, args: list<any>)
  if type(callback) == v:t_func
    call(callback, args)
  elseif type(callback) == v:t_string && callback !=# ''
    call(callback, args)
  endif
enddef
