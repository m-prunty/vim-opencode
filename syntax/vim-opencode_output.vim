" Syntax for the vim-opencode transcript buffer.

if exists('b:current_syntax')
  finish
endif

syntax match VimOpencodeHeading /^#\+ .*/
syntax match VimOpencodeUser /^> .*/
syntax match VimOpencodeTool /^\[[a-zA-Z0-9_.-]\+\]/
syntax match VimOpencodePath /<\=[A-Za-z0-9_./-]\+:\d\+\(:\d\+\)\=>\=/
syntax region VimOpencodeCode start=/^```/ end=/^```/ keepend

highlight default link VimOpencodeHeading Title
highlight default link VimOpencodeUser Identifier
highlight default link VimOpencodeTool Function
highlight default link VimOpencodePath Underlined
highlight default link VimOpencodeCode String

let b:current_syntax = 'vim-opencode_output'
