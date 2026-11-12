vim9script

# UI-agnostic event dispatch. Later phases add reducers on top.

import autoload 'opencode9/util.vim' as util

var listeners: list<func> = []

# Register a callback invoked with every decoded event. Listeners must not
# throw; failures are logged and do not stop other listeners.
export def AddListener(Callback: func)
  listeners->add(Callback)
enddef

export def RemoveListener(Callback: func)
  var kept: list<func> = []
  for listener in listeners
    if listener != Callback
      kept->add(listener)
    endif
  endfor
  listeners = kept
enddef

export def ListenerCount(): number
  return len(listeners)
enddef

# Emit a decoded server event to listeners, User autocmds and public state.
export def Emit(event: any)
  var event_type = Type(event)
  g:opencode9_event = event
  g:opencode9_event_type = event_type
  if event_type ==# ''
    util.Log('warn', 'received an event without a type')
    return
  endif

  for listener in listeners
    try
      call(listener, [event])
    catch
      util.Log('error', 'event listener failed: ' .. util.ExceptionText())
    endtry
  endfor

  var pattern = 'OpencodeEvent:' .. event_type
  if exists('#User#' .. pattern)
    execute 'doautocmd <nomodeline> User ' .. pattern
  endif
enddef

# Emit a locally generated status event with a dictionary payload.
export def EmitLocal(event_type: string, data: any)
  Emit({id: '', type: event_type, data: data})
enddef

export def Type(event: any): string
  if type(event) != v:t_dict
    return ''
  endif
  return get(event, 'type', '')
enddef

export def Data(event: any): any
  if type(event) != v:t_dict
    return v:null
  endif
  return get(event, 'data', v:null)
enddef

export def Id(event: any): string
  if type(event) != v:t_dict
    return ''
  endif
  return get(event, 'id', '')
enddef

export def Last(): any
  return get(g:, 'opencode9_event', v:null)
enddef
