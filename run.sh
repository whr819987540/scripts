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
  git           Install and configure Git
  miniconda [silent] [installer-path]
                Install Miniconda without prompts; reuse an existing installer
  nvm           Install the latest stable nvm and Node.js releases
  zsh           Install and configure Zsh, Oh My Zsh, and plugins
  new-user      Create and configure a user
  zabbix-agent  Install and configure Zabbix Agent
  clash [serve] Install and run Clash; automatically adjust occupied ports
                gpu-docker-processes
                Show Docker containers for processes using NVIDIA GPUs
  network-speed [interface] [interval]
                Monitor interval and cumulative average network speed
                (defaults: eth0, 1 second)
  container-mem [-n N]
                Analyze memory usage of the current container (top N, default: 15)
  help          Show this help

Environment:
  proxy         Proxy URL or host:port used by set-proxy
  config_url    Required by clash; URL of the Clash configuration file
  clash_download_url  
                Clash archive URL; defaults to this repository
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

_scripts_run() {
    local command_name="${1:-help}"
    local script_name=""
    local execution_mode="bash"
    local temp_file=""
    local exit_code=0

    case "$command_name" in
        set-proxy)
            script_name="set_proxy.sh"
            execution_mode="source"
            ;;
        unset-proxy)
            script_name="unset_proxy.sh"
            execution_mode="source"
            ;;
        docker)       script_name="docker_install.sh" ;;
        git)          script_name="git_install_config.sh" ;;
        miniconda)    script_name="miniconda_install.sh" ;;
        nvm)          script_name="nvm_install.sh" ;;
        zsh)          script_name="zsh_install.sh" ;;
        new-user)     script_name="new_user.sh" ;;
        zabbix-agent) script_name="zabbix_agent.sh" ;;
        clash)        script_name="clash.sh" ;;
        gpu-docker-processes) script_name="gpu_docker_processes.sh" ;;
        network-speed) script_name="network_speed.sh" ;;
        container-mem) script_name="container_mem.sh" ;;
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
    else
        bash "$temp_file" "$@"
        exit_code=$?
    fi

    rm -f "$temp_file"
    return "$exit_code"
}

_scripts_run "$@"
_scripts_status=$?
unset -f _scripts_run _scripts_download _scripts_is_sourced _scripts_usage
return "$_scripts_status" 2>/dev/null || exit "$_scripts_status"
