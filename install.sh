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
# is cloned: the helpers file (sourced from shell rc), the Zellij dispatcher
# (referenced by bare name via PATH, see below), and the Zellij layout
# (mirrored at .config/zellij/layouts/ here so it lands in zellij's own
# layout dir and can be referenced by bare name, e.g. `default_layout
# "devcontainer"`).
files=(
  .devcontainer-helpers.sh
  .zellij/dispatch.sh
  .config/zellij/layouts/devcontainer.kdl
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
  echo "Linked $file -> $target"
done

echo
echo "devcontainer-setup installed."
echo "Add the following line to your shell rc file to enable the 'dev' function"
echo "and let zellij find the dispatcher by bare name (used in config.kdl):"
echo
echo "  source \"$HOME/.devcontainer-helpers.sh\""
echo "  export PATH=\"$HOME/.zellij:\$PATH\""
echo
echo "Zellij needs the following in your config.kdl so new panes/tabs attach"
echo "to the right devcontainer (e.g. via a local, untracked include file):"
echo
cat "$SETUP_DIR/.zellij/config-snippet.kdl"
echo
