#!/bin/bash
set -e

SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_REPO="https://github.com/lars-petter-hauge/dotfiles"
DOTFILES_DIR="$HOME/dotfiles"

# Fix ownership of volume-mounted directories (Docker creates them as root)
if command -v sudo &>/dev/null; then
  sudo chown -R "$(id -u):$(id -g)" \
    /nix \
    "$HOME/.local" \
    "$HOME/.cargo" \
    "$HOME/.cache" \
    "$HOME/.npm" \
    "$HOME/.tmux" \
    "$HOME/.zsh_history_dir" \
    2>/dev/null || true
fi

# Install Nix if not present
if ! command -v nix &>/dev/null; then
  sh <(curl -L https://nixos.org/nix/install) --no-daemon
fi
. "$HOME/.nix-profile/etc/profile.d/nix.sh" 2>/dev/null || true

mkdir -p "$HOME/.config/nix"
echo "experimental-features = nix-command flakes" >"$HOME/.config/nix/nix.conf"

nix profile install $(sed 's/^/nixpkgs#/' "$SETUP_DIR/nix-packages.txt" | tr '\n' ' ')

if command -v rustup &>/dev/null && ! rustup show active-toolchain &>/dev/null; then
  rustup default stable
fi

# Clone (or update) the dotfiles repo and run its symlink install
if [ -d "$DOTFILES_DIR/.git" ]; then
  git -C "$DOTFILES_DIR" pull --ff-only
else
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi
"$DOTFILES_DIR/install.sh"
