# devcontainer-setup

Orchestration for my devcontainer workflow — a tmux-based approach where each
project gets its own tmux session with panes that exec into a devcontainer.

## Prerequisites

Install host dependencies with Homebrew:

```sh
brew bundle install --file=Brewfile
```

This installs Docker, jq, and Node.js. Then install the devcontainer CLI:

```sh
npm install -g @devcontainers/cli
```

## Installation

Run the install script to symlink the helper files and configure tmux:

```sh
./install.sh
```

Then add the following to your shell rc file (e.g. `~/.zshrc`):

```sh
source "$HOME/.devcontainer-helpers.sh"
```

## Usage

The `dev` function manages devcontainers via tmux:

```sh
dev                        # List running devcontainers
dev .                      # Enter/create container for current directory
dev myproj                 # Enter/create container for ./myproj
dev projA projB            # projA as workspace, projB mounted alongside
dev --ssh myproj           # Start with SSH agent forwarded
```

When called without arguments, `dev` shows running devcontainers. When given a
project directory, it builds the container on first run (using the project's
`.devcontainer/devcontainer.json` or a default fallback), then creates a tmux
session whose panes connect into the container.

To remove a running devcontainer:

```sh
rmdev              # Remove container for current directory
rmdev myproj       # Remove container for ./myproj
```

## How it works

1. **Config merging** — The project's devcontainer config is deep-merged with
   `devcontainer-defaults/overlay.json`, which adds shared mounts (nix store,
   caches, zsh history), Docker-outside-of-Docker, and SSH agent forwarding.

2. **Dotfiles** — On first start, the container clones this repo and runs
   `devcontainer-install.sh`, which installs Nix, packages from
   `nix-packages.txt`, and the user's dotfiles.

3. **tmux integration** — Each project gets a tmux session. A per-session
   wrapper script (`/tmp/devcontainer-exec-<session>`) is picked up by
   `~/.tmux/default-cmd.sh` so that new panes automatically exec into the
   container.

4. **Persistent volumes** — Named Docker volumes preserve the Nix store,
   cargo registry, pip/npm caches, neovim data, and zsh history across
   container rebuilds.
