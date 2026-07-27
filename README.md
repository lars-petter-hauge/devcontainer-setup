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
dev --worktree feature-x myproj  # Isolated container/session on a git worktree
```

When called without arguments, `dev` shows running devcontainers. When given a
project directory, it builds the container on first run (using the project's
`.devcontainer/devcontainer.json` or a default fallback), then creates a tmux
session whose panes connect into the container.

Since containers and tmux sessions are keyed off the workspace directory,
running multiple sessions on the same checkout means they all share one
container and file tree. To work on several things for the same project in
parallel without them interfering, use `--worktree`:

```sh
dev --worktree feature-x myproj
```

This creates (or reuses) a git worktree at `myproj-wt-feature-x` checked out
to `feature-x` (creating the branch if it doesn't exist yet), and uses that
worktree as the workspace — giving you a separate container, tmux session,
and working tree, while still sharing the global cache volumes (Nix store,
cargo, pip, npm, etc.) with your other devcontainers. `--worktree` requires
the target to already be a git repository; without it, `dev` works exactly
as before on any directory.

To remove a running devcontainer:

```sh
rmdev              # Remove container for current directory
rmdev myproj       # Remove container for ./myproj
rmdev --worktree feature-x myproj  # Remove container, tmux session, and worktree
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
