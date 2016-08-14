#!/bin/sh
. ./init.sh

if ! command -V git 2>/dev/null >/dev/null || ! command -V vcsh 2>/dev/null >/dev/null; then
  ./cli-tools.sh
fi

echo "Cloning github.com/hgto/dots repo"
vcsh clone https://github.com/hgto/dots dots
vcsh clone https://github.com/hgto/dots dots

echo "Checking out master"
vcsh dots branch master origin/master
vcsh dots checkout master -- .

if [ "$GXG" -eq 1 ]; then
  vcsh dots remote rm origin
  vcsh dots remote add origin gh:hgto/dots
fi
