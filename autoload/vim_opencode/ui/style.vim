vim9script

# Style helpers modeled on fzf.vim's s:get_color / s:ansi / s:key_label.
# All colors are derived from Vim highlight groups; never hard-coded ANSI.

# Return the gui (#RRGGBB) or cterm color attribute for a highlight group.
# attr: 'fg' | 'bg'
export def GetColor(group: string, attr: string): string
  var id = hlID(a:group)
  if id == 0
    return ''
  endif
  var tid = synIDtrans(id)
  if &termguicolors
    return synIDattr(tid, a:attr, 'gui')
  endif
  return synIDattr(tid, a:attr, 'cterm')
enddef

# Return the attribute from the first highlight group that defines it.
export def GetColorAny(attr: string, ...: string): string
  for group in a:000
    var value = GetColor(group, a:attr)
    if value !=# '' && value !=# 'NONE'
      return value
    endif
  endfor
  return ''
enddef

# Convert key names to footer labels: C-X, A-S, S-, Dbl-, uppercases single chars.
# Mirrors fzf.vim's s:key_label().
export def KeyLabel(keys: string): string
  var key = a:keys
  if key =~# '^<.*>$'
    var inner = substitute(key, '^<\(.*\)>$', '\1', '')
    if inner =~# '^C-'
      return 'C-' .. toupper(strpart(inner, 2))
    elseif inner =~# '^A-'
      return 'A-' .. toupper(strpart(inner, 2))
    elseif inner =~# '^S-'
      return 'S-' .. toupper(strpart(inner, 2))
    elseif inner =~# '^D-'
      return 'D-' .. toupper(strpart(inner, 2))
    elseif inner ==# 'CR' || inner ==# 'Return'
      return 'Enter'
    elseif inner ==# 'Esc'
      return 'Esc'
    elseif inner ==# 'Tab'
      return 'Tab'
    elseif inner ==# 'Space'
      return 'Space'
    elseif inner ==# 'BS' || inner ==# 'BackSpace'
      return 'BS'
    elseif inner ==# 'Del' || inner ==# 'Delete'
      return 'Del'
    elseif inner ==# 'Up'
      return '↑'
    elseif inner ==# 'Down'
      return '↓'
    elseif inner ==# 'Left'
      return '←'
    elseif inner ==# 'Right'
      return '→'
    elseif inner =~# '^F\d\+$'
      return inner
    else
      return toupper(inner)
    endif
  endif
  if len(key) == 1
    return toupper(key)
  endif
  return key
enddef

# Format a list of keys into a label string, e.g. ['<C-p>', '<C-n>'] -> 'C-P C-N'.
export def KeyLabels(keys: list<string>): string
  var parts: list<string> = []
  for key in keys
    parts->add(KeyLabel(key))
  endfor
  return join(parts, ' ')
enddef
