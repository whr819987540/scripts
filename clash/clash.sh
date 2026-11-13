#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  config_url=<url> [clash_download_url=<url>] clash.sh [bg|serve]

Modes:
  (default)  Run Clash in the foreground
  bg         Run Clash in the background, detached from the terminal, so it
             keeps running after the terminal exits. Output goes to
             ~/clash/clash.log and the PID to ~/clash/clash.pid; running bg
             again first stops the background Clash it started before.
             Stop it with: kill "$(cat ~/clash/clash.pid)"
  serve      Install and start the Clash systemd service

Ports:
  Listening ports in the config that are in use are incremented to the next
  free port. The ports finally used are printed before Clash starts and stay
  in ~/clash/glados.yaml. To pin a port instead, set the variable for its
  config key; the script then stops with an error if that port is in use, and
  adds the key to the config if it is missing:
    clash_port             port (HTTP proxy)
    clash_socks_port       socks-port (SOCKS5 proxy)
    clash_mixed_port       mixed-port (HTTP and SOCKS5 proxy)
    clash_redir_port       redir-port
    clash_tproxy_port      tproxy-port
    clash_controller_port  port of external-controller (RESTful API)

Environment:
  config_url            Required URL of the Clash configuration file
  clash_download_url    Clash archive URL; defaults to this repository. 
                        Official: https://glados.rocks/tools/clash-linux.zip
                        Github: https://raw.githubusercontent.com/whr819987540/scripts/main/clash/clash-linux.zip
                        Gitee: https://gitee.com/hit_whr/scripts/raw/main/clash/clash-linux.zip
EOF
}

mode="${1:-cli}"

case "$mode" in
    cli) ;;
    bg) ;;
    serve) ;;
    help|-h|--help)
        usage
        exit 0
        ;;
    *)
        printf 'Unknown argument: %s\n\n' "$mode" >&2
        usage >&2
        exit 2
        ;;
esac

if [[ -z "${config_url:-}" ]]; then
    printf '%s\n' 'The config_url environment variable is required.' >&2
    usage >&2
    exit 2
fi

for command_name in curl ss unzip; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [[ "$mode" == "bg" ]] && ! command -v setsid >/dev/null 2>&1; then
    printf '%s\n' 'setsid is required for bg mode.' >&2
    exit 1
fi

# Ports requested through clash_*port variables, keyed by the config key they set.
port_keys=(port socks-port mixed-port redir-port tproxy-port external-controller)
declare -A requested_ports=()

port_variable_name() {
    if [[ "$1" == external-controller ]]; then
        printf '%s\n' clash_controller_port
    else
        printf 'clash_%s\n' "${1//-/_}"
    fi
}

for port_key in "${port_keys[@]}"; do
    port_variable="$(port_variable_name "$port_key")"
    port_value="${!port_variable:-}"
    [[ -n "$port_value" ]] || continue
    if [[ ! "$port_value" =~ ^[0-9]{1,5}$ ]] \
        || ((10#$port_value < 1 || 10#$port_value > 65535)); then
        printf '%s must be a port number from 1 to 65535: %s\n' \
            "$port_variable" "$port_value" >&2
        exit 2
    fi
    requested_ports[$port_key]=$((10#$port_value))
done

install_dir="${HOME}/clash"
config_path="${install_dir}/glados.yaml"
log_path="${install_dir}/clash.log"
pid_path="${install_dir}/clash.pid"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
archive_path="${script_dir}/clash-linux.zip"
clash_download_url="${clash_download_url:-https://raw.githubusercontent.com/whr819987540/scripts/main/clash/clash-linux.zip}"
temporary_archive=""
temporary_config=""

cleanup() {
    if [[ -n "$temporary_archive" ]]; then
        rm -f "$temporary_archive"
    fi
    if [[ -n "$temporary_config" ]]; then
        rm -f "$temporary_config"
    fi
}
trap cleanup EXIT

# Succeeds when the PID is a running Clash process that uses this script's config.
# Checking the command line guards against a stale PID file whose PID was reused.
is_background_clash() {
    local pid="$1"
    local cmdline=""

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    cmdline="$(tr '\0' ' ' 2>/dev/null <"/proc/${pid}/cmdline")" || return 1
    [[ "$cmdline" == *" -f ${config_path} "* ]]
}

# Stops the Clash started by an earlier bg run so its ports can be reused.
stop_background_clash() {
    local pid=""
    local attempt=0

    [[ -f "$pid_path" ]] || return 0
    pid="$(<"$pid_path")"
    if is_background_clash "$pid"; then
        printf 'Stopping the background Clash started earlier (PID %s).\n' "$pid" >&2
        kill "$pid" 2>/dev/null || true
        while is_background_clash "$pid" && ((attempt < 50)); do
            sleep 0.1
            ((attempt += 1))
        done
        if is_background_clash "$pid"; then
            kill -KILL "$pid" 2>/dev/null || true
            sleep 0.5
        fi
    fi
    rm -f "$pid_path"
}

declare -A reserved_ports=()
available_port=""
declare -A seen_keys=()       # port keys present in the downloaded config
declare -A rewritten_keys=()  # requested keys whose port was written into the config
declare -A final_ports=()     # config key -> address it listens on after adjustment
listening_ports=()            # summary lines in config order

port_is_in_use() {
    local port="$1"
    local protocols="$2"

    if [[ "$protocols" == *tcp* ]]; then
        if [[ -n "${reserved_ports[tcp:$port]:-}" ]] \
            || [[ -n "$(ss -H -ltn "sport = :$port")" ]]; then
            return 0
        fi
    fi
    if [[ "$protocols" == *udp* ]]; then
        if [[ -n "${reserved_ports[udp:$port]:-}" ]] \
            || [[ -n "$(ss -H -lun "sport = :$port")" ]]; then
            return 0
        fi
    fi
    return 1
}

reserve_available_port() {
    local requested_port="$1"
    local protocols="$2"
    local port="$requested_port"

    while port_is_in_use "$port" "$protocols"; do
        ((port += 1))
        if ((port > 65535)); then
            printf 'No available %s port found at or above %s.\n' \
                "$protocols" "$requested_port" >&2
            return 1
        fi
    done

    reserve_port "$port" "$protocols"
    available_port="$port"
    return 0
}

reserve_port() {
    local port="$1"
    local protocols="$2"

    if [[ "$protocols" == *tcp* ]]; then
        reserved_ports[tcp:$port]=1
    fi
    if [[ "$protocols" == *udp* ]]; then
        reserved_ports[udp:$port]=1
    fi
}

# Reserves the requested ports before any configured port is adjusted, so the
# adjusted ports avoid them. A requested port that is taken is an error rather
# than being moved: the user asked for exactly that port.
reserve_requested_ports() {
    local key=""
    local port=""
    local protocols=""

    for key in "${port_keys[@]}"; do
        port="${requested_ports[$key]:-}"
        [[ -n "$port" ]] || continue
        protocols=tcp
        [[ "$key" == tproxy-port ]] && protocols=tcp,udp
        if [[ -n "${reserved_ports[tcp:$port]:-}" ]]; then
            printf 'Port %s is requested by more than one clash_*port variable.\n' \
                "$port" >&2
            exit 2
        fi
        if port_is_in_use "$port" "$protocols"; then
            printf 'Port %s requested by %s is already in use:\n' \
                "$port" "$(port_variable_name "$key")" >&2
            ss -H -ltunp "sport = :$port" >&2 || true
            exit 1
        fi
        reserve_port "$port" "$protocols"
    done
}

# Sets available_port for a config key: the requested port if there is one,
# otherwise the first free port at or above the configured one.
choose_port() {
    local key="$1"
    local port="$2"
    local protocols="$3"
    local label="$4"

    if [[ -n "${requested_ports[$key]:-}" ]]; then
        available_port="${requested_ports[$key]}"
        rewritten_keys[$key]=1
        return 0
    fi
    reserve_available_port "$port" "$protocols"
    if [[ "$available_port" != "$port" ]]; then
        printf '%s %s is in use; using %s.\n' "$label" "$port" "$available_port" >&2
    fi
}

record_port() {
    final_ports[$1]="$2"
    listening_ports+=("$(printf '  %-20s %s' "$1" "$2")")
}

adjust_config_ports() {
    local line=""
    local key=""
    local whitespace=""
    local suffix=""
    local address=""
    local quote=""
    local host=""
    local port=""
    local protocols=""
    local in_dns=false

    reserve_requested_ports
    temporary_config="$(mktemp "${config_path}.XXXXXX")"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^dns:[[:space:]]*(#.*)?$ ]]; then
            in_dns=true
        elif [[ "$line" =~ ^[^[:space:]#] ]]; then
            in_dns=false
        fi

        if [[ "$line" =~ ^(port|socks-port|mixed-port|redir-port|tproxy-port|external-controller):([[:space:]]|$) ]]; then
            seen_keys[${BASH_REMATCH[1]}]=1
        fi

        if [[ "$line" =~ ^(port|socks-port|mixed-port|redir-port|tproxy-port):([[:space:]]*)([0-9]+)([[:space:]]*(#.*)?)$ ]]; then
            key="${BASH_REMATCH[1]}"
            whitespace="${BASH_REMATCH[2]}"
            port="${BASH_REMATCH[3]}"
            suffix="${BASH_REMATCH[4]}"
            protocols=tcp
            [[ "$key" == tproxy-port ]] && protocols=tcp,udp
            choose_port "$key" "$port" "$protocols" "$key"
            line="${key}:${whitespace}${available_port}${suffix}"
            record_port "$key" "$available_port"
        elif [[ "$line" =~ ^(external-controller):([[:space:]]*)([^#[:space:]]+)([[:space:]]*(#.*)?)$ ]]; then
            key="${BASH_REMATCH[1]}"
            whitespace="${BASH_REMATCH[2]}"
            address="${BASH_REMATCH[3]}"
            suffix="${BASH_REMATCH[4]}"
            quote=""
            if [[ "$address" == \"*\" || "$address" == \'*\' ]]; then
                quote="${address:0:1}"
                address="${address:1:${#address}-2}"
            fi
            host="${address%:*}"
            port="${address##*:}"
            if [[ "$address" == *:* && "$port" =~ ^[0-9]+$ ]]; then
                choose_port "$key" "$port" tcp "$key port"
                line="${key}:${whitespace}${quote}${host}:${available_port}${quote}${suffix}"
                record_port "$key" "${host}:${available_port}"
            fi
        elif $in_dns && [[ "$line" =~ ^([[:space:]]+)(listen):([[:space:]]*)([^#[:space:]]+)([[:space:]]*(#.*)?)$ ]]; then
            whitespace="${BASH_REMATCH[1]}"
            key="${BASH_REMATCH[2]}"
            address="${BASH_REMATCH[4]}"
            suffix="${BASH_REMATCH[5]}"
            quote=""
            if [[ "$address" == \"*\" || "$address" == \'*\' ]]; then
                quote="${address:0:1}"
                address="${address:1:${#address}-2}"
            fi
            host="${address%:*}"
            port="${address##*:}"
            if [[ -n "$host" && "$port" =~ ^[0-9]+$ ]]; then
                choose_port dns.listen "$port" tcp,udp "DNS listen port"
                line="${whitespace}${key}: ${quote}${host}:${available_port}${quote}${suffix}"
                record_port dns.listen "${host}:${available_port}"
            fi
        fi

        printf '%s\n' "$line" >>"$temporary_config"
    done <"$config_path"

    # Add requested keys the config lacks. A key that is present but was not
    # rewritten has a value this parser does not understand.
    for key in "${port_keys[@]}"; do
        port="${requested_ports[$key]:-}"
        [[ -n "$port" ]] || continue
        if [[ -z "${seen_keys[$key]:-}" ]]; then
            address="$port"
            [[ "$key" == external-controller ]] && address="127.0.0.1:${port}"
            printf '%s: %s\n' "$key" "$address" >>"$temporary_config"
            record_port "$key" "$address"
        elif [[ -z "${rewritten_keys[$key]:-}" ]]; then
            printf 'Cannot apply %s: the %s value in the config is not a plain port.\n' \
                "$(port_variable_name "$key")" "$key" >&2
            exit 1
        fi
    done

    chmod 600 "$temporary_config"
    mv -f "$temporary_config" "$config_path"
    temporary_config=""
}

print_listening_ports() {
    local http_port="${final_ports[mixed-port]:-${final_ports[port]:-}}"
    local run_url="${SCRIPTS_BASE_URL:-https://gitee.com/hit_whr/scripts/raw/main}/run.sh"

    ((${#listening_ports[@]} > 0)) || return 0
    printf 'Clash listening ports (kept in %s):\n' "$config_path"
    printf '%s\n' "${listening_ports[@]}"
    if [[ -n "$http_port" ]]; then
        printf 'Use the proxy in a shell:\n'
        printf '  source <(curl -fsSL %s) set-proxy 127.0.0.1:%s\n' "$run_url" "$http_port"
    fi
}

mkdir -p "$install_dir"
if [[ ! -f "$archive_path" ]]; then
    temporary_archive="$(mktemp "${TMPDIR:-/tmp}/clash-linux.XXXXXX.zip")"
    archive_path="$temporary_archive"
    curl -fsSL "$clash_download_url" -o "$archive_path"
fi
unzip -oq "$archive_path" -d "$install_dir"
curl -fsSL "$config_url" -o "$config_path"
chmod 600 "$config_path"
if [[ "$mode" == "bg" ]]; then
    stop_background_clash
fi
adjust_config_ports

binary_path="$(
    find "$install_dir" -maxdepth 2 -type f -name 'clash-linux-amd64-*' -print \
        | sort -V \
        | tail -n 1
)"

if [[ -z "$binary_path" ]]; then
    printf 'Clash executable not found under %s\n' "$install_dir" >&2
    exit 1
fi

chmod a+x "$binary_path"

if ! "$binary_path" -t -f "$config_path" -d "$install_dir"; then
    printf '%s\n' 'Clash configuration validation failed.' >&2
    exit 1
fi

print_listening_ports

if [[ "$mode" == "cli" ]]; then
    exec "$binary_path" -f "$config_path" -d "$install_dir"
fi

if [[ "$mode" == "bg" ]]; then
    # setsid gives Clash its own session without a controlling terminal, so closing
    # the terminal or the SSH connection does not stop it. This script runs without
    # job control, so the child is not a process group leader: setsid execs Clash
    # in place instead of forking, and $! is the Clash PID.
    setsid "$binary_path" -f "$config_path" -d "$install_dir" \
        </dev/null >"$log_path" 2>&1 &
    clash_pid=$!
    printf '%s\n' "$clash_pid" >"$pid_path"

    sleep 1
    if ! is_background_clash "$clash_pid"; then
        rm -f "$pid_path"
        printf 'Clash exited right after starting. Last lines of %s:\n' "$log_path" >&2
        tail -n 20 "$log_path" >&2
        exit 1
    fi

    printf 'Clash is running in the background (PID %s).\n' "$clash_pid"
    printf 'Log:  %s\n' "$log_path"
    printf 'Stop: kill "$(cat %s)"\n' "$pid_path"
    exit 0
fi

if ! command -v systemctl >/dev/null 2>&1; then
    printf '%s\n' 'systemctl is required for serve mode.' >&2
    exit 1
fi

service_user="$(id -un)"
service_path='/etc/systemd/system/clash.service'

sudo tee "$service_path" >/dev/null <<EOF
[Unit]
Description=Clash proxy service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$service_user
WorkingDirectory=$install_dir
ExecStart=$binary_path -f $config_path -d $install_dir
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now clash.service
sudo systemctl status --no-pager clash.service
