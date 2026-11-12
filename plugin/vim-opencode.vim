vim9script

# vim-opencode.vim - a Vim 9.1-native OpenCode client.

if exists('g:loaded_vim_opencode')
  finish
endif
g:loaded_vim_opencode = 1
g:vim_opencode_version = '0.1.0-dev'

if v:version < 901
  echohl ErrorMsg
  echomsg 'vim-opencode: Vim 9.1 or newer is required'
  echohl None
  finish
endif

import autoload 'vim_opencode/config.vim' as config
import autoload 'vim_opencode/commands.vim' as commands
import autoload 'vim_opencode/prompt.vim' as prompt
import autoload 'vim_opencode/permissions.vim' as permissions
import autoload 'vim_opencode/ui/diff.vim' as diff
import autoload 'vim_opencode/server.vim' as server
import autoload 'vim_opencode/ui/panel.vim' as panel
import autoload 'vim_opencode/quickchat.vim' as quickchat
import autoload 'vim_opencode/tabs.vim' as tabs

def g:VimOpencodeShutdown()
  server.Shutdown()
enddef

var user_config: any = get(g:, 'vim_opencode_config', {})
if type(user_config) != v:t_dict
  echohl ErrorMsg
  echomsg 'vim-opencode: g:vim_opencode_config must be a dictionary'
  echohl None
  finish
endif

try
  config.Setup(user_config)
catch
  echohl ErrorMsg
  echomsg 'vim-opencode: ' .. v:exception
  echohl None
  finish
endtry

# The completion function must be globally discoverable by -complete=customlist.
def g:VimOpencodeComplete(arglead: string, cmdline: string, cursorpos: number): list<string>
  return commands.Complete(arglead, cmdline, cursorpos)
enddef

command! -nargs=* -range -bang -complete=customlist,g:VimOpencodeComplete
      \ Opencode commands.Dispatch(<q-args>, [<line1>, <line2>], <bang>0)

highlight default link VimOpencodeInfo MoreMsg
highlight default link VimOpencodeWarn WarningMsg
highlight default link VimOpencodeError ErrorMsg
highlight default link VimOpencodeMuted Comment
highlight default link VimOpencodeUser Identifier
highlight default link VimOpencodeTool Function
highlight default link VimOpencodeReasoning Comment

# Stable plugin entry points. Users can map these without depending on defaults.
nnoremap <silent> <Plug>(vim-opencode-help) <Cmd>Opencode help<CR>
nnoremap <silent> <Plug>(vim-opencode-health) <Cmd>Opencode health<CR>
nnoremap <silent> <Plug>(vim-opencode-prompt) <Cmd>Opencode prompt<CR>
nnoremap <silent> <Plug>(vim-opencode-ask) <Cmd>Opencode ask<CR>
xnoremap <silent> <Plug>(vim-opencode-prompt) :Opencode prompt<CR>
xnoremap <silent> <Plug>(vim-opencode-ask) :Opencode ask<CR>
nnoremap <expr> <Plug>(vim-opencode-operator) prompt.OperatorExpr('@this')
nnoremap <silent> <Plug>(vim-opencode-toggle) <Cmd>Opencode toggle<CR>

# Default mappings are opt-in. Only actions implemented by the current phase
# are mapped; <Plug> names remain stable for the rest.
if get(g:vim_opencode_config, 'default_mappings', false)
  var mappings = {
    help: '<Plug>(vim-opencode-help)',
    health: '<Plug>(vim-opencode-health)',
    prompt: '<Plug>(vim-opencode-prompt)',
    ask: '<Plug>(vim-opencode-ask)',
    toggle: '<Plug>(vim-opencode-toggle)',
  }
  var keymaps = get(g:vim_opencode_config, 'keymaps', {})
  for [action, plug] in items(mappings)
    var key = get(keymaps, action, '')
    if key !=# '' && empty(maparg(key, 'n'))
      execute 'nnoremap <silent> ' .. key .. ' ' .. plug
    endif
  endfor
endif

panel.Setup()
permissions.Setup()
diff.Setup()
quickchat.Setup()
tabs.Setup()

augroup vim-opencode
  autocmd!
  autocmd VimLeavePre * call g:VimOpencodeShutdown()
augroup END
