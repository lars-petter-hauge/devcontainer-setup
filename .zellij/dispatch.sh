#!/bin/sh
SESSION="$ZELLIJ_SESSION_NAME"
WRAPPER="/tmp/devcontainer-exec-$SESSION"
if [ -x "$WRAPPER" ]; then
  exec "$WRAPPER"
fi
exec ${SHELL:-/bin/zsh} -l
