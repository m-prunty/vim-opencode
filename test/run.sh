#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vim_bin=${VIM:-vim}

exec "$vim_bin" -Nu NONE -es -i NONE \
  --cmd "set runtimepath^=$root" \
  -S "$root/test/p0.vim"
