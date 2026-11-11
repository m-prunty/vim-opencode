#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vim_bin=${VIM:-vim}

for test_name in p0 p1 p2; do
  echo "== $test_name =="
  "$vim_bin" -Nu NONE -es -i NONE \
    --cmd "set runtimepath^=$root" \
    -S "$root/test/$test_name.vim"
done
