#!/bin/bash
set -e

SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"

required_tools=(docker jq devcontainer)

missing=()
for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    missing+=("$tool")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing required tools: ${missing[*]}"
  echo "Install docker/jq with: brew bundle install --file=\"$SETUP_DIR/Brewfile\""
  echo "Install the devcontainer CLI with: npm install -g @devcontainers/cli"
  exit 1
fi

# Symlink files that must live at a fixed path, regardless of where this repo
# is cloned: the helpers file (sourced from shell rc) and the tmux
# default-command script which dev()
# relies on to attach panes inside devcontainers.
files=(
  .devcontainer-helpers.sh
  .tmux/default-cmd.sh
  .tmux/devcontainer.conf
)

for file in "${files[@]}"; do
  target="$HOME/$file"
  source="$SETUP_DIR/$file"

  if [ -L "$target" ]; then
    unlink "$target"
  elif [ -e "$target" ]; then
    mv "$target" "$target.bak"
  fi

  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  echo "Linked $file"
done

TMUX_CONF="$HOME/.tmux.conf"
SOURCE_LINE="source-file ~/.tmux/devcontainer.conf"
if [ -f "$TMUX_CONF" ] && grep -qF "$SOURCE_LINE" "$TMUX_CONF"; then
  echo "tmux already configured."
else
  echo
  echo "The tmux default-command needs to be configured for devcontainer panes."
  printf "Add '%s' to %s? [y/N] " "$SOURCE_LINE" "$TMUX_CONF"
  read -r answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    printf '%s\n' "$SOURCE_LINE" >>"$TMUX_CONF"
    echo "Done."
  else
    echo "Skipped. You can add it manually later:"
    echo "  echo '$SOURCE_LINE' >> $TMUX_CONF"
  fi
fi

echo
echo "devcontainer-setup installed."
echo "Add the following line to your shell rc file to enable the 'dev' function:"
echo
echo "  source \"$HOME/.devcontainer-helpers.sh\""
echo
