vim9script

# Transcript formatter.
#
# A chunk is the unit the panel writes and folds: {key, kind, lines, fold,
# props}. Chunks are stable per message part so streaming text only rewrites the
# part that changed, and previously created folds stay intact.

import autoload 'vim_opencode/state.vim' as state
import autoload 'vim_opencode/util.vim' as util

const MAX_REASONING_LINES = 80
const MAX_TOOL_LINES = 120
const MAX_INPUT_CHARS = 400
const MAX_RESULT_CHARS = 2000

# Convert the current transcript into ordered render chunks.
# When max_messages is set, only the most recent messages are rendered and a
# truncation notice is prepended so the user knows older content was dropped.
export def Chunks(max_messages: number = 0): list<dict<any>>
  var chunks: list<dict<any>> = []
  var all_messages = state.Messages()
  var start = 0
  if max_messages > 0 && len(all_messages) > max_messages
    start = len(all_messages) - max_messages
    chunks->add({
      key: 'truncated',
      kind: 'notice',
      lines: [
        '# ' .. (len(all_messages) - max_messages) .. ' older messages hidden (max_messages=' .. max_messages .. ')',
        '# Scroll or reopen the panel to see more context.',
      ],
      fold: false,
      props: [{offset: 0, col: 1, length: 1, group: 'VimOpencodeMuted'}],
    })
  endif
  var i = start
  while i < len(all_messages)
    var message = all_messages[i]
    var produced = ChunksForMessage(message)
    if !empty(produced)
      chunks += produced
      chunks->add({key: 'sep:' .. message.id, kind: 'separator', lines: [''], fold: false, props: []})
    endif
    i += 1
  endwhile
  return chunks
enddef

# Flatten chunks into buffer lines.
export def Lines(chunks: list<dict<any>> = []): list<string>
  var source = empty(chunks) ? Chunks() : chunks
  var lines: list<string> = []
  for chunk in source
    lines += chunk.lines
  endfor
  return lines
enddef

# Return 1-based line numbers where each message begins, tagged by kind.
export def MessageLines(chunks: list<dict<any>> = []): list<dict<any>>
  var source = empty(chunks) ? Chunks() : chunks
  var result: list<dict<any>> = []
  var line = 1
  for chunk in source
    if get(chunk, 'messageStart', false)
      var kind = chunk.kind ==# 'user' ? 'user' : (chunk.kind ==# 'notice' ? 'notice' : 'assistant')
      result->add({line: line, kind: kind})
    endif
    line += len(chunk.lines)
  endfor
  return result
enddef

def ChunksForMessage(message: dict<any>): list<dict<any>>
  var chunks: list<dict<any>> = []
  var kind = get(message, 'kind', '')

  if kind ==# 'user'
    var text = get(message, 'text', '')
    if text ==# ''
      return []
    endif
    chunks->add({
      key: 'user:' .. message.id,
      kind: 'user',
      lines: PrefixLines(text, '> '),
      fold: false,
      props: [{offset: 0, col: 1, length: 2, group: 'VimOpencodeUser'}],
    })
    MarkStart(chunks)
    return chunks
  endif

  if kind ==# 'assistant'
    for part in get(message, 'parts', [])
      var part_kind = get(part, 'kind', '')
      if part_kind ==# 'text'
        var value = get(part, 'text', '')
        if value !=# ''
          chunks->add({
            key: get(part, 'key', ''),
            kind: 'text',
            lines: SplitLines(value),
            fold: false,
            props: [],
          })
        endif
      elseif part_kind ==# 'reasoning'
        var reasoning = get(part, 'text', '')
        if reasoning !=# ''
          var lines = ['[reasoning]'] + IndentLines(CapLines(SplitLines(reasoning), MAX_REASONING_LINES))
          chunks->add({
            key: get(part, 'key', ''),
            kind: 'reasoning',
            lines: lines,
            fold: true,
            props: [{offset: 0, col: 1, length: strlen(lines[0]), group: 'VimOpencodeReasoning'}],
          })
        endif
      elseif part_kind ==# 'tool'
        var tool_lines = ToolLines(part)
        chunks->add({
          key: get(part, 'key', ''),
          kind: 'tool',
          lines: tool_lines,
          fold: true,
          props: [{offset: 0, col: 1, length: strlen(tool_lines[0]), group: 'VimOpencodeTool'}],
        })
      endif
    endfor
  endif

  if kind ==# 'synthetic' || kind ==# 'system'
    var notice = get(message, 'text', '')
    if notice !=# ''
      var label = get(message, 'description', '')
      var notice_lines = label ==# '' ? PrefixLines(notice, '# ') : ['# ' .. label] + PrefixLines(notice, '  ')
      chunks->add({
        key: 'notice:' .. message.id,
        kind: 'notice',
        lines: notice_lines,
        fold: false,
        props: [{offset: 0, col: 1, length: 1, group: 'VimOpencodeMuted'}],
      })
    endif
  endif

  var error = get(message, 'error', v:null)
  if type(error) != v:t_none && type(error) != v:t_bool && !(type(error) == v:t_string && error ==# '')
    var error_lines = ['[error]'] + PrefixLines(ErrorText(error), '  ')
    chunks->add({
      key: 'error:' .. message.id,
      kind: 'error',
      lines: error_lines,
      fold: false,
      props: [{offset: 0, col: 1, length: strlen(error_lines[0]), group: 'VimOpencodeError'}],
    })
  endif

  MarkStart(chunks)
  return chunks
enddef

def MarkStart(chunks: list<dict<any>>)
  if !empty(chunks)
    chunks[0].messageStart = true
  endif
enddef

def ToolLines(part: dict<any>): list<string>
  var name = get(part, 'name', '')
  if name ==# ''
    name = 'tool'
  endif
  var status = get(part, 'state', '')
  var header = '[tool ' .. name .. ']'
  if status !=# '' && status !=# 'completed'
    header ..= ' ' .. status
  endif

  var body: list<string> = []
  var input_text = get(part, 'input_text', '')
  if input_text !=# ''
    var trimmed = substitute(input_text, '\n$', '', '')
    body += PrefixLines(CapText(trimmed, MAX_INPUT_CHARS), '  input: ')
  elseif type(get(part, 'input', v:null)) != v:t_none
    body += PrefixLines(CapText(JsonText(part.input), MAX_INPUT_CHARS), '  input: ')
  endif

  var result = get(part, 'result', v:null)
  if type(result) != v:t_none
    var result_lines = ResultLines(result)
    if !empty(result_lines)
      var limited = CapLines(result_lines, MAX_TOOL_LINES)
      body += PrefixLines(CapText(join(limited, "\n"), MAX_RESULT_CHARS), '  ')
    endif
  endif

  var error = get(part, 'error', v:null)
  if type(error) != v:t_none
    body += PrefixLines(ErrorText(error), '  error: ')
  endif

  if empty(body) && status ==# 'error'
    body = ['  (failed without details)']
  endif

  return [header] + body
enddef

def ResultLines(result: any): list<string>
  if type(result) == v:t_string
    return SplitLines(result)
  endif
  if type(result) == v:t_list
    var lines: list<string> = []
    for item in result
      if type(item) == v:t_string
        lines += SplitLines(item)
      elseif type(item) == v:t_dict
        var text = get(item, 'text', '')
        if type(text) == v:t_string && text !=# ''
          lines += SplitLines(text)
        else
          var name = get(item, 'name', '')
          if type(name) == v:t_string && name !=# ''
            lines->add(name)
          else
            lines->add(JsonText(item))
          endif
        endif
      endif
    endfor
    return lines
  endif
  if type(result) == v:t_dict
    var text = get(result, 'text', get(result, 'output', ''))
    if type(text) == v:t_string && text !=# ''
      return SplitLines(text)
    endif
    return [JsonText(result)]
  endif
  return []
enddef

def ErrorText(error: any): string
  if type(error) == v:t_string
    return error
  endif
  if type(error) == v:t_dict
    var message = get(error, 'message', get(error, 'name', ''))
    if type(message) == v:t_string && message !=# ''
      return message
    endif
  endif
  return JsonText(error)
enddef

def JsonText(value: any): string
  try
    var text = util.JsonEncode(value)
    return text ==# 'null' ? '' : text
  catch
    return string(value)
  endtry
enddef

def SplitLines(text: string): list<string>
  if text ==# ''
    return []
  endif
  return split(text, '\n', 1)
enddef

def PrefixLines(text: string, prefix: string): list<string>
  var lines = SplitLines(text)
  if empty(lines)
    return []
  endif
  var result: list<string> = []
  for line in lines
    result->add(line ==# '' ? '' : prefix .. line)
  endfor
  return result
enddef

def IndentLines(lines: list<string>): list<string>
  var result: list<string> = []
  for line in lines
    result->add(line ==# '' ? '' : '  ' .. line)
  endfor
  return result
enddef

def CapLines(lines: list<string>, limit: number): list<string>
  if len(lines) <= limit
    return lines
  endif
  return lines[0 : limit - 1] + ['...']
enddef

def CapText(value: any, limit: number): string
  if type(value) == v:t_list
    return join(value, "\n")
  endif
  var text = type(value) == v:t_string ? value : string(value)
  if strlen(text) <= limit
    return text
  endif
  return strpart(text, 0, limit) .. '...'
enddef
