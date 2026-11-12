vim9script

# Minimal, safe single-file edit review. The proposed text is shown in a
# scratch split; accepting is the only operation that writes the target file.

import autoload 'vim_opencode/events.vim' as events
import autoload 'vim_opencode/util.vim' as util

var active: dict<any> = {}
var original_buf = -1
var proposed_buf = -1
var original_win = 0
var proposed_win = 0
var installed = false

export def Setup()
  if installed
    return
  endif
  installed = true
  events.AddListener(OnEvent)
enddef

export def Current(): dict<any>
  return active
enddef

export def Set(file: string, text: string, request_id: string = ''): bool
  var path = fnamemodify(file, ':p')
  if path ==# '' || !filereadable(path)
    util.EchoError('cannot review edit: file is not readable')
    return false
  endif
  active = {file: path, text: text, requestID: request_id}
  return true
enddef

export def Open()
  if empty(active)
    util.EchoInfo('no active edit diff')
    return
  endif
  if !has('diff')
    util.EchoError('Vim was built without +diff')
    return
  endif
  var path = active.file
  original_buf = bufnr('%')
  execute 'aboveleft split ' .. fnameescape(path)
  original_win = win_getid()
  execute 'belowright split'
  proposed_win = win_getid()
  proposed_buf = bufadd('vim-opencode://proposed/' .. fnamemodify(path, ':t'))
  bufload(proposed_buf)
  setbufvar(proposed_buf, '&buftype', 'nofile')
  setbufvar(proposed_buf, '&bufhidden', 'wipe')
  setbufvar(proposed_buf, '&filetype', getbufvar(original_buf, '&filetype'))
  setbufvar(proposed_buf, '&modifiable', true)
  setbufline(proposed_buf, 1, split(active.text, '\n', 1))
  execute 'buffer ' .. proposed_buf
  setlocal nomodifiable
  setlocal readonly
  diffthis
  win_gotoid(original_win)
  diffthis
  win_gotoid(proposed_win)
  InstallMappings()
enddef

export def Accept()
  if empty(active)
    util.EchoError('no active edit diff')
    return
  endif
  var text = active.text
  if proposed_buf > 0 && bufloaded(proposed_buf)
    var lines = getbufline(proposed_buf, 1, '$')
    text = join(lines, "\n")
  endif
  writefile(split(text, '\n', 1), active.file)
  Close()
  events.EmitLocal('diff.accepted', {file: active.file, requestID: get(active, 'requestID', '')})
  active = {}
enddef

export def Reject()
  if empty(active)
    return
  endif
  var file = active.file
  var request_id = get(active, 'requestID', '')
  Close()
  active = {}
  events.EmitLocal('diff.rejected', {file: file, requestID: request_id})
enddef

export def Close()
  for win in [proposed_win, original_win]
    if win > 0 && win_id2win(win) > 0
      win_gotoid(win)
      diffoff!
      close
    endif
  endfor
  proposed_win = 0
  original_win = 0
  proposed_buf = -1
  original_buf = -1
enddef

def InstallMappings()
  execute 'nnoremap <buffer><silent> <Leader>da <Cmd>call g:VimOpencodeDiffAccept()<CR>'
  execute 'nnoremap <buffer><silent> <Leader>dr <Cmd>call g:VimOpencodeDiffReject()<CR>'
enddef

def OnEvent(event: any)
  var kind = get(event, 'type', '')
  if kind !=# 'session.diff' && kind !=# 'file.edited' && kind !=# 'edit.proposed'
    return
  endif
  var data = get(event, 'data', {})
  if type(data) != v:t_dict
    return
  endif
  var file = get(data, 'file', get(data, 'path', ''))
  var text = get(data, 'text', get(data, 'content', ''))
  if type(file) == v:t_string && type(text) == v:t_string && file !=# ''
    Set(file, text, get(data, 'requestID', ''))
    events.EmitLocal('diff.pending', {file: file})
  endif
enddef

def g:VimOpencodeDiffAccept()
  Accept()
enddef

def g:VimOpencodeDiffReject()
  Reject()
enddef
