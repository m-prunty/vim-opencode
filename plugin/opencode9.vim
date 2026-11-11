vim9script

# opencode9.vim - a Vim 9.1-native OpenCode client.

if exists('g:loaded_opencode9')
  finish
endif
g:loaded_opencode9 = 1
g:opencode9_version = '0.1.0-dev'

if v:version < 901
  echohl ErrorMsg
  echomsg 'opencode9: Vim 9.1 or newer is required'
  echohl None
  finish
endif

import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/commands.vim' as commands

var user_config: any = get(g:, 'opencode9_config', {})
if type(user_config) != v:t_dict
  echohl ErrorMsg
  echomsg 'opencode9: g:opencode9_config must be a dictionary'
  echohl None
  finish
endif

try
  config.Setup(user_config)
catch
  echohl ErrorMsg
  echomsg 'opencode9: ' .. v:exception
  echohl None
  finish
endtry

# The completion function must be globally discoverable by -complete=customlist.
def g:Opencode9Complete(arglead: string, cmdline: string, cursorpos: number): list<string>
  return commands.Complete(arglead, cmdline, cursorpos)
enddef

command! -nargs=* -range -bang -complete=customlist,g:Opencode9Complete
      \ Opencode commands.Dispatch(<q-args>, [<line1>, <line2>], <bang>0)

highlight default link Opencode9Info MoreMsg
highlight default link Opencode9Warn WarningMsg
highlight default link Opencode9Error ErrorMsg
highlight default link Opencode9Muted Comment

# Stable plugin entry points. Users can map these without depending on defaults.
nnoremap <silent> <Plug>(opencode9-help) <Cmd>Opencode help<CR>
nnoremap <silent> <Plug>(opencode9-health) <Cmd>Opencode health<CR>
nnoremap <silent> <Plug>(opencode9-prompt) <Cmd>Opencode prompt<CR>
nnoremap <silent> <Plug>(opencode9-ask) <Cmd>Opencode ask<CR>
nnoremap <silent> <Plug>(opencode9-operator) <Cmd>Opencode operator<CR>
nnoremap <silent> <Plug>(opencode9-toggle) <Cmd>Opencode toggle<CR>

# Default mappings are opt-in. Only actions implemented by the current phase
# are mapped; <Plug> names remain stable for the rest.
if get(g:opencode9_config, 'default_mappings', false)
  var mappings = {
    help: '<Plug>(opencode9-help)',
    health: '<Plug>(opencode9-health)',
  }
  var keymaps = get(g:opencode9_config, 'keymaps', {})
  for [action, plug] in items(mappings)
    var key = get(keymaps, action, '')
    if key !=# '' && empty(maparg(key, 'n'))
      execute 'nnoremap <silent> ' .. key .. ' ' .. plug
    endif
  endfor
endif

augroup opencode9
  autocmd!
augroup END
