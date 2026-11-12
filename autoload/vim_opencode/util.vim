vim9script

# Shared helpers for vim-opencode.vim.

const LOG_LEVELS: dict<number> = {
  silent: 0,
  error: 1,
  warn: 2,
  info: 3,
  debug: 4,
}

# Return the supported log levels and their numeric priorities.
export def LogLevels(): dict<number>
  return copy(LOG_LEVELS)
enddef

# Encode a JSON-compatible value.
export def JsonEncode(value: any): string
  try
    return json_encode(value)
  catch
    throw 'vim-opencode: cannot encode JSON: ' .. v:exception
  endtry
  return ''
enddef

# Decode a JSON string, raising a readable error on invalid input.
export def JsonDecode(text: string): any
  if text ==# ''
    return v:null
  endif
  try
    return json_decode(text)
  catch
    throw 'vim-opencode: invalid JSON: ' .. v:exception
  endtry
  return v:null
enddef

# Percent-encode every byte that is not an RFC 3986 unreserved character.
export def UrlEncode(value: string): string
  var out = ''
  for i in range(strlen(value))
    var char = strpart(value, i, 1)
    if char =~# '[A-Za-z0-9_.~-]'
      out ..= char
    else
      out ..= printf('%%%02X', char2nr(char))
    endif
  endfor
  return out
enddef

# Expand ~, environment variables and wildcards in a path.
export def ExpandPath(path: string): string
  if path ==# ''
    return ''
  endif
  return expand(path)
enddef

# Return an absolute path without a trailing separator.
export def NormalizePath(path: string): string
  if path ==# ''
    return ''
  endif
  var normalized = fnamemodify(expand(path), ':p')
  if has('win32')
    normalized = substitute(normalized, '\\', '/', 'g')
  endif
  while strlen(normalized) > 1 && normalized =~# '/$'
    normalized = strpart(normalized, 0, strlen(normalized) - 1)
  endwhile
  return normalized
enddef

# Return the current working directory in normalized form.
export def Cwd(): string
  return NormalizePath(getcwd())
enddef

# Return vim-opencode's per-user state directory, honoring XDG_STATE_HOME.
export def StateDir(): string
  var base = getenv('XDG_STATE_HOME')
  if base ==# ''
    base = expand('~/.local/state')
  endif
  return NormalizePath(base .. '/vim-opencode')
enddef

# Create a unique temporary file name.
export def TempFile(prefix: string = 'vim-opencode'): string
  return tempname() .. '-' .. prefix
enddef

# Create a directory and its parents when it does not exist.
export def EnsureDir(path: string)
  if path ==# '' || isdirectory(path)
    return
  endif
  mkdir(path, 'p')
  if !isdirectory(path)
    throw 'vim-opencode: cannot create directory: ' .. path
  endif
enddef

# Escape and join a command argument list for display or a shell string.
export def ShellJoin(args: list<string>): string
  var escaped: list<string> = []
  for arg in args
    escaped->add(shellescape(arg))
  endfor
  return join(escaped, ' ')
enddef

# Return true when a program is available on PATH.
export def IsExecutable(name: string): bool
  return executable(name) == 1
enddef

# Compare dotted version strings. Missing components count as zero.
export def VersionAtLeast(actual: string, minimum: string): bool
  var left = VersionParts(actual)
  var right = VersionParts(minimum)
  var count = max([len(left), len(right)])
  for i in range(count)
    var a = i < len(left) ? left[i] : 0
    var b = i < len(right) ? right[i] : 0
    if a > b
      return true
    endif
    if a < b
      return false
    endif
  endfor
  return true
enddef

def VersionParts(version: string): list<number>
  var cleaned = matchstr(version, '^\d\+\(\.\d\+\)*')
  var parts: list<number> = []
  for part in split(cleaned, '\.')
    parts->add(str2nr(part))
  endfor
  return parts
enddef

# Emit a message at the requested level. Errors also reach the message area.
export def Log(level: string, message: string)
  var config = get(g:, 'vim_opencode_config', {})
  var configured = get(config, 'log_level', 'warn')
  var actual_level = has_key(LOG_LEVELS, level) ? level : 'info'
  var threshold = has_key(LOG_LEVELS, configured) ? LOG_LEVELS[configured] : LOG_LEVELS.warn
  if LOG_LEVELS[actual_level] > threshold
    return
  endif

  var line = strftime('%Y-%m-%dT%H:%M:%S') .. ' [' .. actual_level .. '] ' .. message
  var log_file = get(config, 'log_file', '')
  if log_file !=# ''
    try
      EnsureDir(fnamemodify(ExpandPath(log_file), ':h'))
      writefile([line], ExpandPath(log_file), 'a')
    catch
      # Logging must never break the editor.
    endtry
  endif

  if actual_level ==# 'error'
    EchoError(message)
  elseif actual_level ==# 'warn'
    EchoWarn(message)
  endif
enddef

export def EchoError(message: string)
  echohl ErrorMsg
  echomsg 'vim-opencode: ' .. message
  echohl None
enddef

export def EchoWarn(message: string)
  echohl WarningMsg
  echomsg 'vim-opencode: ' .. message
  echohl None
enddef

export def EchoInfo(message: string)
  echomsg 'vim-opencode: ' .. message
enddef

# Return true for strings that start with a prefix.
export def StartsWith(value: string, prefix: string): bool
  return strpart(value, 0, strlen(prefix)) ==# prefix
enddef

# Format an exception with its throw point when available.
export def ExceptionText(): string
  if v:throwpoint ==# ''
    return v:exception
  endif
  return v:exception .. ' (' .. v:throwpoint .. ')'
enddef
