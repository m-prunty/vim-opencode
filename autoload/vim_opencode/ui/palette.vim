vim9script

# Interactive command palette modeled on fzf.vim's spec-dict pattern.
#
# Opens a single bordered popup listing every :Opencode command and
# sub-action. Supports filtering (`/`), preview (C-P), help (C-H),
# and quit (C-Q). Enter runs the highlighted command.

import autoload 'vim_opencode/commands.vim' as commands
import autoload 'vim_opencode/ui/popup.vim' as popup
import autoload 'vim_opencode/util.vim' as util

var palette_state: dict<any> = {}

# Build the flattened source of all commands + sub-actions.
export def Source(): list<dict<any>>
  var out: list<dict<any>> = []
  var table = commands.Table()
  for [name, meta] in items(table)
    if !meta.implemented
      continue
    endif
    out->add({
      \ kind: 'command',
      \ name: name,
      \ label: name,
      \ desc: get(meta, 'description', ''),
      \ usage: get(meta, 'usage', ''),
      \ })
  endfor
  # Sub-actions that are worth reaching directly from the palette.
  var subs: list<dict<any>> = [
    \ {kind: 'session', name: 'session list', label: 'session list', desc: 'List conversations', usage: 'session list'},
    \ {kind: 'session', name: 'session pick', label: 'session pick', desc: 'Pick a conversation', usage: 'session pick'},
    \ {kind: 'session', name: 'session new', label: 'session new', desc: 'Create a conversation', usage: 'session new'},
    \ {kind: 'model', name: 'model list', label: 'model list', desc: 'List models', usage: 'model list'},
    \ {kind: 'model', name: 'model pick', label: 'model pick', desc: 'Pick a model', usage: 'model pick'},
    \ {kind: 'agent', name: 'agent list', label: 'agent list', desc: 'List agents', usage: 'agent list'},
    \ {kind: 'agent', name: 'agent pick', label: 'agent pick', desc: 'Pick an agent', usage: 'agent pick'},
    \ {kind: 'server', name: 'server connect', label: 'server connect', desc: 'Connect to server', usage: 'server connect'},
    \ {kind: 'server', name: 'server status', label: 'server status', desc: 'Show connection state', usage: 'server status'},
    \ {kind: 'permission', name: 'permission list', label: 'permission list', desc: 'List pending requests', usage: 'permission list'},
    \ {kind: 'diff', name: 'diff open', label: 'diff open', desc: 'Open edit diff', usage: 'diff open'},
    \ {kind: 'tab', name: 'tab list', label: 'tab list', desc: 'List panel tabs', usage: 'tab list'},
    \ ]
  for s in subs
    out->add(s)
  endfor
  return out
enddef

# Format a source entry for display.
def FormatEntry(entry: dict<any>): string
  var label = get(entry, 'label', '')
  var desc = get(entry, 'desc', '')
  if desc !=# ''
    return label .. '  —  ' .. desc
  endif
  return label
enddef

# Filter the source by the current filter string.
def Filtered(): list<dict<any>>
  var f = tolower(get(palette_state, 'filter', ''))
  var out: list<dict<any>> = []
  if f ==# ''
    return copy(get(palette_state, 'source', []))
  endif
  for entry in get(palette_state, 'source', [])
    var h = tolower(get(entry, 'label', '') .. ' ' .. get(entry, 'desc', ''))
    if stridx(h, f) >= 0
      out->add(entry)
    endif
  endfor
  return out
enddef

# Run the palette. info: dict with optional 'filter' string.
export def Palette(info: dict<any>)
  var filter = get(info, 'filter', '')
  palette_state = {filter: filter, source: Source(), idx: 1}
  var items = Filtered()
  if empty(items)
    util.EchoInfo('no commands available')
    return
  endif
  var lines: list<string> = []
  var i = 1
  for entry in items
    lines->add(printf('[%d] %s', i, FormatEntry(entry)))
    i += 1
  endfor
  var footer = 'Enter run | C-P preview | C-H help | / filter | C-Q quit'
  var spec: dict<any> = {
    \ items: lines,
    \ title: 'OpenCode palette',
    \ border: 'rounded',
    \ width: 74,
    \ height: min([len(lines) + 4, 22]),
    \ callback: (sel: string) => g:PaletteRunSelection({'selection': sel}),
    \ cancel: funcref('g:PaletteCancel'),
    \ footer: footer,
    \ keymaps: {
    \   '/': funcref('g:PaletteStartFilter'),
    \   'C-h': funcref('g:PaletteHelp'),
    \   'C-p': funcref('g:PalettePreview'),
    \   'j': funcref('g:PaletteNext'),
    \   'k': funcref('g:PalettePrev'),
    \   '<Down>': funcref('g:PaletteNext'),
    \   '<Up>': funcref('g:PalettePrev'),
    \ },
    \ }
  popup.Run(spec)
enddef

def g:PaletteRunSelection(info: dict<any>)
  var selection = get(info, 'selection', '')
  var m = matchstr(selection, '^\\[\(\d\+\)\\]')
  if m ==# ''
    return
  endif
  var choice = str2nr(substitute(m, '[\\[\]]', '', 'g'))
  var items = Filtered()
  if choice < 1 || choice > len(items)
    return
  endif
  var entry = items[choice - 1]
  var usage = get(entry, 'usage', '')
  if usage !=# ''
    execute 'Opencode ' .. usage
  else
    execute 'Opencode ' .. get(entry, 'name', '')
  endif
enddef

def g:PaletteStartFilter(info: dict<any>)
  var filter = input('filter: ')
  if filter ==# ''
    return
  endif
  call popup.CloseAll({})
  Palette({'filter': filter})
enddef

def g:PaletteHelp(info: dict<any>)
  util.EchoInfo('OpenCode palette: Enter run, C-P preview, C-H help, / filter, C-Q quit')
enddef

def g:PalettePreview(info: dict<any>)
  var winid = popup.CurrentPopupId()
  if winid == 0
    return
  endif
  var line = popup.CurrentPopupLine()
  var offset = popup.CurrentPopupOffset()
  var idx = line - offset
  var items = Filtered()
  if idx < 1 || idx > len(items)
    return
  endif
  var entry = items[idx - 1]
  var lines: list<string> = []
  lines->add('kind: ' .. get(entry, 'kind', ''))
  lines->add('name: ' .. get(entry, 'name', ''))
  var desc = get(entry, 'desc', '')
  if desc !=# ''
    lines->add('desc: ' .. desc)
  endif
  var usage = get(entry, 'usage', '')
  if usage !=# ''
    lines->add('usage: :Opencode ' .. usage)
  endif
  var pspec: dict<any> = {
    \ items: lines,
    \ title: 'Preview',
    \ border: 'rounded',
    \ width: 50,
    \ height: min([len(lines) + 4, 10]),
    \ callback: (sel: string) => 0,
    \ footer: 'C-Q close',
    \ }
  popup.Run(pspec)
enddef

def g:PaletteNext(info: dict<any>)
  # Navigation handled by popup's inherent line movement; this is a placeholder.
enddef

def g:PalettePrev(info: dict<any>)
  # Navigation handled by popup's inherent line movement; this is a placeholder.
enddef

def g:PaletteCancel()
  palette_state = {}
enddef
