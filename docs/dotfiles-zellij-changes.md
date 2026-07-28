# Required changes in `lars-petter-hauge/dotfiles` for the Zellij migration

This repo's switch from tmux to Zellij (see `zellij-migration` branch) requires
matching changes in the `dotfiles` repo, since `devcontainer-install.sh` clones
it and runs its `install.sh` on every container build.

## `install.sh`

- `required_tools`: replace `tmux` with `zellij`.
- `files` symlink list: replace `.tmux.conf` with the new Zellij config, e.g.
  `.config/zellij/config.kdl` and `.config/zellij/layouts/devcontainer.kdl`
  (the layout that runs the dispatcher script as the first pane — see this
  repo's `.tmux/default-cmd.sh` equivalent).
- Remove the TPM bootstrap block entirely (`git clone tmux-plugins/tpm`,
  `install_plugins`, the `nord.tmux` shebang patch, and the
  `tmux-thumbs` cargo build). Zellij doesn't use TPM; plugins/themes are
  configured directly in `config.kdl` (Zellij ships a `nord` theme built in,
  so the nordtheme/tmux plugin can likely just be dropped).

## `.tmux.conf` → new `.config/zellij/config.kdl` (+ layout file)

Port these behaviors, all currently defined in `.tmux.conf`:

- Prefix key `C-Space`, vi-style copy mode, mouse mode → Zellij equivalents
  in `keybinds`/`ui` config sections.
- Pane split keys (`v`/`h`), pane resize keys, vim-tmux-navigator-style
  `C-h/j/k/l` pane navigation → Zellij `keybinds`.
- `nordtheme/tmux` colors → Zellij's built-in `nord` theme (`theme "nord"`).
- `tmux-thumbs` (fast text selection) → no direct built-in Zellij
  equivalent; either drop it or find/vendor a Zellij plugin.
- Pane border title showing `@custom_pane_title` → Zellij pane titles
  (`pane_titles` config / `rename-pane` action).
- **Status bar container/SSH indicator** (`#{?DEVCONTAINER_ID,...}`, reading
  the `DEVCONTAINER_ID`/`DEVCONTAINER_NO_SSH` env vars) — Zellij's status
  bar is a compiled plugin, not a shell format string, so this can't be
  ported directly. Simplest approach: have the dispatcher script itself call
  `zellij action rename-tab`/`rename-pane` with a `🐳`/`🐳🔒` marker instead of
  relying on a status-bar plugin.

## `.zshrc`

No tmux references today, so likely no changes needed — confirm nothing
elsewhere in the dotfiles repo assumes a tmux session is active (e.g. via
`$TMUX`).
