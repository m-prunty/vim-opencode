vim9script

# Settings for the vim-opencode transcript output buffer.

if exists('b:did_ftplugin')
  finish
endif
b:did_ftplugin = 1

setlocal buftype=nofile
setlocal bufhidden=wipe
setlocal noswapfile
setlocal nobuflisted
setlocal nomodifiable
setlocal readonly
setlocal noundofile
setlocal foldmethod=manual
setlocal foldcolumn=1
setlocal wrap
setlocal linebreak
setlocal nonumber
setlocal norelativenumber

b:undo_ftplugin = 'setlocal buftype< bufhidden< swapfile< buflisted< modifiable< readonly< undofile< foldmethod< foldcolumn< wrap< linebreak< number< relativenumber<'
