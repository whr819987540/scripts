#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  config_url=<url> clash.sh [serve]

Modes:
  (default)  Run Clash in the foreground
  serve      Install and start the Clash systemd service

Environment:
  config_url  Required URL of the Clash configuration file
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

for command_name in curl unzip; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

install_dir="${HOME}/clash"
config_path="${install_dir}/glados.yaml"
archive_path="$(mktemp "${TMPDIR:-/tmp}/clash-linux.XXXXXX.zip")"

cleanup() {
    rm -f "$archive_path"
}
trap cleanup EXIT

mkdir -p "$install_dir"
curl -fsSL 'https://glados.rocks/tools/clash-linux.zip' -o "$archive_path"
unzip -oq "$archive_path" -d "$install_dir"
curl -fsSL "$config_url" -o "$config_path"
chmod 600 "$config_path"

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
