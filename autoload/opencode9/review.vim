vim9script

import autoload 'opencode9/util.vim' as util
import autoload 'opencode9/events.vim' as events

var comments: list<dict<any>> = []
var next_id = 0

export def Add(file: string, line: number, text: string, end_line: number = 0): string
  next_id += 1
  var id = 'review-' .. next_id
  comments->add({id: id, file: fnamemodify(file, ':p'), line: line, endLine: end_line > 0 ? end_line : line, text: text, stale: false})
  events.EmitLocal('review.pending', {commentID: id, file: file, line: line})
  return id
enddef

export def Remove(id: string)
  comments = filter(comments, (_, item: dict<any>) => item.id !=# id)
enddef

export def Clear()
  comments = []
enddef

export def List(): list<dict<any>>
  return comments
enddef

export def Text(): string
  var lines: list<string> = []
  for item in comments
    var file = item.file
    var cwd = util.Cwd()
    if stridx(file, cwd .. '/') == 0
      file = strpart(file, strlen(cwd) + 1)
    endif
    lines->add(printf('[review %s] %s:%d-%d %s', item.id, file, item.line, item.endLine, item.text))
  endfor
  return join(lines, "\n")
enddef

export def MarkSent()
  for item in comments
    item.stale = false
  endfor
enddef

export def AddCurrent(text: string): string
  return Add(expand('%:p'), line('.'), text)
enddef
