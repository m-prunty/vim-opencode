vim9script

# Settings for the opencode9 prompt input buffer.

import autoload 'opencode9/catalog.vim' as catalog

if exists('b:did_ftplugin')
  finish
endif
b:did_ftplugin = 1

setlocal buftype=nofile
setlocal bufhidden=wipe
setlocal noswapfile
setlocal nobuflisted
setlocal nonumber
setlocal norelativenumber
setlocal noundofile
setlocal wrap
setlocal linebreak

# Completion offers @ context placeholders and cached server commands. Commands
# use a leading slash for display, but the input is still plain text.
def g:Opencode9InputComplete(findstart: number, base: string): any
  if findstart == 1
    var line = getline('.')
    var start = col('.') - 1
    while start > 0 && line[start - 1] =~# '[A-Za-z0-9_@/-]'
      start -= 1
    endwhile
    return start
  endif
  return catalog.Complete(base)
enddef

setlocal completeopt=menu,menuone,noinsert
setlocal omnifunc=g:Opencode9InputComplete

b:undo_ftplugin = 'setlocal buftype< bufhidden< swapfile< buflisted< number< relativenumber< undofile< wrap< linebreak< completeopt< omnifunc<'
