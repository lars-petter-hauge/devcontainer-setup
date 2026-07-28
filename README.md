# devcontainer-setup

Orchestration for my devcontainer workflow — a Zellij-based approach where each
project gets its own Zellij session with panes that exec into a devcontainer.

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

Run the install script to symlink the helper files and configure Zellij:

```sh
./install.sh
```

Then add the following to your shell rc file (e.g. `~/.zshrc`):

```sh
source "$HOME/.devcontainer-helpers.sh"
```

## Usage

The `dev` function manages devcontainers via Zellij:

```sh
dev                        # List running devcontainers
dev .                      # Enter/create container for current directory
dev myproj                 # Enter/create container for ./myproj
dev projA projB            # projA as workspace, projB mounted alongside
dev --ssh myproj           # Start with SSH agent forwarded
dev --name feature-x myproj  # Isolated session for a parallel task
```

When called without arguments, `dev` shows running devcontainers. When given a
project directory, it builds the container on first run (using the project's
`.devcontainer/devcontainer.json` or a default fallback), then creates a Zellij
session whose panes connect into the container.

Since containers and Zellij sessions are keyed off the workspace directory,
running multiple sessions on the same checkout means they all share one
container and file tree. To work on several things for the same project in
parallel without them interfering, give the session a name with `--name`:

```sh
dev --name feature-x myproj
```

This starts (or reuses) an isolated session called `feature-x` for `myproj`,
with its own container, Zellij session, and working tree — so it never touches
files from your other sessions on the same project, while still sharing the
global cache volumes (Nix store, cargo, pip, npm, etc.) with your other
devcontainers. Under the hood this is backed by a git worktree (and a branch
of the same name, created if it doesn't exist yet), so `--name` requires the
target to already be a git repository; without it, `dev` works exactly as
before on any directory.

To remove a running devcontainer:

```sh
rmdev              # Remove container for current directory
rmdev myproj       # Remove container for ./myproj
rmdev --name feature-x myproj  # Remove container, Zellij session, and worktree
```

## How it works

1. **Config merging** — The project's devcontainer config is deep-merged with
   `devcontainer-defaults/overlay.json`, which adds shared mounts (nix store,
   caches, zsh history), Docker-outside-of-Docker, and SSH agent forwarding.

2. **Dotfiles** — On first start, the container clones this repo and runs
   `devcontainer-install.sh`, which installs Nix, packages from
   `nix-packages.txt`, and the user's dotfiles.

3. **Zellij integration** — Each project gets a Zellij session. A per-session
   wrapper script (`/tmp/devcontainer-exec-<session>`) is picked up by
   `~/.zellij/dispatch.sh` so that new panes/tabs automatically exec into the
   container. Since Zellij has no tmux-style global default-command, this is
   wired up via a default layout and explicit keybind overrides for
   new-pane/new-tab (see `.zellij/config-snippet.kdl`, appended to the user's
   `~/.config/zellij/config.kdl` by `install.sh`).

4. **Persistent volumes** — Named Docker volumes preserve the Nix store,
   cargo registry, pip/npm caches, neovim data, GitHub Copilot CLI session
   data (`~/.copilot`, shared globally so `rmdev`/container rebuilds don't
   lose session history), and zsh history across container rebuilds.
