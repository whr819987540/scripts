#!/usr/bin/env bash

# Unified remote entry point for the scripts in this repository.

_scripts_usage() {
    cat <<'EOF'
Usage:
  source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) <command> [args...]

Commands:
  set-proxy [proxy]
                Set proxy variables in the current shell (default: 127.0.0.1:7890)
  unset-proxy   Unset proxy variables in the current shell
  docker        Install Docker
  git           Install/configure Git, an SSH key, and the GitHub SSH proxy
  miniconda [silent] [installer-path]
                Install Miniconda without prompts; reuse an existing installer
  nvm           Install the latest stable nvm and Node.js releases
  zsh           Install and configure Zsh, Oh My Zsh, and plugins
  tmux          Install tmux 3.7b into ~/.local/bin, also for non-interactive
                shells, and write ~/.tmux.conf
  new-user      Create and configure a user
  add-authorized-key [public-key]
                Trust a quoted SSH public key for the current user
                (defaults to the key built into the script)
  zabbix-agent  Install and configure Zabbix Agent
  clash [serve] Install and run Clash; automatically adjust occupied ports
  gpu-docker-processes
                Show Docker containers for processes using NVIDIA GPUs
  gpu-interconnect-benchmark [work-dir] [gpu-devices]
                Build and run nvbandwidth, CUDA P2P, and NCCL benchmarks
  network-speed [interface] [interval]
                Monitor interval and cumulative average network speed
                (defaults: eth0, 1 second)
  container-mem [-n N]
                Analyze memory usage of the current container (top N, default: 15)
  claude-sync [--dry-run] [--all] [--source auto|github|gitee]
                Sync shared Claude Code settings and status line to this machine
                (asks before every change; requires Python 3.8+)
  help          Show this help

Environment:
  proxy         Proxy URL or host:port used by set-proxy
  config_url    Required by clash; URL of the Clash configuration file
  clash_download_url  
                Clash archive URL; defaults to this repository
  tmux_download_url
                tmux source tarball URL; defaults to the GitHub release
  SCRIPTS_BASE_URL
                Base URL used to download scripts (defaults to Gitee)
EOF
}

_scripts_download() {
    local script_name="$1"
    local destination="$2"
    local base_url="${SCRIPTS_BASE_URL:-https://gitee.com/hit_whr/scripts/raw/main}"

    command curl -fsSL "${base_url}/${script_name}" -o "$destination"
}

_scripts_is_sourced() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        [[ "${ZSH_EVAL_CONTEXT:-}" == *:file || "${ZSH_EVAL_CONTEXT:-}" == *:file:* ]]
    else
        [[ "${BASH_SOURCE[0]}" != "$0" ]]
    fi
}

# tmux_install.sh changes ~/.bashrc and ~/.zshenv, which this shell read before the
# install. Apply the changes here so `tmux` works right away: move ~/.local/bin to the
# front of PATH (it may be missing or come after /usr/bin), drop cached command
# locations, and run the UTF-8 locale fallback that the installer wrote.
_scripts_apply_tmux_install() {
    local local_bin="$HOME/.local/bin"
    local rest=":${PATH}:"

    while [[ "$rest" == *":${local_bin}:"* ]]; do
        rest="${rest/":${local_bin}:"/:}"
    done
    rest="${rest#:}"
    rest="${rest%:}"
    export PATH="${local_bin}${rest:+:${rest}}"
    hash -r 2>/dev/null
    eval "$(sed -n '/^# >>> UTF-8 locale for tmux /,/^# <<< UTF-8 locale for tmux /p' \
        "$HOME/.zshenv" 2>/dev/null)"
    printf '[scripts] Updated this shell: tmux is now %s, locale %s\n' \
        "$(command -v tmux)" "${LC_ALL:-${LC_CTYPE:-${LANG:-unset}}}"
}

_scripts_find_python() {
    local candidate

    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1 &&
            "$candidate" -c 'import sys; sys.exit(sys.version_info < (3,))' >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

_scripts_run() {
    local command_name="${1:-help}"
    local script_name=""
    local execution_mode="bash"
    local temp_file=""
    local python_cmd=""
    local exit_code=0

    case "$command_name" in
        set-proxy)
            script_name="proxy/set_proxy.sh"
            execution_mode="source"
            ;;
        unset-proxy)
            script_name="proxy/unset_proxy.sh"
            execution_mode="source"
            ;;
        docker)       script_name="docker/docker_install.sh" ;;
        git)          script_name="git/git_install_config.sh" ;;
        miniconda)    script_name="miniconda/miniconda_install.sh" ;;
        nvm)          script_name="nvm/nvm_install.sh" ;;
        zsh)          script_name="zsh/zsh_install.sh" ;;
        tmux)         script_name="tmux/tmux_install.sh" ;;
        new-user)     script_name="new-user/new_user.sh" ;;
        add-authorized-key) script_name="add-authorized-key/add_authorized_key.sh" ;;
        zabbix-agent) script_name="zabbix-agent/zabbix_agent.sh" ;;
        clash)        script_name="clash/clash.sh" ;;
        gpu-docker-processes) script_name="gpu-docker-processes/gpu_docker_processes.sh" ;;
        gpu-interconnect-benchmark) script_name="gpu-interconnect-benchmark/gpu_interconnect_benchmark.sh" ;;
        network-speed) script_name="network-speed/network_speed.sh" ;;
        container-mem) script_name="container-mem/container_mem.sh" ;;
        claude-sync)
            script_name="claude-sync-settings/sync.py"
            execution_mode="python"
            ;;
        help|-h|--help)
            _scripts_usage
            return 0
            ;;
        *)
            printf 'Unknown command: %s\n\n' "$command_name" >&2
            _scripts_usage >&2
            return 2
            ;;
    esac

    shift

    if [[ "$execution_mode" == "source" ]] && ! _scripts_is_sourced; then
        printf '%s\n' "The $command_name command must be run with 'source' so it can modify the current shell." >&2
        return 2
    fi

    if [[ "$execution_mode" == "python" ]]; then
        python_cmd="$(_scripts_find_python)" || {
            printf '%s\n' "The $command_name command requires Python 3 (python3 or python)." >&2
            return 1
        }
    fi

    temp_file="$(mktemp)" || return 1
    if ! _scripts_download "$script_name" "$temp_file"; then
        printf 'Failed to download %s\n' "$script_name" >&2
        rm -f "$temp_file"
        return 1
    fi

    if [[ "$execution_mode" == "source" ]]; then
        # shellcheck disable=SC1090
        source "$temp_file" "$@"
        exit_code=$?
    elif [[ "$execution_mode" == "python" ]]; then
        "$python_cmd" "$temp_file" "$@"
        exit_code=$?
    else
        bash "$temp_file" "$@"
        exit_code=$?
    fi

    if [[ "$command_name" == tmux && "$exit_code" -eq 0 ]] && _scripts_is_sourced; then
        _scripts_apply_tmux_install
    fi

    rm -f "$temp_file"
    return "$exit_code"
}

_scripts_run "$@"
_scripts_status=$?
unset -f _scripts_run _scripts_download _scripts_is_sourced _scripts_usage _scripts_apply_tmux_install \
    _scripts_find_python
return "$_scripts_status" 2>/dev/null || exit "$_scripts_status"
