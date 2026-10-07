#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  config_url=<url> [clash_download_url=<url>] clash.sh [serve]

Modes:
  (default)  Run Clash in the foreground
  serve      Install and start the Clash systemd service

Clash listening ports in use are incremented to the next available port.

Environment:
  config_url            Required URL of the Clash configuration file
  clash_download_url    Clash archive URL; defaults to this repository. 
                        Official: https://glados.rocks/tools/clash-linux.zip
                        Github: https://raw.githubusercontent.com/whr819987540/scripts/main/clash-linux.zip
                        Gitee: https://gitee.com/hit_whr/scripts/raw/main/clash-linux.zip
EOF
}

mode="${1:-cli}"

case "$mode" in
    cli) ;;
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

install_dir="${HOME}/clash"
config_path="${install_dir}/glados.yaml"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
archive_path="${script_dir}/clash-linux.zip"
clash_download_url="${clash_download_url:-https://raw.githubusercontent.com/whr819987540/scripts/main/clash-linux.zip}"
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

declare -A reserved_ports=()
available_port=""

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

    [[ "$protocols" == *tcp* ]] && reserved_ports[tcp:$port]=1
    [[ "$protocols" == *udp* ]] && reserved_ports[udp:$port]=1
    available_port="$port"
    return 0
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

    temporary_config="$(mktemp "${config_path}.XXXXXX")"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^dns:[[:space:]]*(#.*)?$ ]]; then
            in_dns=true
        elif [[ "$line" =~ ^[^[:space:]#] ]]; then
            in_dns=false
        fi

        if [[ "$line" =~ ^(port|socks-port|mixed-port|redir-port|tproxy-port):([[:space:]]*)([0-9]+)([[:space:]]*(#.*)?)$ ]]; then
            key="${BASH_REMATCH[1]}"
            whitespace="${BASH_REMATCH[2]}"
            port="${BASH_REMATCH[3]}"
            suffix="${BASH_REMATCH[4]}"
            protocols=tcp
            [[ "$key" == tproxy-port ]] && protocols=tcp,udp
            reserve_available_port "$port" "$protocols"
            if [[ "$available_port" != "$port" ]]; then
                printf '%s %s is in use; using %s.\n' \
                    "$key" "$port" "$available_port" >&2
            fi
            line="${key}:${whitespace}${available_port}${suffix}"
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
            if [[ -n "$host" && "$port" =~ ^[0-9]+$ ]]; then
                reserve_available_port "$port" tcp
                if [[ "$available_port" != "$port" ]]; then
                    printf '%s port %s is in use; using %s.\n' \
                        "$key" "$port" "$available_port" >&2
                fi
                line="${key}:${whitespace}${quote}${host}:${available_port}${quote}${suffix}"
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
                reserve_available_port "$port" tcp,udp
                if [[ "$available_port" != "$port" ]]; then
                    printf 'DNS listen port %s is in use; using %s.\n' \
                        "$port" "$available_port" >&2
                fi
                line="${whitespace}${key}: ${quote}${host}:${available_port}${quote}${suffix}"
            fi
        fi

        printf '%s\n' "$line" >>"$temporary_config"
    done <"$config_path"

    chmod 600 "$temporary_config"
    mv -f "$temporary_config" "$config_path"
    temporary_config=""
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

if [[ "$mode" == "cli" ]]; then
    exec "$binary_path" -f "$config_path" -d "$install_dir"
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
