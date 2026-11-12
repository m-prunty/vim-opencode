vim9script

# Transcript state for the split panel.
#
# The model stores ordered messages with stable content parts. It accepts both
# the V2 delta events used by the OpenCode server and the snapshot/part shapes
# returned by the HTTP API, so the renderer never has to know the wire format.

import autoload 'opencode9/util.vim' as util

var session_id = ''
var model = ''
var messages: list<dict<any>> = []
var index: dict<number> = {}
var version = 0
var optimistic_seq = 0
var listeners: list<func> = []

export def SessionId(): string
  return session_id
enddef

export def Model(): string
  return model
enddef

export def Version(): number
  return version
enddef

# Live message list. Callers must not reorder it; the renderer only reads.
export def Messages(): list<dict<any>>
  return messages
enddef

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

export def Status(): dict<any>
  return {
    sessionID: session_id,
    version: version,
    messages: len(messages),
  }
enddef

# Forget everything and optionally start a new session.
export def Reset(new_session: string = '')
  session_id = new_session
  model = ''
  messages = []
  index = {}
  Touch()
enddef

# Reset only when the session actually changes.
export def EnsureSession(new_session: string): bool
  if new_session ==# '' || new_session ==# session_id
    return false
  endif
  Reset(new_session)
  return true
enddef

export def Clear()
  Reset(session_id)
enddef

# Replace the transcript with a snapshot from GET /api/session/{id}/message.
export def Snapshot(new_session: string, items: any)
  Reset(new_session)
  var source = items
  if type(source) == v:t_dict
    source = get(source, 'data', [])
  endif
  if type(source) != v:t_list
    return
  endif
  for item in source
    if type(item) == v:t_dict
      IngestMessage(item)
    endif
  endfor
  Touch()
enddef

# Append a locally sent user message before the server echoes it.
export def AddUser(new_session: string, text: string)
  if session_id ==# ''
    session_id = new_session
  elseif new_session !=# '' && new_session !=# session_id
    Reset(new_session)
  endif
  DropOptimistic(text)
  optimistic_seq += 1
  var message = EnsureMessage('optimistic:' .. optimistic_seq, 'user')
  message.text = text
  message.optimistic = true
  Touch()
enddef

export def AddNotice(new_session: string, text: string, description: string = '')
  if session_id ==# '' && new_session !=# ''
    session_id = new_session
  endif
  optimistic_seq += 1
  var message = EnsureMessage('notice:' .. optimistic_seq, 'synthetic')
  message.text = text
  message.description = description
  Touch()
enddef

# Apply one decoded server event. Returns true when the transcript changed.
export def Apply(event: any): bool
  if type(event) != v:t_dict
    return false
  endif
  var event_type = get(event, 'type', '')
  var data: any = get(event, 'data', {})
  if type(data) != v:t_dict
    return false
  endif

  # Session-scoped message events. Session status and lifecycle events carry a
  # sessionID too, but do not touch the transcript.
  var event_session = get(data, 'sessionID', '')
  if type(event_session) != v:t_string
    event_session = ''
  endif
  if event_session !=# ''
    if session_id ==# ''
      session_id = event_session
    elseif event_session !=# session_id
      return false
    endif
  endif

  if event_type ==# 'session.step.started'
    var assistant = EnsureMessage(GetString(data, 'assistantMessageID'), 'assistant')
    assistant.agent = GetString(data, 'agent')
    assistant.model = get(data, 'model', v:null)
    var m = get(data, 'model', v:null)
    if type(m) == v:t_string && m !=# ''
      model = m
    endif
  elseif event_type ==# 'session.text.started' || event_type ==# 'session.text.delta' || event_type ==# 'session.text.ended'
    ApplyOrdinal(data, 'text', event_type)
  elseif event_type ==# 'session.reasoning.started' || event_type ==# 'session.reasoning.delta' || event_type ==# 'session.reasoning.ended'
    ApplyOrdinal(data, 'reasoning', event_type)
  elseif event_type ==# 'session.tool.input.started'
    ApplyToolStart(data)
  elseif event_type ==# 'session.tool.input.delta'
    ApplyToolInput(data, true)
  elseif event_type ==# 'session.tool.input.ended'
    ApplyToolInput(data, false)
  elseif event_type ==# 'session.tool.called'
    ApplyToolCalled(data)
  elseif event_type ==# 'session.tool.progress'
    var progress = FindTool(data)
    if type(progress) != v:t_none
      progress.metadata = get(data, 'metadata', v:null)
    endif
  elseif event_type ==# 'session.tool.success' || event_type ==# 'session.tool.failed'
    ApplyToolFinished(data, event_type ==# 'session.tool.success')
  elseif event_type ==# 'session.step.ended' || event_type ==# 'session.step.failed'
    ApplyStepFinished(data, event_type ==# 'session.step.failed')
  elseif event_type ==# 'session.inbox.enqueued'
    ApplyInbox(data)
  elseif event_type ==# 'session.synthetic'
    ApplySynthetic(event, data)
  elseif event_type ==# 'session.instructions.updated'
    AddNotice(session_id, GetString(data, 'text'), 'Instructions updated')
  elseif event_type ==# 'session.revert.committed'
    ApplyRevert(data)
  elseif event_type ==# 'message.updated'
    ApplyMessageUpdated(event)
  elseif event_type ==# 'message.removed'
    ApplyMessageRemoved(event)
  elseif event_type ==# 'message.part.updated'
    ApplyPartUpdated(event)
  elseif event_type ==# 'message.part.delta'
    ApplyPartDelta(event)
  elseif event_type ==# 'message.part.removed'
    ApplyPartRemoved(event)
  else
    return false
  endif

  Touch()
  return true
enddef

# ---------------------------------------------------------------------------
# V2 delta events

def ApplyOrdinal(data: dict<any>, kind: string, event_type: string)
  var message = EnsureMessage(GetString(data, 'assistantMessageID'), 'assistant')
  var ordinal = get(data, 'ordinal', 0)
  if type(ordinal) != v:t_number
    ordinal = 0
  endif
  var part = EnsurePart(message, kind .. ':' .. message.id .. ':' .. ordinal, kind)
  if event_type =~# '\.delta$'
    part.text ..= GetString(data, 'delta')
  elseif event_type =~# '\.ended$'
    part.text = GetString(data, 'text')
  elseif type(get(part, 'time', v:null)) == v:t_none
    part.time = {}
  endif
enddef

def ApplyToolStart(data: dict<any>)
  var message = EnsureMessage(GetString(data, 'assistantMessageID'), 'assistant')
  var call_id = GetString(data, 'id')
  var part = EnsurePart(message, 'tool:' .. message.id .. ':' .. call_id, 'tool')
  part.id = call_id
  part.name = GetString(data, 'name')
  part.state = 'streaming'
enddef

def ApplyToolInput(data: dict<any>, append: bool)
  var part = FindTool(data)
  if type(part) == v:t_none
    return
  endif
  if append
    part.input_text ..= GetString(data, 'delta')
  else
    part.input_text = GetString(data, 'text')
  endif
enddef

def ApplyToolCalled(data: dict<any>)
  var part = FindTool(data)
  if type(part) == v:t_none
    return
  endif
  part.state = 'running'
  part.input = get(data, 'input', v:null)
  part.input_text = ''
  part.executed = get(data, 'executed', false)
enddef

def ApplyToolFinished(data: dict<any>, succeeded: bool)
  var part = FindTool(data)
  if type(part) == v:t_none
    return
  endif
  part.state = succeeded ? 'completed' : 'error'
  part.result = get(data, 'content', v:null)
  part.error = get(data, 'error', v:null)
  part.metadata = get(data, 'metadata', v:null)
enddef

def ApplyStepFinished(data: dict<any>, failed: bool)
  var message = FindMessage(GetString(data, 'assistantMessageID'))
  if type(message) == v:t_none
    return
  endif
  message.error = get(data, 'error', v:null)
  message.finish = get(data, 'finish', '')
  if failed && type(message.error) == v:t_none
    message.error = 'step failed'
  endif
enddef

def ApplyInbox(data: dict<any>)
  var item = get(data, 'item', {})
  if type(item) != v:t_dict
    return
  endif
  var kind = GetString(item, 'type')
  if kind !=# 'user' && kind !=# 'synthetic'
    return
  endif
  var payload = get(item, 'payload', {})
  if type(payload) != v:t_dict
    return
  endif
  var text = GetString(payload, 'text')
  if kind ==# 'user'
    DropOptimistic(text)
  endif
  var id = GetString(data, 'inboxID')
  if id ==# ''
    id = 'inbox:' .. len(messages)
  endif
  IngestMessage({
    id: id,
    type: kind,
    text: text,
    description: GetString(payload, 'description'),
    time: {created: get(data, 'created', 0)},
  })
enddef

def ApplySynthetic(event: dict<any>, data: dict<any>)
  var text = GetString(data, 'text')
  if text ==# ''
    return
  endif
  var id = GetString(event, 'id')
  id = substitute(id, '^evt_', 'msg_', '')
  if id ==# ''
    id = 'synthetic:' .. len(messages)
  endif
  IngestMessage({
    id: id,
    type: 'synthetic',
    text: text,
    description: GetString(data, 'description'),
  })
enddef

def ApplyRevert(data: dict<any>)
  var boundary = GetString(data, 'to')
  if boundary ==# ''
    return
  endif
  var position = -1
  for i in range(len(messages))
    if messages[i].id ==# boundary
      position = i
      break
    endif
  endfor
  if position < 0
    return
  endif
  messages = position == 0 ? [] : messages[0 : position - 1]
  Reindex()
enddef

# ---------------------------------------------------------------------------
# Snapshot and legacy message events

def ApplyMessageUpdated(event: dict<any>)
  var data = get(event, 'data', {})
  var info = get(data, 'info', get(event, 'properties', {}))
  if type(info) != v:t_dict
    return
  endif
  var parts = get(data, 'parts', get(get(event, 'properties', {}), 'parts', []))
  IngestMessage({info: info, parts: parts})
enddef

def ApplyMessageRemoved(event: dict<any>)
  var data = get(event, 'data', {})
  var id = GetString(data, 'messageID')
  if id ==# ''
    id = GetString(get(event, 'properties', {}), 'messageID')
  endif
  RemoveMessage(id)
enddef

def ApplyPartUpdated(event: dict<any>)
  var data = get(event, 'data', {})
  var part = get(data, 'part', get(event, 'properties', {}).part)
  if type(part) != v:t_dict
    part = data
  endif
  var message_id = GetString(part, 'messageID')
  if message_id ==# ''
    message_id = GetString(data, 'messageID')
  endif
  var message = EnsureMessage(message_id, 'assistant')
  IngestPart(message, part, {})
enddef

def ApplyPartDelta(event: dict<any>)
  var data = get(event, 'data', {})
  var message_id = GetString(data, 'messageID')
  var part_id = GetString(data, 'partID')
  var message = FindMessage(message_id)
  if type(message) == v:t_none
    return
  endif
  var part = FindPartById(message, part_id)
  if type(part) == v:t_none
    return
  endif
  var field = GetString(data, 'field')
  if field ==# 'text'
    part.text ..= GetString(data, 'delta')
  elseif field ==# 'reasoning'
    part.text ..= GetString(data, 'delta')
  endif
enddef

def ApplyPartRemoved(event: dict<any>)
  var data = get(event, 'data', {})
  var message_id = GetString(data, 'messageID')
  var part_id = GetString(data, 'partID')
  var message = FindMessage(message_id)
  if type(message) == v:t_none
    return
  endif
  var kept: list<dict<any>> = []
  for part in message.parts
    if part.id !=# part_id
      kept->add(part)
    endif
  endfor
  message.parts = kept
enddef

def IngestMessage(item: dict<any>)
  var info = get(item, 'info', item)
  if type(info) != v:t_dict
    return
  endif
  var id = GetString(info, 'id')
  if id ==# ''
    id = GetString(info, 'messageID')
  endif
  if id ==# ''
    id = 'message:' .. len(messages)
  endif
  var kind = GetString(info, 'type')
  if kind ==# ''
    kind = GetString(info, 'role')
  endif
  if kind ==# ''
    kind = 'assistant'
  endif
  if kind ==# 'assistant' && get(info, 'role', '') ==# 'assistant'
    kind = 'assistant'
  endif

  var message = EnsureMessage(id, kind)
  message.time = get(info, 'time', get(message, 'time', {}))
  message.agent = GetString(info, 'agent')
  message.model = get(info, 'model', v:null)
  message.error = get(info, 'error', v:null)
  message.finish = get(info, 'finish', '')
  message.description = GetString(info, 'description')
  var text = GetString(info, 'text')
  if text !=# ''
    message.text = text
  endif

  var parts = get(item, 'parts', get(info, 'content', []))
  if type(parts) != v:t_list
    return
  endif
  var ordinals: dict<number> = {text: 0, reasoning: 0}
  for part in parts
    if type(part) == v:t_dict
      IngestPart(message, part, ordinals)
    endif
  endfor
enddef

def IngestPart(message: dict<any>, part: dict<any>, ordinals: dict<number>)
  var part_type = GetString(part, 'type')
  if part_type ==# ''
    part_type = GetString(part, 'kind')
  endif
  if part_type ==# 'tool' || has_key(part, 'tool')
    IngestTool(message, part)
    return
  endif
  if part_type !=# 'text' && part_type !=# 'reasoning'
    return
  endif

  var id = GetString(part, 'id')
  var key: string
  if id !=# ''
    key = 'part:' .. id
  else
    var ordinal = get(ordinals, part_type, 0)
    ordinals[part_type] = ordinal + 1
    key = part_type .. ':' .. message.id .. ':' .. ordinal
  endif
  var existing = EnsurePart(message, key, part_type)
  existing.id = id
  existing.text = GetString(part, 'text')
  existing.time = get(part, 'time', v:null)
enddef

def IngestTool(message: dict<any>, part: dict<any>)
  var state = get(part, 'state', {})
  var call_id = GetString(part, 'callID')
  if call_id ==# ''
    call_id = GetString(part, 'call_id')
  endif
  if call_id ==# ''
    call_id = GetString(part, 'id')
  endif
  var key = 'tool:' .. message.id .. ':' .. call_id
  var tool = EnsurePart(message, key, 'tool')
  tool.id = call_id
  tool.name = GetString(part, 'tool')
  if tool.name ==# ''
    tool.name = GetString(part, 'name')
  endif
  if type(state) == v:t_dict
    tool.state = GetString(state, 'status')
    tool.input = get(state, 'input', v:null)
    tool.input_text = GetString(state, 'input')
    tool.result = get(state, 'content', v:null)
    tool.error = get(state, 'error', v:null)
    tool.metadata = get(state, 'metadata', v:null)
  elseif type(state) == v:t_string
    tool.state = state
  endif
  if tool.state ==# ''
    tool.state = 'completed'
  endif
  tool.executed = get(part, 'executed', false)
enddef

# ---------------------------------------------------------------------------
# Message and part helpers

def EnsureMessage(id: string, kind: string): dict<any>
  var message_id = id
  if message_id ==# ''
    message_id = 'message:' .. len(messages)
  endif
  if has_key(index, message_id)
    var position = index[message_id]
    if position > 0 && position <= len(messages)
      var existing = messages[position - 1]
      if get(existing, 'kind', '') ==# ''
        existing.kind = kind
      endif
      return existing
    endif
  endif
  var message: dict<any> = {
    id: message_id,
    kind: kind,
    time: {},
    text: '',
    description: '',
    agent: '',
    model: v:null,
    error: v:null,
    finish: '',
    parts: [],
    optimistic: false,
  }
  messages->add(message)
  index[message_id] = len(messages)
  return message
enddef

def EnsurePart(message: dict<any>, key: string, kind: string): dict<any>
  for part in message.parts
    if part.key ==# key
      return part
    endif
  endfor
  var part: dict<any> = {
    key: key,
    kind: kind,
    id: '',
    text: '',
    name: '',
    state: '',
    input: v:null,
    input_text: '',
    result: v:null,
    error: v:null,
    metadata: v:null,
    time: v:null,
  }
  message.parts->add(part)
  return part
enddef

def FindMessage(id: string): any
  if id ==# '' || !has_key(index, id)
    return v:null
  endif
  var position = index[id]
  if position <= 0 || position > len(messages)
    return v:null
  endif
  return messages[position - 1]
enddef

def FindPartById(message: dict<any>, id: string): any
  if id ==# ''
    return v:null
  endif
  for part in message.parts
    if part.id ==# id
      return part
    endif
  endfor
  return v:null
enddef

# Find a tool part by session tool call id. V2 tool events identify the part by
# call id and the assistant message by assistantMessageID.
def FindTool(data: dict<any>): any
  var message = FindMessage(GetString(data, 'assistantMessageID'))
  if type(message) == v:t_none
    return v:null
  endif
  var call_id = GetString(data, 'id')
  for part in message.parts
    if part.kind ==# 'tool' && part.id ==# call_id
      return part
    endif
  endfor
  return v:null
enddef

def RemoveMessage(id: string)
  if id ==# '' || !has_key(index, id)
    return
  endif
  var position = index[id]
  if position <= 0 || position > len(messages)
    return
  endif
  remove(messages, position - 1)
  Reindex()
enddef

def DropOptimistic(text: string)
  for position in range(len(messages) - 1, 0, -1)
    var message = messages[position]
    if get(message, 'optimistic', false) && get(message, 'text', '') ==# text
      remove(messages, position)
      Reindex()
      return
    endif
  endfor
enddef

def Reindex()
  index = {}
  for position in range(len(messages))
    index[messages[position].id] = position + 1
  endfor
enddef

def Touch()
  version += 1
  for listener in listeners
    try
      call(listener, [])
    catch
      util.Log('error', 'state listener failed: ' .. util.ExceptionText())
    endtry
  endfor
enddef

def GetString(dict: dict<any>, key: string): string
  var value = get(dict, key, '')
  return type(value) == v:t_string ? value : ''
enddef
