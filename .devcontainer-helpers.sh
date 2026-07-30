export NODE_COMPILE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/node-compile-cache"

# Directory this file lives in, resolved via the ~/.devcontainer-helpers.sh
# symlink. Falls back to the sourced path if not symlinked. Lets us find
# devcontainer-defaults/ alongside this file's real location.
DEVCONTAINER_SETUP_DIR="$(cd "$(dirname "$(readlink "$HOME/.devcontainer-helpers.sh" 2>/dev/null || echo "${(%):-%x}")")" && pwd)"

# Resolve and merge devcontainer config files.
# Finds the project's devcontainer.json, merges it with the default overlay
# (devcontainer-defaults/overlay.json), injects SSH agent mounts and extra bind mounts.
# Returns: merged config path and temp dir path (for cleanup) on separate lines.
function _dc_config_paths() {
  local ws="$1"
  local no_ssh="$2"
  shift 2
  local -a extra_mounts=("$@")

  # Locate the base devcontainer.json (project-specific or default fallback)
  local config
  if [ -f "$ws/.devcontainer/devcontainer.json" ]; then
    config="$ws/.devcontainer/devcontainer.json"
  elif [ -f "$ws/.devcontainer.json" ]; then
    config="$ws/.devcontainer.json"
  else
    config="$DEVCONTAINER_SETUP_DIR/devcontainer-defaults/devcontainer.json"
  fi

  local overlay="$DEVCONTAINER_SETUP_DIR/devcontainer-defaults/overlay.json"
  local merged_config="$config"
  local tmpdir=""
  if [ -f "$overlay" ]; then
    if ! command -v jq >/dev/null; then
      echo "devcontainer helper: jq is required to merge $overlay" >&2
      return 1
    fi

    tmpdir="$(mktemp -d)"
    merged_config="$tmpdir/devcontainer.json"

    local config_dir
    config_dir="$(cd "$(dirname "$config")" && pwd)"

    # Determine SSH socket path for forwarding into the container
    local ssh_source=""
    if [[ "$no_ssh" != "1" ]]; then
      if [[ "$(uname)" == "Darwin" ]]; then
        ssh_source="/run/host-services/ssh-auth.sock"
      elif [[ -n "$SSH_AUTH_SOCK" ]]; then
        ssh_source="$SSH_AUTH_SOCK"
      fi
    fi

    local extra_mounts_json="[]"
    if (( ${#extra_mounts[@]} > 0 )); then
      extra_mounts_json=$(printf '%s\n' "${extra_mounts[@]}" | jq -Rn '[inputs | select(. != "") | "type=bind,source=\(.),target=\(.)"]' 2>/dev/null || echo "[]")
    fi

    # Deep-merge base config with overlay: features, mounts, extensions, SSH, build context
    jq -s --arg ctx "$config_dir" --arg ssh "$ssh_source" --argjson extra "$extra_mounts_json" '
      .[0] as $base
      | .[1] as $overlay
      | $base * $overlay
      | .features = (($base.features // {}) * ($overlay.features // {}))
      | .mounts = (($base.mounts // []) + ($overlay.mounts // []) + $extra | unique)
      | if $ssh != "" then .mounts += ["type=bind,source=\($ssh),target=/ssh-agent"] | .containerEnv.SSH_AUTH_SOCK = "/ssh-agent" | .postStartCommand = "sudo chmod 666 /ssh-agent" else . end
      | .customizations.vscode.extensions = (($base.customizations.vscode.extensions // []) + ($overlay.customizations.vscode.extensions // []) | unique)
      | if .build then .build.context = $ctx | .build.dockerfile = ($ctx + "/" + .build.dockerfile) else . end
    ' "$config" "$overlay" > "$merged_config" || {
      rm -rf "$tmpdir"
      return 1
    }
  fi

  printf "%s\n%s\n" "$merged_config" "$tmpdir"
}

# Print dev's usage/help text.
function _dev_usage() {
  cat <<'EOF'
Usage: dev [options] [project] [extra...]

Enter a devcontainer, creating it if needed. Builds the container on first
run, then creates a tmux session whose panes connect into the container via
docker exec.

When called without arguments, always lists running devcontainers instead
of attaching, even if one is already running for the current directory.
Use `dev .` to explicitly target and attach to the current directory.

Arguments:
  project        Workspace directory to use (with --name, the repo the
                 session's worktree is created from)
  extra...       Additional project directories to mount alongside

Options:
  -h, --help              Show this help message and exit
  -s, --ssh, --enable-ssh Forward the SSH agent into the container (forces
                          a fresh container if one is already running)
  -n, --name NAME         Start (or reuse) an isolated session for this
                          project: its own git worktree, container, and tmux
                          session, so parallel sessions never touch each
                          other's files. Requires project to be a git repo.

Examples:
  dev                    List running containers (does not attach)
  dev .                  Use current directory as workspace
  dev myproj             Use ./myproj as workspace
  dev projA projB        projA as workspace, projB mounted alongside
  dev --ssh myproj       Start myproj with SSH agent access
  dev --name feature-x myproj
                         Start (or reuse) an isolated "feature-x" session for
                         ./myproj, running independently of any other session
EOF
}

# Sibling directory named after the repo + branch, so the session/wrapper
# naming (keyed off basename) stays collision-free without further changes.
# Usage: _dev_worktree_path <repo> <branch>
function _dev_worktree_path() {
  local repo="$1" branch="$2"
  local sanitized_branch="${branch//\//-}"
  echo "${repo}-wt-${sanitized_branch}"
}

# Ensure a git worktree exists for <branch> off <repo>, creating the branch
# if it doesn't exist yet. Reuses the worktree if already present. Prints the
# worktree path on stdout on success.
# Usage: _dev_ensure_worktree <repo> <branch>
function _dev_ensure_worktree() {
  local repo="$1" branch="$2"

  if ! git -C "$repo" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "dev: --name requires $repo to be a git repository" >&2
    return 1
  fi

  local wt_path
  wt_path="$(_dev_worktree_path "$repo" "$branch")"

  if [[ -e "$wt_path" ]]; then
    if ! git -C "$repo" worktree list --porcelain | grep -qF "worktree $wt_path"; then
      echo "dev: $wt_path already exists and is not a worktree of $repo" >&2
      return 1
    fi
  elif git -C "$repo" rev-parse --verify --quiet "$branch" &>/dev/null; then
    git -C "$repo" worktree add "$wt_path" "$branch" >&2 || return 1
  else
    git -C "$repo" worktree add -b "$branch" "$wt_path" >&2 || return 1
  fi

  echo "$wt_path"
}

# Strip a "-wt-<branch>" worktree suffix, if present, to get the base repo
# path for a workspace (used to find sibling worktree containers).
function _dev_repo_root() {
  local ws="$1"
  if [[ "$ws" == *-wt-* ]]; then
    echo "${ws%-wt-*}"
  else
    echo "$ws"
  fi
}

# Print any other running devcontainers that belong to the same repo as $ws
# (the repo itself plus any `dev --name` siblings of it), excluding $ws
# itself. Helps avoid forgetting about other sessions in flight.
function _dev_print_related_containers() {
  local ws="$1"
  local root
  root="$(_dev_repo_root "$ws")"

  local running
  running=$(docker ps --filter "label=devcontainer.local_folder" --format '{{.Label "devcontainer.local_folder"}}' 2>/dev/null)
  [[ -z "$running" ]] && return 0

  local -a related=()
  local folder
  while IFS= read -r folder; do
    [[ -z "$folder" || "$folder" == "$ws" ]] && continue
    if [[ "$folder" == "$root" || "$folder" == "$root"-wt-* ]]; then
      related+=("$folder")
    fi
  done <<< "$running"

  (( ${#related[@]} == 0 )) && return 0

  echo "Other running sessions for this repo:"
  local f
  for f in "${related[@]}"; do
    echo "  $(basename "$f")  ($f)"
  done
}

# Enter a devcontainer, creating it if needed.
# Builds the container on first run, then creates a tmux session whose panes
# connect into the container via docker exec. Splits are handled by the global
# default-command dispatcher (~/.tmux/default-cmd.sh).
#
# Usage: dev [-h|--help] [-s|--ssh|--enable-ssh] [project] [extra...]
# Run `dev --help` for details.
function dev() {
  local -A opts
  zparseopts -D -E -A opts -- h -help s -ssh -enable-ssh n: -name:

  if (( ${+opts[-h]} || ${+opts[--help]} )); then
    _dev_usage
    return 0
  fi

  # SSH forwarding is opt-in; explicitly requesting it forces a fresh
  # container so an already-running one picks up the SSH mount.
  local ssh_requested="0"
  if (( ${+opts[-s]} || ${+opts[--ssh]} || ${+opts[--enable-ssh]} )); then
    ssh_requested="1"
  fi
  local no_ssh="1"
  [[ "$ssh_requested" == "1" ]] && no_ssh="0"

  # --name is opt-in and only touches git under the hood (via a worktree);
  # without it dev behaves exactly as before, regardless of whether the
  # target is a git repo at all.
  local worktree_branch=""
  if (( ${+opts[-n]} )); then
    worktree_branch="${opts[-n]}"
  elif (( ${+opts[--name]} )); then
    worktree_branch="${opts[--name]}"
  fi

  # A worktree's .git is a file pointing at an absolute path back into the
  # main repo's .git/worktrees/<name> directory, so that path must also be
  # reachable inside the worktree's container. Bind-mount only the main
  # repo's .git dir (not its working tree) at the same absolute path, so the
  # worktree container stays isolated from the main checkout's files.
  local worktree_git_mount=""

  if [[ -n "$worktree_branch" ]]; then
    local repo_arg="."
    if (( $# > 0 )); then
      repo_arg="$1"
      shift
    fi

    local repo
    repo="$(cd "$repo_arg" && pwd)" || return 1

    local wt_path
    wt_path="$(_dev_ensure_worktree "$repo" "$worktree_branch")" || return 1
    worktree_git_mount="$repo/.git"

    set -- "$wt_path" "$@"
  fi

  # Resolve workspace and extra mount paths
  local ws
  local -a extra=()
  local explicit_ws=0

  if (( $# == 0 )); then
    ws="$(pwd)"
  else
    explicit_ws=1
    ws="$(cd "$1" && pwd)"
    shift
    for arg in "$@"; do
      extra+=("$(cd "$arg" && pwd)")
    done
  fi

  # Called with no arguments: always list running containers instead of
  # attaching, even if one happens to match cwd exactly. Use `dev .` to
  # explicitly target and attach to the current directory.
  if [[ "$explicit_ws" -eq 0 ]]; then
    local running
    running=$(docker ps --filter "label=devcontainer.local_folder" --format '{{.ID}}\t{{.Label "devcontainer.local_folder"}}' 2>/dev/null)
    if [[ -n "$running" ]]; then
      echo "Running containers:"
      echo "$running" | while IFS=$'\t' read -r cid folder; do
        local suffix=""
        [[ "$folder" == "$ws" ]] && suffix="  (current directory)"
        echo "  $(basename "$folder")  ($folder)$suffix"
      done
    else
      echo "No devcontainers running."
    fi
    return 0
  fi

  # Find existing container or rebuild if --ssh requires a fresh one
  local container_id
  container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$ws")

  if [[ -n "$container_id" && "$ssh_requested" == "1" ]]; then
    docker rm -f "$container_id" >/dev/null
    container_id=""
  fi

  # Build and start the container if not already running
  if [[ -z "$container_id" ]]; then
    local -a internal_mounts=()
    [[ -n "$worktree_git_mount" ]] && internal_mounts+=("$worktree_git_mount")

    local -a config_paths
    config_paths=("${(@f)$(_dc_config_paths "$ws" "$no_ssh" "${extra[@]}" "${internal_mounts[@]}")}") || return 1
    local merged_config="${config_paths[1]}"
    local generated_config="${config_paths[2]}"

    echo "Config: $merged_config"
    read -r "?Press Enter to continue..."

    devcontainer up --workspace-folder "$ws" \
      --config "$merged_config" \
      --dotfiles-repository https://github.com/lars-petter-hauge/devcontainer-setup \
      --dotfiles-target-path '~/devcontainer-setup' \
      --dotfiles-install-command ./devcontainer-install.sh
    local exit_code=$?

    [[ -n "$generated_config" ]] && rm -rf "$generated_config"
    [[ $exit_code -ne 0 ]] && return $exit_code

    container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$ws")
  fi

  # Inside the container each workspace has its own isolated filesystem, so
  # the "-wt-<branch>" suffix (needed on the host to keep worktree
  # directories collision-free) serves no purpose there. Use the repo's
  # plain basename for the in-container symlink/cwd, while keeping the
  # suffixed name for the tmux session and wrapper script, which are shared
  # across the host and must stay unique per parallel session.
  local display_name
  display_name="$(basename "$(_dev_repo_root "$ws")")"

  # Create convenience symlinks inside the container (~/projects/<name>)
  docker exec -u vscode "$container_id" mkdir -p /home/vscode/projects 2>/dev/null
  docker exec -u vscode "$container_id" ln -sfn "$ws" "/home/vscode/projects/$display_name" 2>/dev/null
  for p in "${extra[@]}"; do
    docker exec -u vscode "$container_id" ln -sfn "$p" "/home/vscode/projects/$(basename "$p")" 2>/dev/null
  done

  local project_name session_name
  project_name="$(basename "$ws")"
  session_name="$project_name"

  # Write the wrapper script that docker-execs into the container.
  # This is picked up by ~/.tmux/default-cmd.sh for all panes in this session.
  local wrapper="/tmp/devcontainer-exec-${session_name}"
  cat > "$wrapper" <<EOF
#!/bin/sh
GH_TOKEN=\$(cat ~/.config/gh-copilot-token 2>/dev/null)
exec docker exec -it -e TERM="$TERM" -e USER=vscode -e "GH_TOKEN=\$GH_TOKEN" -u vscode $container_id zsh -c 'export PATH="\$HOME/.nix-profile/bin:\$PATH"; cd ~/projects/'$display_name' && exec zsh -li'
EOF
  chmod +x "$wrapper"

  # Create tmux session and switch to it
  [[ "$ssh_requested" == "1" ]] && tmux kill-session -t "=$session_name" 2>/dev/null

  if ! tmux has-session -t "=$session_name" 2>/dev/null; then
    tmux new-session -d -s "$session_name" \
      -e "DEVCONTAINER_ID=$container_id" \
      -e "DEVCONTAINER_NO_SSH=$no_ssh"
  fi

  _dev_print_related_containers "$ws"

  tmux switch-client -t "=$session_name"
}

# Remove a running devcontainer for the given workspace.
# With -n/--name NAME, also kills the associated tmux session and removes
# the git worktree at <repo>-wt-<name> (created by `dev --name`).
function rmdev() {
  local -A opts
  zparseopts -D -E -A opts -- n: -name:

  local worktree_branch=""
  if (( ${+opts[-n]} )); then
    worktree_branch="${opts[-n]}"
  elif (( ${+opts[--name]} )); then
    worktree_branch="${opts[--name]}"
  fi

  local repo
  repo="$(cd "${1:-.}" && pwd)"

  local ws="$repo"
  if [[ -n "$worktree_branch" ]]; then
    ws="$(_dev_worktree_path "$repo" "$worktree_branch")"
  fi

  local container_id
  container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$ws")
  if [[ -n "$container_id" ]]; then
    docker rm -f "$container_id"
  else
    echo "No running devcontainer found for $ws"
  fi

  if [[ -n "$worktree_branch" ]]; then
    tmux kill-session -t "=$(basename "$ws")" 2>/dev/null
    git -C "$repo" worktree remove "$ws" 2>/dev/null ||
      echo "rmdev: could not remove worktree $ws (uncommitted changes? try: git -C $repo worktree remove --force $ws)"
  fi
}

