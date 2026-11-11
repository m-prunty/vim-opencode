vim9script

# OpenCode V1 protocol adapter stub. Implemented in P9.

const MESSAGE = 'OpenCode V1 is not supported yet (planned for P9)'

export def Probe(conn: any, on_success: any, on_error: any): number
  Fail(on_error)
  return 0
enddef

export def Subscribe(conn: any, on_event: any, on_error: any, on_close: any): number
  Fail(on_error)
  return 0
enddef

def Fail(on_error: any)
  if type(on_error) == v:t_func
    call(on_error, [MESSAGE, -1, 0])
  elseif type(on_error) == v:t_string && on_error !=# ''
    call(on_error, [MESSAGE, -1, 0])
  endif
enddef
