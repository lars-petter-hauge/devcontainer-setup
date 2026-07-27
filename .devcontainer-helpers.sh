export NODE_COMPILE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/node-compile-cache"

# Resolve and merge devcontainer config files.
# Finds the project's devcontainer.json, merges it with the global overlay
# (~/. devcontainer/overlay.json), injects SSH agent mounts and extra bind mounts.
# Returns: merged config path and temp dir path (for cleanup) on separate lines.
function _dc_config_paths() {
  local ws="$1"
  local no_ssh="$2"
  shift 2
  local -a extra_mounts=("$@")

  # Locate the base devcontainer.json (project-specific or global fallback)
  local config
  if [ -f "$ws/.devcontainer/devcontainer.json" ]; then
    config="$ws/.devcontainer/devcontainer.json"
  elif [ -f "$ws/.devcontainer.json" ]; then
    config="$ws/.devcontainer.json"
  else
    config="$HOME/.devcontainer/devcontainer.json"
  fi

  local overlay="$HOME/.devcontainer/overlay.json"
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
      extra_mounts_json=$(printf '%s\n' "${extra_mounts[@]}" | jq -R '[inputs // empty | "type=bind,source=\(.),target=\(.)"]' 2>/dev/null || echo "[]")
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

# Enter a devcontainer, creating it if needed.
# Builds the container on first run, then creates a tmux session whose panes
# connect into the container via docker exec. Splits are handled by the global
# default-command dispatcher (~/.tmux/default-cmd.sh).
#
# Usage:
#   dev              - use current directory as workspace
#   dev project      - use project as workspace
#   dev projA projB  - projA as workspace, projB mounted alongside
#   dev --no-ssh project  - without SSH agent access
function dev() {
  local no_ssh="0"
  if [[ "$1" == "--no-ssh" ]]; then
    no_ssh="1"
    shift
  fi

  # Resolve workspace and extra mount paths
  local ws
  local -a extra=()

  if (( $# == 0 )); then
    ws="$(pwd)"
  else
    ws="$(cd "$1" && pwd)"
    shift
    for arg in "$@"; do
      extra+=("$(cd "$arg" && pwd)")
    done
  fi

  # Find existing container or rebuild if --no-ssh requires a fresh one
  local container_id
  container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$ws")

  if [[ -n "$container_id" && "$no_ssh" == "1" ]]; then
    docker rm -f "$container_id" >/dev/null
    container_id=""
  fi

  # Build and start the container if not already running
  if [[ -z "$container_id" ]]; then
    local -a config_paths
    config_paths=("${(@f)$(_dc_config_paths "$ws" "$no_ssh" "${extra[@]}")}") || return 1
    local merged_config="${config_paths[1]}"
    local generated_config="${config_paths[2]}"

    echo "Config: $merged_config"
    read -r "?Press Enter to continue..."

    devcontainer up --workspace-folder "$ws" \
      --config "$merged_config" \
      --dotfiles-repository https://github.com/lars-petter-hauge/dotfiles \
      --dotfiles-install-command ./install.sh
    local exit_code=$?

    [[ -n "$generated_config" ]] && rm -rf "$generated_config"
    [[ $exit_code -ne 0 ]] && return $exit_code

    container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$ws")
  fi

  # Create convenience symlinks inside the container (~/projects/<name>)
  docker exec -u vscode "$container_id" mkdir -p /home/vscode/projects 2>/dev/null
  docker exec -u vscode "$container_id" ln -sfn "$ws" "/home/vscode/projects/$(basename "$ws")" 2>/dev/null
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
exec docker exec -it -e TERM="$TERM" -e "GH_TOKEN=\$GH_TOKEN" -u vscode $container_id zsh -lic "cd ~/projects/'$project_name' && exec zsh -li"
EOF
  chmod +x "$wrapper"

  # Create tmux session and switch to it
  [[ "$no_ssh" == "1" ]] && tmux kill-session -t "$session_name" 2>/dev/null

  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    tmux new-session -d -s "$session_name" \
      -e "DEVCONTAINER_ID=$container_id" \
      -e "DEVCONTAINER_NO_SSH=$no_ssh"
  fi
  tmux switch-client -t "$session_name"
}

# Remove a running devcontainer for the given workspace.
function rmdev() {
  local ws="${1:-.}"
  ws="$(cd "$ws" && pwd)"
  local container_id
  container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$ws")
  if [[ -n "$container_id" ]]; then
    docker rm -f "$container_id"
  else
    echo "No running devcontainer found for $ws"
  fi
}

