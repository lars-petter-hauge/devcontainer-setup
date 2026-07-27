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

# Symlink the helpers file so it can be sourced from a fixed path, regardless
# of where this repo is cloned.
target="$HOME/.devcontainer-helpers.sh"
source="$SETUP_DIR/.devcontainer-helpers.sh"

if [ -L "$target" ]; then
  unlink "$target"
elif [ -e "$target" ]; then
  mv "$target" "$target.bak"
fi

ln -s "$source" "$target"
echo "Linked .devcontainer-helpers.sh"

echo
echo "devcontainer-setup installed."
echo "Add the following line to your shell rc file to enable the 'dev' function:"
echo
echo "  source \"$target\""
echo
