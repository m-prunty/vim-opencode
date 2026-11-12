vim9script

# GUI smoke test: popups, styling, keymaps and palette dispatch.
# Run through test/run.sh as `p11`.

import autoload 'vim_opencode/config.vim' as config
import autoload 'vim_opencode/commands.vim' as commands
import autoload 'vim_opencode/ui/style.vim' as style
import autoload 'vim_opencode/ui/popup.vim' as popup
import autoload 'vim_opencode/ui/palette.vim' as palette
import autoload 'vim_opencode/util.vim' as util

var failures: list<string> = []

def Check(condition: bool, message: string)
  if !condition
    failures->add(message)
  endif
enddef

def CheckContains(haystack: string, needle: string, message: string)
  Check(stridx(haystack, needle) >= 0, message .. ' (missing "' .. needle .. '")')
enddef

try
  runtime plugin/vim-opencode.vim

  # GUI config defaults and validation.
  var cfg = config.Get()
  Check(has_key(cfg, 'gui'), 'gui section missing from config')
  Check(cfg.gui.popup_border ==# 'rounded', 'default popup_border is not rounded')
  Check(cfg.gui.default_position ==# 'right', 'default default_position is not right')
  Check(cfg.gui.colors == v:true, 'default colors is not true')
  Check(cfg.gui.preview_width == 60, 'default preview_width is not 60')

  # Validation rejects bad border values.
  var threw = false
  try
    config.Setup({gui: {popup_border: 'double'}})
  catch /vim-opencode config/
    threw = true
  endtry
  Check(threw, 'invalid popup_border did not raise')
  config.Setup({})

  # Style helpers derive colors from highlight groups.
  Check(type(style.GetColor) == v:t_func, 'GetColor is not a function')
  Check(type(style.KeyLabel) == v:t_func, 'KeyLabel is not a function')
  Check(style.KeyLabel({'key': '<C-x>'}) ==# 'C-X', 'KeyLabel C-X wrong')
  Check(style.KeyLabel({'key': '<A-s>'}) ==# 'A-S', 'KeyLabel A-S wrong')
  Check(style.KeyLabel({'key': '<CR>'}) ==# 'Enter', 'KeyLabel CR wrong')
  Check(style.KeyLabels({'keys': ['<C-p>', '<C-q>']}) ==# 'C-P C-Q', 'KeyLabels wrong')

  # Popup runner exists and falls back gracefully without a visible display.
  Check(type(popup.Run) == v:t_func, 'popup.Run is not a function')
  Check(type(popup.CloseAll) == v:t_func, 'popup.CloseAll is not a function')

  # Palette dispatches and lists commands.
  Check(type(palette.Palette) == v:t_func, 'palette.Palette is not a function')
  var src = palette.Source()
  Check(!empty(src), 'palette source is empty')
  var found_help = 0
  for entry in src
    if get(entry, 'name', '') ==# 'help'
      found_help = 1
      break
    endif
  endfor
  Check(found_help == 1, 'palette source does not contain help command')

  # Default keymap chords are registered in config defaults.
  var defaults = config.Defaults
  Check(defaults.keymaps.open ==# '<Leader>oo', 'open keymap default wrong')
  Check(defaults.keymaps.explain ==# '<Leader>ox', 'explain keymap default wrong')
  Check(defaults.keymaps.palette ==# '<Leader>ocp', 'palette keymap default wrong')
  Check(defaults.keymaps.session_list ==# '<Leader>osl', 'session_list keymap default wrong')
  Check(defaults.keymaps.server_connect ==# '<Leader>osc', 'server_connect keymap default wrong')

  # Imported modules compile under Vim 9.1.
  execute 'defcompile'
catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

var script_dir = fnamemodify(expand('<sfile>'), ':p:h')
var result_dir = script_dir .. '/results'

if isdirectory(result_dir) == 0
  mkdir(result_dir, 'p')
endif

if empty(failures)
  writefile(['GUI smoke test passed'], result_dir .. '/p11.txt')
  qa!
else
  writefile(failures, result_dir .. '/p11.txt')
  execute 'cquit 1'
endif
