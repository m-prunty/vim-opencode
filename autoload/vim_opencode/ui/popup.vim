vim9script

# Generic bordered popup runner modeled on fzf.vim's spec-dict pattern.
#
# Every picker/palette/preview builds a spec dict and hands it to
# vim_opencode#ui#popup#Run(). The runner creates a popup_create() window with
# a border/title/footer, installs mappings via the popup `mapping` option,
# scrolls the contents, and falls back to inputlist() when +popupwin is
# unavailable.

import autoload 'vim_opencode/util.vim' as util

const DEFAULT_BORDER_CHARS: list<string> = ['╭', '─', '╮', '│', '╯', '─', '╰', '│']
const SINGLE_BORDER_CHARS: list<string> = ['+', '-', '+', '|', '+', '-', '+', '|']

var open_popups: list<number> = []

def EnsureGlobals()
  if !has_key(g:, 'vim_opencode_popup_specs')
    g:vim_opencode_popup_specs = {}
  endif
enddef

# Build the line buffer for a popup spec. Returns [lines, title_lines,
# border_offset] where border_offset is the number of lines above the first
# item row (title + top border).
def BuildLines(spec: dict<any>): list<any>
  var title = get(spec, 'title', '')
  var width = get(spec, 'width', 60)
  var padding = get(spec, 'padding', 1)
  var items = get(spec, 'items', [])
  var footer = get(spec, 'footer', '')
  var cfg = GetConfig()
  var border = get(spec, 'border', get(cfg.gui, 'popup_border', 'rounded'))
  var border_chars: list<string> = []
  if border ==# 'rounded'
    border_chars = DEFAULT_BORDER_CHARS
  elseif border ==# 'single'
    border_chars = SINGLE_BORDER_CHARS
  endif

  var lines: list<string> = []
  var title_lines = 0
  if title !=# ''
    lines->add(title)
    title_lines += 1
  endif
  var border_offset = 0
  if empty(border_chars)
    lines += items
  else
    var top = border_chars[0] .. repeat(border_chars[1], width - 2) .. border_chars[2]
    lines->add(top)
    border_offset += 1
    for item in items
      var cell = item
      if len(cell) > width - 2 - padding * 2
        cell = strpart(cell, 0, width - 2 - padding * 2 - 3) .. '...'
      endif
      var right_pad = width - 2 - len(cell) - padding * 2
      if right_pad < 0
        right_pad = 0
      endif
      lines->add(border_chars[3] .. repeat(' ', padding) .. cell ..
                 \ repeat(' ', right_pad) .. border_chars[3])
    endfor
    var bot = border_chars[4] .. repeat(border_chars[5], width - 2) .. border_chars[6]
    lines->add(bot)
  endif
  if footer !=# ''
    lines->add(footer)
  endif
  return [lines, title_lines, border_offset]
enddef

def GetConfig(): dict<any>
  return get(g:, 'vim_opencode_config', {})
enddef

def BorderName(style: string): any
  if style ==# 'none'
    return 'none'
  endif
  if style ==# 'single'
    return SINGLE_BORDER_CHARS
  endif
  return DEFAULT_BORDER_CHARS
enddef

# Run a bordered popup list. spec:
#   items       list<string>  - display lines
#   title       string        - optional title bar
#   border      string        - 'rounded'|'single'|'none' (default from config)
#   width       number        - popup width
#   height      number        - popup height
#   row         number        - popup row (default centered)
#   col         number        - popup col (default centered)
#   padding     number        - inner padding (default 1)
#   keymaps     dict<string,string> - extra lhs->rhs buffer mappings
#   callback    funcref       - called with (selection: string) on Enter
#   cancel      funcref       - called when popup closes without selection
#   footer      string        - hint line appended under the list
# Returns the popup id, or -1 when falling back to inputlist().
export def Run(spec: dict<any>): number
  call EnsureGlobals()
  if !has('popupwin') || !exists('*popup_create()')
    return RunInputlist(spec)
  endif

  var cfg = GetConfig()
  var border = get(spec, 'border', get(cfg.gui, 'popup_border', 'rounded'))
  var border_chars = BorderName(border)

  var title = get(spec, 'title', '')
  var width = get(spec, 'width', 60)
  var height = get(spec, 'height', 10)
  var padding = get(spec, 'padding', 1)
  var items = get(spec, 'items', [])
  var footer = get(spec, 'footer', '')

  var result = BuildLines(spec)
  var lines: list<string> = result[0]

  var winid = popup_create(lines, {
    \ title: title,
    \ border: border_chars,
    \ padding: padding,
    \ width: width,
    \ height: height,
    \ row: get(spec, 'row', -1),
    \ col: get(spec, 'col', -1),
    \ zindex: 500,
    \ focusable: v:true,
    \ close: 'click',
  })

  open_popups->add(winid)
  g:vim_opencode_popup_specs[winid] = spec
  call InstallPopupMappings({'winid': winid, 'spec': spec})
  return winid
enddef

def InstallPopupMappings(info: dict<any>)
  var winid = get(info, 'winid', 0)
  var spec = get(info, 'spec', {})
  var base: dict<any> = {
    \ '<CR>': funcref('g:VimOpencodePopupSelect'),
    \ '<C-o>': funcref('g:VimOpencodePopupPeek'),
    \ '<C-q>': funcref('g:VimOpencodePopupCloseById'),
    \ '<C-e>': funcref('g:VimOpencodePopupScrollDown'),
    \ '<C-y>': funcref('g:VimOpencodePopupScrollUp'),
    \ '<PageDown>': funcref('g:VimOpencodePopupScrollDownPage'),
    \ '<PageUp>': funcref('g:VimOpencodePopupScrollUpPage'),
    \ '<C-d>': funcref('g:VimOpencodePopupScrollDownPage'),
    \ '<C-u>': funcref('g:VimOpencodePopupScrollUpPage'),
  }
  var merged = deepcopy(base)
  for [key, val] in items(get(spec, 'keymaps', {}))
    merged[key] = val
  endfor
  var mapping: dict<any> = {}
  for [lhs, rhs] in items(merged)
    mapping[lhs] = rhs
  endfor
  call popup_setoptions(winid, {mapping: mapping})
enddef

def g:VimOpencodePopupSelect()
  var winid = CurrentPopup()
  if winid == 0
    return
  endif
  var spec = get(g:vim_opencode_popup_specs, winid, {})
  var result = BuildLines(spec)
  var title_lines = result[1]
  var border_offset = result[2]
  var pos = popup_getpos(winid)
  var idx = pos.line - title_lines - border_offset
  var items = get(spec, 'items', [])
  if idx >= 1 && idx <= len(items)
    var cb = get(spec, 'callback', v:null)
    if type(cb) == v:t_func
      call(cb, [items[idx - 1]])
    endif
  endif
  VimOpencodePopupCloseById()
enddef

def g:VimOpencodePopupPeek()
  var winid = CurrentPopup()
  if winid == 0
    return
  endif
  var spec = get(g:vim_opencode_popup_specs, winid, {})
  var result = BuildLines(spec)
  var title_lines = result[1]
  var border_offset = result[2]
  var pos = popup_getpos(winid)
  var idx = pos.line - title_lines - border_offset
  var items = get(spec, 'items', [])
  if idx >= 1 && idx <= len(items)
    var cb = get(spec, 'callback', v:null)
    if type(cb) == v:t_func
      call(cb, [items[idx - 1]])
    endif
  endif
enddef

def g:VimOpencodePopupCloseById()
  var winid = CurrentPopup()
  if winid == 0
    return
  endif
  if winid > 0 && popup_isvisible(winid)
    popup_close(winid)
  endif
  open_popups = filter(open_popups, (_, w) => w != winid)
  var spec = get(g:vim_opencode_popup_specs, winid, {})
  unlet g:vim_opencode_popup_specs[winid]
  var cancel = get(spec, 'cancel', v:null)
  if type(cancel) == v:t_func
    call(cancel, [])
  endif
enddef

def g:VimOpencodePopupScrollDown()
  g:VimOpencodePopupScrollCurrent({'dir': 1})
enddef

def g:VimOpencodePopupScrollUp()
  g:VimOpencodePopupScrollCurrent({'dir': -1})
enddef

def g:VimOpencodePopupScrollDownPage()
  g:VimOpencodePopupScrollCurrent({'dir': 5})
enddef

def g:VimOpencodePopupScrollUpPage()
  g:VimOpencodePopupScrollCurrent({'dir': -5})
enddef

def g:VimOpencodePopupScrollCurrent(info: dict<any>)
  var winid = CurrentPopup()
  if winid == 0
    return
  endif
  var dir = get(info, 'dir', 0)
  var pos = popup_getpos(winid)
  var new_line = max([1, pos.line + dir])
  call popup_setpos(winid, {line: new_line})
enddef

export def CurrentPopupId(): number
  call EnsureGlobals()
  for id in keys(g:vim_opencode_popup_specs)
    if popup_isvisible(id)
      return id
    endif
  endfor
  return 0
enddef

export def CurrentPopup(): number
  return CurrentPopupId()
enddef

# Return the 1-based line position within the current popup's rendered buffer,
# or 0 if no popup is visible.
export def CurrentPopupLine(): number
  var winid = CurrentPopupId()
  if winid == 0
    return 0
  endif
  return popup_getpos(winid).line
enddef

# Return the offset (title + border lines) above the first item row for the
# current popup, or 0 if none.
export def CurrentPopupOffset(): number
  var winid = CurrentPopupId()
  if winid == 0
    return 0
  endif
  var spec = get(g:vim_opencode_popup_specs, winid, {})
  var result = BuildLines(spec)
  return result[1] + result[2]
enddef

# Close all open popups (e.g. when leaving normal context).
export def CloseAll(info: dict<any>)
  for winid in copy(open_popups)
    if winid > 0 && popup_isvisible(winid)
      popup_close(winid)
    endif
  endfor
  open_popups = []
  g:vim_opencode_popup_specs = {}
enddef

def RunInputlist(spec: dict<any>): number
  var items = get(spec, 'items', [])
  if empty(items)
    util.EchoInfo('no items available')
    return -1
  endif
  var labels: list<string> = []
  var index = 1
  for item in items
    labels->add(printf('%d. %s', index, item))
    index += 1
  endfor
  var title = get(spec, 'title', 'OpenCode')
  var prompt = [title] + labels
  var choice = inputlist(prompt)
  if choice >= 1
    var cb = get(spec, 'callback', v:null)
    if type(cb) == v:t_func
      call(cb, [items[choice - 1]])
    endif
  else
    var cancel = get(spec, 'cancel', v:null)
    if type(cancel) == v:t_func
      call(cancel, [])
    endif
  endif
  return -1
enddef
