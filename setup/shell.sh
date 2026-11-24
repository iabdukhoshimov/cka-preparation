#!/usr/bin/env bash
# Wire the exam-style shell + vim config into your user account (no sudo needed).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LINE="[ -f \"$REPO/setup/cka.bashrc\" ] && source \"$REPO/setup/cka.bashrc\""
if ! grep -qF "cka.bashrc" ~/.bashrc 2>/dev/null; then
  printf '\n# CKA practice environment\n%s\n' "$LINE" >> ~/.bashrc
  echo ">> Added cka.bashrc to ~/.bashrc"
else
  echo ">> ~/.bashrc already sources cka.bashrc"
fi

if [ ! -e ~/.vimrc ]; then
  ln -s "$REPO/setup/vimrc" ~/.vimrc
  echo ">> Linked ~/.vimrc -> setup/vimrc"
else
  echo ">> ~/.vimrc exists, left untouched (see setup/vimrc for the exam settings)"
fi
