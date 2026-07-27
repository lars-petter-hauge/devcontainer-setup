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

# Symlink the global devcontainer config (default devcontainer.json + overlay.json)
target="$HOME/.devcontainer"
source="$SETUP_DIR/.devcontainer"

if [ -L "$target" ]; then
  unlink "$target"
elif [ -e "$target" ]; then
  mv "$target" "$target.bak"
fi

ln -s "$source" "$target"
echo "Linked .devcontainer"

echo
echo "devcontainer-setup installed."
echo "Add the following line to your shell rc file to enable the 'dev' function:"
echo
echo "  source \"$SETUP_DIR/.devcontainer-helpers.sh\""
echo
