vim9script

# P6 smoke test for deduplicated rich context and review comments.

import autoload 'opencode9/commands.vim' as commands
import autoload 'opencode9/config.vim' as config
import autoload 'opencode9/context.vim' as context
import autoload 'opencode9/review.vim' as review
import autoload 'opencode9/util.vim' as util

var failures: list<string> = []

def Check(condition: bool, message: string)
  if !condition
    failures->add(message)
  endif
enddef

try
  config.Setup({})
  var path = '/tmp/opencode/p6_context.txt'
  writefile(['one', 'two', 'three'], path)
  execute 'edit ' .. fnameescape(path)
  var ctx = context.Capture([1, 2])
  var first = context.Changed('p6', ctx)
  var second = context.Changed('p6', ctx)
  Check(has_key(first, 'file'), 'rich context should include the whole file')
  Check(empty(second), 'unchanged context should not be resent')
  setline(2, 'changed')
  var third = context.Changed('p6', ctx)
  Check(has_key(third, 'file') && has_key(third, 'cursor'), 'changed context should include changed items')
  context.ClearSent('p6')

  review.Clear()
  var id = review.Add(path, 2, 'Please simplify this line')
  Check(id ==# 'review-1', 'review id should be stable')
  Check(review.Text() =~# 'p6_context.txt:2-2 Please simplify', 'review text should include file and range')
  Check(len(review.List()) == 1, 'review list should contain one comment')
  review.Remove(id)
  Check(empty(review.List()), 'review remove should clear the comment')

  var table = commands.Table()
  Check(table.review.implemented, 'review command should be implemented')
catch
  failures->add('unexpected exception: ' .. util.ExceptionText())
endtry

if empty(failures)
  writefile(['P6 smoke test passed'], 'test/results/p6.txt')
  qa!
else
  writefile(failures, 'test/results/p6.txt')
  execute 'cquit 1'
endif
