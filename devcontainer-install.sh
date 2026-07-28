#!/bin/bash
set -e

SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_REPO="https://github.com/lars-petter-hauge/dotfiles"
DOTFILES_DIR="$HOME/dotfiles"

# Fix ownership of volume-mounted directories (Docker creates them as root
# on first use). Only chown -R when the top-level dir isn't already owned by
# the current user, so we don't re-walk large/growing volumes (like
# ~/.copilot, which accumulates many small files over time) on every start.
if command -v sudo &>/dev/null; then
  for dir in \
    /nix \
    "$HOME/.local" \
    "$HOME/.cargo" \
    "$HOME/.cache" \
    "$HOME/.npm" \
    "$HOME/.copilot" \
    "$HOME/.zsh_history_dir"; do
    [ -e "$dir" ] || continue
    owner="$(stat -c '%u' "$dir" 2>/dev/null)"
    [ "$owner" = "$(id -u)" ] || sudo chown -R "$(id -u):$(id -g)" "$dir" 2>/dev/null || true
  done
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
