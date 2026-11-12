vim9script

# P0 headless smoke test. Run through test/run.sh.

import autoload 'vim_opencode/config.vim' as config
import autoload 'vim_opencode/commands.vim' as commands
import autoload 'vim_opencode/health.vim' as health
import autoload 'vim_opencode/util.vim' as util

var failures: list<string> = []
var script_dir = fnamemodify(expand('<sfile>'), ':p:h')
var result_dir = script_dir .. '/results'

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

  # Plugin loading and command surface.
  Check(get(g:, 'loaded_vim_opencode', 0) == 1, 'plugin did not set g:loaded_vim_opencode')
  Check(exists(':Opencode') == 2, ':Opencode command is not defined')
  Check(type(g:vim_opencode_config) == v:t_dict, 'g:vim_opencode_config is not a dictionary')
  Check(g:vim_opencode_config.request_timeout_ms == 30000, 'default request timeout is wrong')
  Check(g:vim_opencode_config.panel.height == 20, 'default panel height is wrong')

  # Version, help and config commands produce useful output.
  CheckContains(execute('Opencode version'), 'vim-opencode.vim', 'version output')
  CheckContains(execute('Opencode help'), 'Usage: :Opencode', 'help output')
  CheckContains(execute('Opencode config log_level'), 'warn', 'config path output')

  # Completion stays local and suggests both commands and arguments.
  Check(index(commands.Complete('he', 'Opencode he', 11), 'help') >= 0, 'command completion missed help')
  Check(index(commands.Complete('', 'Opencode ', 9), 'server') >= 0, 'command completion missed server')
  var help_line = 'Opencode help d'
  Check(index(commands.Complete('d', help_line, strlen(help_line)), 'doc') >= 0, 'argument completion missed doc')

  # Configuration merging and validation.
  var merged = config.DeepMerge(config.Defaults, {panel: {height: 42}})
  Check(merged.panel.height == 42, 'deep merge did not override panel.height')
  Check(merged.panel.debounce_ms == 60, 'deep merge dropped sibling defaults')
  Check(config.Defaults.panel.height == 20, 'deep merge mutated the defaults')

  var threw = false
  try
    config.Setup({request_timeout_ms: -1})
  catch /vim-opencode config/
    threw = true
  endtry
  Check(threw, 'invalid configuration did not raise a config error')

  var bad_url_threw = false
  try
    config.Setup({server_url: 'ftp://example.com'})
  catch /vim-opencode config/
    bad_url_threw = true
  endtry
  Check(bad_url_threw, 'invalid server_url did not raise a config error')

  # Restore a known-good configuration for the remaining checks.
  config.Setup({})

  # Utility behavior used by later phases.
  Check(util.UrlEncode('a b/c') ==# 'a%20b%2Fc', 'URL encoding is wrong')
  Check(util.VersionAtLeast('0.2.1', '0.2.0'), 'version comparison missed a newer version')
  Check(!util.VersionAtLeast('0.1.9', '0.2'), 'version comparison accepted an older version')
  Check(util.JsonDecode(util.JsonEncode({a: 1})).a == 1, 'JSON round trip failed')

  # Health checks run and report the P0 state.
  var report = health.Report()
  Check(!empty(report), 'health report is empty')
  CheckContains(join(report, "\n"), 'config: loaded', 'health report')
  CheckContains(execute('Opencode health'), 'vim-opencode.vim health', 'health command output')

  # Imported modules must compile under Vim 9.1.
  execute 'defcompile'
catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

if isdirectory(result_dir) == 0
  mkdir(result_dir, 'p')
endif

if empty(failures)
  writefile(['P0 smoke test passed'], result_dir .. '/p0.txt')
  qa!
else
  writefile(failures, result_dir .. '/p0.txt')
  execute 'cquit 1'
endif
