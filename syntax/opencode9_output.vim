" Syntax for the opencode9 transcript buffer.

if exists('b:current_syntax')
  finish
endif

syntax match Opencode9Heading /^#\+ .*/
syntax match Opencode9User /^> .*/
syntax match Opencode9Tool /^\[[a-zA-Z0-9_.-]\+\]/
syntax match Opencode9Path /<\=[A-Za-z0-9_./-]\+:\d\+\(:\d\+\)\=>\=/
syntax region Opencode9Code start=/^```/ end=/^```/ keepend

highlight default link Opencode9Heading Title
highlight default link Opencode9User Identifier
highlight default link Opencode9Tool Function
highlight default link Opencode9Path Underlined
highlight default link Opencode9Code String

let b:current_syntax = 'opencode9_output'
