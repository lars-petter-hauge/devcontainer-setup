#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Fix ownership of volume-mounted directories (Docker creates them as root)
if command -v sudo &>/dev/null; then
  sudo chown -R "$(id -u):$(id -g)" \
    /nix \
    "$HOME/.local" \
    "$HOME/.cargo" \
    "$HOME/.cache" \
    "$HOME/.npm" \
    "$HOME/.tmux" \
    2>/dev/null || true
fi

# Install Nix if not present
if ! command -v nix &>/dev/null; then
  sh <(curl -L https://nixos.org/nix/install) --no-daemon
fi
. "$HOME/.nix-profile/etc/profile.d/nix.sh" 2>/dev/null || true

mkdir -p "$HOME/.config/nix"
echo "experimental-features = nix-command flakes" >"$HOME/.config/nix/nix.conf"

nix profile install $(sed 's/^/nixpkgs#/' "$DOTFILES_DIR/nix-packages.txt" | tr '\n' ' ')

gh extension install github/gh-copilot 2>/dev/null || true

if command -v rustup &>/dev/null && ! rustup show active-toolchain &>/dev/null; then
  rustup default stable
fi

# Run shared install (symlinks, plugins)
"$DOTFILES_DIR/install_local.sh"
