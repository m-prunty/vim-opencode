vim9script

# P7 smoke test for command registration and cancellation safety.

import autoload 'opencode9/commands.vim' as commands
import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/quickchat.vim' as quickchat
import autoload 'opencode9/util.vim' as util

var failures: list<string> = []

def Check(condition: bool, message: string)
  if !condition
    failures->add(message)
  endif
enddef

try
  config.Setup({})
  var path = '/tmp/opencode/p7_quickchat.txt'
  writefile(['keep this line', 'keep this too'], path)
  execute 'edit ' .. fnameescape(path)
  var before = getbufline(bufnr('%'), 1, '$')
  Check(!quickchat.Active(), 'quick chat should start inactive')
  quickchat.Cancel()
  Check(getbufline(bufnr('%'), 1, '$') ==# before, 'cancel while idle must not change the buffer')
  var table = commands.Table()
  Check(table.quickchat.implemented, 'quickchat command should be implemented')
catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

if empty(failures)
  writefile(['P7 smoke test passed'], 'test/results/p7.txt')
  qa!
else
  writefile(failures, 'test/results/p7.txt')
  execute 'cquit 1'
endif
