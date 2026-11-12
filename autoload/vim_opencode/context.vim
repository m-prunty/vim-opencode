vim9script

# Editor context capture, path formatting and @placeholder expansion.

import autoload 'vim_opencode/util.vim' as util

const PLACEHOLDERS: list<string> = [
  '@diagnostics',
  '@quickfix',
  '@buffers',
  '@visible',
  '@buffer',
  '@marks',
  '@this',
]
var sent_hashes: dict<dict<string>> = {}

# Capture the current window, cursor and optional command/visual range.
export def Capture(line_range: list<number>): dict<any>
  var ctx: dict<any> = {
    buf: bufnr('%'),
    win: win_getid(),
    cursor: getcurpos(),
    cwd: util.Cwd(),
    range: v:null,
    match_id: -1,
    visual: false,
  }

  var line1 = get(line_range, 0, 0)
  var line2 = get(line_range, 1, 0)
  var has_command_range = line1 > 0 && line2 > 0
  var from = getpos("'<")
  var to = getpos("'>")
  var last_visual = visualmode()
  var marks_match = from[1] > 0 && to[1] > 0 &&
    (!has_command_range || (from[1] == line1 && to[1] == line2) || (from[1] == line2 && to[1] == line1))

  if last_visual !=# '' && marks_match
    var kind = last_visual ==# 'V' ? 'line' : (last_visual ==# "\<C-v>" ? 'block' : 'char')
    var start = [from[1], from[2]]
    var end = [to[1], to[2]]
    if start[0] > end[0] || (start[0] == end[0] && start[1] > end[1])
      var swap = start
      start = end
      end = swap
    endif
    if kind ==# 'line'
      start[1] = 1
      end[1] = LineLength(end[0])
    endif
    ctx.range = {from: start, to: end, kind: kind}
    ctx.visual = true
  elseif has_command_range && line1 != line2
    ctx.range = {from: [line1, 1], to: [line2, LineLength(line2)], kind: 'line'}
  endif

  return ctx
enddef

# Capture a range delimited by the '[' and ']' marks from operatorfunc.
export def CaptureOperator(operator_type: string): dict<any>
  var from = getpos("'[")
  var to = getpos("']")
  var ctx: dict<any> = {
    buf: bufnr('%'),
    win: win_getid(),
    cursor: getcurpos(),
    cwd: util.Cwd(),
    range: v:null,
    match_id: -1,
    visual: false,
  }
  if from[1] <= 0 || to[1] <= 0
    return ctx
  endif
  var kind = operator_type ==# 'line' ? 'line' : (operator_type ==# 'block' ? 'block' : 'char')
  var start = [from[1], from[2]]
  var end = [to[1], to[2]]
  if start[0] > end[0] || (start[0] == end[0] && start[1] > end[1])
    var swap = start
    start = end
    end = swap
  endif
  if kind ==# 'line'
    start[1] = 1
    end[1] = LineLength(end[0])
  endif
  if kind ==# 'block' && start[1] > end[1]
    var column = start[1]
    start[1] = end[1]
    end[1] = column
  endif
  ctx.range = {from: start, to: end, kind: kind}
  return ctx
enddef

# Highlight the captured range with matchaddpos until Clear()/Resume().
export def Highlight(ctx: dict<any>)
  if type(ctx.range) == v:t_none || ctx.win <= 0
    return
  endif
  Clear(ctx)
  var positions = Positions(ctx)
  if empty(positions)
    return
  endif
  try
    ctx.match_id = matchaddpos('Visual', positions, 10, -1, {window: ctx.win})
  catch
    ctx.match_id = -1
  endtry
enddef

export def Clear(ctx: dict<any>)
  if get(ctx, 'match_id', -1) > 0
    try
      matchdelete(ctx.match_id, ctx.win)
    catch
      # The window may have closed while the request was in flight.
    endtry
    ctx.match_id = -1
  endif
enddef

# Clear the highlight and restore the visual selection or cursor.
export def Resume(ctx: dict<any>)
  Clear(ctx)
  if get(ctx, 'win', 0) > 0 && win_gotoid(ctx.win)
    try
      cursor(ctx.cursor[1], ctx.cursor[2])
    catch
      # The original buffer may have been wiped.
    endtry
  endif
  if get(ctx, 'visual', false)
    try
      normal! gv
    catch
      # Marks can disappear after a buffer change.
    endtry
  endif
enddef

# Replace the built-in placeholders in a prompt with captured context.
export def Render(text: string, ctx: dict<any>): string
  var result = text
  for placeholder in PLACEHOLDERS
    if stridx(result, placeholder) < 0
      continue
    endif
    var value = Build(placeholder, ctx)
    if type(value) == v:t_string
      result = ReplaceAll(result, placeholder, value)
    endif
  endfor
  return result
enddef

export def Placeholders(): list<string>
  return copy(PLACEHOLDERS)
enddef

export def Rich(ctx: dict<any>): dict<string>
  var result: dict<string> = {}
  var buf = get(ctx, 'buf', 0)
  if type(buf) == v:t_number && buf > 0 && IsFileBuffer(buf)
    result.file = join(getbufline(buf, 1, '$'), "\n")
    result.cursor = join(getbufline(buf, max([1, ctx.cursor[1] - 3]), ctx.cursor[1] + 3), "\n")
    result.diff = GitDiff(ctx.cwd, bufname(buf))
  endif
  return result
enddef

export def Changed(session_id: string, ctx: dict<any>): dict<string>
  var current = Rich(ctx)
  var previous = get(sent_hashes, session_id, {})
  var changed: dict<string> = {}
  var hashes: dict<string> = {}
  for [name, value] in items(current)
    var hash = exists('*sha256') ? sha256(value) : string([strlen(value), value])
    hashes[name] = hash
    if get(previous, name, '') !=# hash
      changed[name] = value
    endif
  endfor
  sent_hashes[session_id] = hashes
  return changed
enddef

export def ClearSent(session_id: string = '')
  if session_id ==# ''
    sent_hashes = {}
  elseif has_key(sent_hashes, session_id)
    remove(sent_hashes, session_id)
  endif
enddef

def GitDiff(cwd: string, file: string): string
  if !executable('git') || file ==# ''
    return ''
  endif
  try
    return join(systemlist('git -C ' .. shellescape(cwd) .. ' diff -- ' .. shellescape(file)), "\n")
  catch
    return ''
  endtry
enddef

def Build(placeholder: string, ctx: dict<any>): any
  if placeholder ==# '@this'
    return This(ctx)
  elseif placeholder ==# '@buffer'
    return Buffer(ctx)
  elseif placeholder ==# '@buffers'
    return Buffers(ctx)
  elseif placeholder ==# '@visible'
    return Visible(ctx)
  elseif placeholder ==# '@quickfix'
    return Quickfix(ctx)
  elseif placeholder ==# '@marks'
    return Marks(ctx)
  elseif placeholder ==# '@diagnostics'
    return Diagnostics(ctx)
  endif
  return v:null
enddef

def This(ctx: dict<any>): any
  if type(ctx.range) != v:t_none
    return FormatRange(ctx.buf, ctx.range.from, ctx.range.to, ctx.range.kind, ctx.cwd)
  endif
  return FormatLocation(ctx.buf, ctx.cursor[1], ctx.cursor[2], ctx.cwd)
enddef

def Buffer(ctx: dict<any>): any
  if IsFileBuffer(ctx.buf)
    return RelativePath(bufname(ctx.buf), ctx.cwd)
  endif
  return join(getbufline(ctx.buf, 1, '$'), "\n")
enddef

def Buffers(ctx: dict<any>): any
  var paths: list<string> = []
  for info in getbufinfo({buflisted: 1})
    var name = get(info, 'name', '')
    if type(name) == v:t_string && name != '' && IsFileBuffer(info.bufnr)
      paths->add(RelativePath(name, ctx.cwd))
    endif
  endfor
  return empty(paths) ? v:null : join(paths, ', ')
enddef

def Visible(ctx: dict<any>): any
  var locations: list<string> = []
  for info in getwininfo()
    var from = get(info, 'topline', 0)
    var to = get(info, 'botline', 0)
    var buf = get(info, 'bufnr', 0)
    if from <= 0 || to < from || buf <= 0
      continue
    endif
    var location = FormatRange(buf, [from, 1], [to, LineLength(to, buf)], 'line', ctx.cwd)
    if type(location) == v:t_string
      locations->add(location)
    endif
  endfor
  return empty(locations) ? v:null : join(locations, ', ')
enddef

def Quickfix(ctx: dict<any>): any
  var locations: list<string> = []
  for entry in getqflist()
    if get(entry, 'valid', 1) == 0 || get(entry, 'bufnr', 0) <= 0
      continue
    endif
    var location = FormatLocation(get(entry, 'bufnr', 0), get(entry, 'lnum', 0), get(entry, 'col', 1), ctx.cwd)
    if type(location) == v:t_string
      locations->add(location)
    endif
  endfor
  return empty(locations) ? v:null : join(locations, ', ')
enddef

def Marks(ctx: dict<any>): any
  var locations: list<string> = []
  for mark in getmarklist()
    if get(mark, 'mark', '') !~# '^''[A-Z]$'
      continue
    endif
    var pos = get(mark, 'pos', [])
    if type(pos) != v:t_list || len(pos) < 3 || pos[0] <= 0
      continue
    endif
    var location = FormatLocation(pos[0], pos[1], max([1, pos[2]]), ctx.cwd)
    if type(location) == v:t_string
      locations->add(location)
    endif
  endfor
  return empty(locations) ? v:null : join(locations, ', ')
enddef

def Diagnostics(ctx: dict<any>): any
  var lines: list<string> = []
  for entry in getqflist()
    if get(entry, 'valid', 1) == 0
      continue
    endif
    var buf = get(entry, 'bufnr', 0)
    if buf != ctx.buf
      continue
    endif
    var lnum = get(entry, 'lnum', 0)
    if type(ctx.range) != v:t_none && (lnum < ctx.range.from[0] || lnum > ctx.range.to[0])
      continue
    endif
    var location = FormatLocation(buf, lnum, max([1, get(entry, 'col', 1)]), ctx.cwd)
    if type(location) != v:t_string
      continue
    endif
    var source = get(entry, 'module', '')
    if type(source) != v:t_string || source ==# ''
      source = get(entry, 'type', 'quickfix')
    endif
    if type(source) != v:t_string || source ==# ''
      source = 'quickfix'
    endif
    var text = substitute(get(entry, 'text', ''), '\s\+', ' ', 'g')
    lines->add('- ' .. location .. ' (' .. source .. '): ' .. text)
  endfor
  if empty(lines)
    return v:null
  endif
  return len(lines) .. ' diagnostic(s):' .. "\n" .. join(lines, "\n")
enddef

# Format a file range as path:Lx:Cy-Lx:Cy, or return the literal text for
# buffers without a readable backing file.
export def FormatRange(buf: number, from: list<number>, to: list<number>, kind: string, cwd: string): any
  if !IsFileBuffer(buf)
    return RangeText(buf, from, to, kind)
  endif
  var result = RelativePath(bufname(buf), cwd)
  result ..= ':L' .. from[0]
  if kind !=# 'line'
    result ..= ':C' .. from[1]
  endif
  result ..= '-L' .. to[0]
  if kind !=# 'line'
    result ..= ':C' .. to[1]
  endif
  return result
enddef

# Format a single location as path:Lx:Cy.
export def FormatLocation(buf: number, lnum: number, col: number, cwd: string): any
  if !IsFileBuffer(buf)
    return get(getbufline(buf, lnum), 0, '')
  endif
  return RelativePath(bufname(buf), cwd) .. ':L' .. lnum .. ':C' .. max([1, col])
enddef

def RangeText(buf: number, from: list<number>, to: list<number>, kind: string): string
  var lines = getbufline(buf, from[0], to[0])
  if empty(lines)
    return ''
  endif
  if kind ==# 'line'
    return join(lines, "\n")
  endif
  if len(lines) == 1
    return strpart(lines[0], from[1] - 1, max([0, to[1] - from[1] + 1]))
  endif
  var first = strpart(lines[0], from[1] - 1)
  var last = strpart(lines[-1], 0, max([0, to[1]]))
  var middle = len(lines) > 2 ? lines[1 : -2] : []
  return join([first] + middle + [last], "\n")
enddef

def IsFileBuffer(buf: number): bool
  var name = bufname(buf)
  return type(name) == v:t_string && name != '' && filereadable(name)
enddef

def RelativePath(path: string, cwd: string): string
  var normalized = util.NormalizePath(path)
  var prefix = cwd ==# '/' ? '/' : cwd .. '/'
  if stridx(normalized, prefix) == 0
    return strpart(normalized, strlen(prefix))
  endif
  return normalized
enddef

def LineLength(lnum: number, buf: number = 0): number
  var line = buf > 0 ? get(getbufline(buf, lnum), 0, '') : getline(lnum)
  return max([1, strlen(line)])
enddef

def Positions(ctx: dict<any>): list<list<number>>
  var positions: list<list<number>> = []
  var selected = ctx.range
  var kind = selected.kind
  for lnum in range(selected.from[0], selected.to[0])
    var line_length = LineLength(lnum, ctx.buf)
    var start = 1
    var end = line_length
    if kind ==# 'char'
      if lnum == selected.from[0]
        start = max([1, selected.from[1]])
      endif
      if lnum == selected.to[0]
        end = min([line_length, selected.to[1]])
      endif
    elseif kind ==# 'block'
      start = max([1, min([selected.from[1], selected.to[1]])])
      end = min([line_length, max([selected.from[1], selected.to[1]])])
    endif
    if end >= start
      positions->add([lnum, start, end - start + 1])
    endif
  endfor
  return positions
enddef

def ReplaceAll(text: string, needle: string, replacement: string): string
  if needle ==# ''
    return text
  endif
  var result = ''
  var start = 0
  while true
    var position = stridx(text, needle, start)
    if position < 0
      result ..= strpart(text, start)
      break
    endif
    result ..= strpart(text, start, position - start) .. replacement
    start = position + strlen(needle)
  endwhile
  return result
enddef
