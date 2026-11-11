vim9script

# Settings for the opencode9 prompt input buffer.

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

b:undo_ftplugin = 'setlocal buftype< bufhidden< swapfile< buflisted< number< relativenumber< undofile< wrap< linebreak<'
