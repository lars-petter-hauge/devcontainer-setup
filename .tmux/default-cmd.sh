#!/bin/sh
SESSION=$(tmux display-message -p '#{session_name}')
WRAPPER="/tmp/devcontainer-exec-$SESSION"
if [ -x "$WRAPPER" ]; then
  exec "$WRAPPER"
fi
exec ${SHELL:-/bin/zsh} -l
