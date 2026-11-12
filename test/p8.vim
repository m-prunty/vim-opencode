vim9script

# P8 smoke test for persistent panel tab metadata.

import autoload 'vim_opencode/commands.vim' as commands
import autoload 'vim_opencode/config.vim' as config
import autoload 'vim_opencode/state.vim' as state
import autoload 'vim_opencode/tabs.vim' as tabs
import autoload 'vim_opencode/util.vim' as util

var failures: list<string> = []

def Check(condition: bool, message: string)
  if !condition
    failures->add(message)
  endif
enddef

try
  setenv('XDG_STATE_HOME', '/tmp/opencode/p8-state')
  config.Setup({})
  state.Reset('session-p8')
  tabs.Setup()
  var before = len(tabs.List())
  tabs.New('session-p8')
  Check(len(tabs.List()) == before + 1, 'new tab should be added')
  Check(tabs.Current().sessionID ==# 'session-p8', 'new tab should store its session')
  Check(tabs.Format(tabs.Current(), len(tabs.List())) =~# 'session-p8', 'tab formatting should show session')
  Check(filereadable(tabs.File()), 'tab metadata should be persisted')
  var saved = util.JsonDecode(join(readfile(tabs.File()), "\n"))
  Check(type(saved) == v:t_dict && type(get(saved, 'tabs', [])) == v:t_list, 'saved tab format should be valid')
  var table = commands.Table()
  Check(table.tab.implemented, 'tab command should be implemented')
  tabs.Close()
catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

if empty(failures)
  writefile(['P8 smoke test passed'], 'test/results/p8.txt')
  qa!
else
  writefile(failures, 'test/results/p8.txt')
  execute 'cquit 1'
endif
