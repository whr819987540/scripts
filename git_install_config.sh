#!/usr/bin/env bash

set -euo pipefail

readonly GIT_USER_EMAIL="819987540@qq.com"
readonly GIT_USER_NAME="whr81998754"
readonly SSH_CONFIG_BEGIN="# BEGIN scripts: github proxy"
readonly SSH_CONFIG_END="# END scripts: github proxy"

usage() {
    cat <<'EOF'
Usage:
  git_install_config.sh

Install Git when needed, configure the global Git identity and proxy, reuse or
create an SSH public key, and configure GitHub SSH access through the proxy.

Environment:
  http_proxy    HTTP proxy URL (default: http://127.0.0.1:7890)
  https_proxy   HTTPS Git proxy URL (default: value of http_proxy)
EOF
}

run_as_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        printf 'Cannot install missing packages without root privileges or sudo access.\n' >&2
        exit 1
    fi
}

if (( $# > 1 )); then
    printf '%s\n\n' 'Too many arguments.' >&2
    usage >&2
    exit 2
fi

case "${1:-}" in
    "") ;;
    help|-h|--help)
        usage
        exit 0
        ;;
    *)
        printf 'Unknown argument: %s\n\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac

proxy_url="${http_proxy:-http://127.0.0.1:7890}"
https_proxy_url="${https_proxy:-$proxy_url}"
if [[ "$proxy_url" != *://* ]]; then
    proxy_url="http://${proxy_url}"
fi
if [[ "$https_proxy_url" != *://* ]]; then
    https_proxy_url="http://${https_proxy_url}"
fi

proxy_address="${proxy_url#*://}"
proxy_address="${proxy_address%%/*}"
if [[ ! "$proxy_address" =~ ^[^[:space:]/:@]+:[0-9]+$ ]]; then
    printf 'Invalid HTTP proxy address for SSH: %s\n' "$proxy_url" >&2
    printf '%s\n' 'Expected a URL such as http://127.0.0.1:7890.' >&2
    exit 2
fi

packages=()
if command -v git >/dev/null 2>&1; then
    printf 'Git is already installed: %s\n' "$(git --version)"
else
    packages+=(git)
fi

if ! command -v nc >/dev/null 2>&1; then
    packages+=(netcat-openbsd)
fi

if (( ${#packages[@]} > 0 )); then
    printf 'Installing required packages: %s\n' "${packages[*]}"
    run_as_root apt-get update
    run_as_root apt-get install -y "${packages[@]}"
fi

git config --global user.email "$GIT_USER_EMAIL"
git config --global user.name "$GIT_USER_NAME"
git config --global http.proxy "$proxy_url"
git config --global https.proxy "$https_proxy_url"
git config --global core.editor /usr/bin/vim

ssh_dir="$HOME/.ssh"
ssh_config="$ssh_dir/config"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"

shopt -s nullglob
public_keys=("$ssh_dir"/*.pub)
shopt -u nullglob

if (( ${#public_keys[@]} == 0 )); then
    printf '%s\n' 'No SSH public key found. Generating an Ed25519 key...'
    ssh-keygen -t ed25519 -C "$GIT_USER_EMAIL"
    shopt -s nullglob
    public_keys=("$ssh_dir"/*.pub)
    shopt -u nullglob
else
    printf 'Existing SSH public key found; skipping ssh-keygen: %s\n' "${public_keys[0]}"
fi

filtered_config="$(mktemp "${ssh_config}.filtered.XXXXXX")"
new_config="$(mktemp "${ssh_config}.new.XXXXXX")"
cleanup() {
    rm -f "$filtered_config" "$new_config"
}
trap cleanup EXIT

if [[ -f "$ssh_config" ]]; then
    awk -v begin="$SSH_CONFIG_BEGIN" -v end="$SSH_CONFIG_END" '
        $0 == begin { managed = 1; next }
        $0 == end { managed = 0; next }
        !managed {
            if (!started && $0 ~ /^[[:space:]]*$/) {
                next
            }
            started = 1
            print
        }
    ' "$ssh_config" > "$filtered_config"
fi

{
    printf '%s\n' "$SSH_CONFIG_BEGIN"
    cat <<EOF
Host github.com
    HostName ssh.github.com
    Port 443
    User git
    ProxyCommand nc -X connect -x ${proxy_address} %h %p
EOF
    printf '%s\n' "$SSH_CONFIG_END"
    if [[ -s "$filtered_config" ]]; then
        printf '\n'
        command cat "$filtered_config"
    fi
} > "$new_config"

chmod 600 "$new_config"
mv "$new_config" "$ssh_config"
printf 'Configured GitHub SSH proxy in %s using %s.\n' "$ssh_config" "$proxy_address"

if (( ${#public_keys[@]} > 0 )); then
    printf '%s\n' 'Add the following public key to GitHub:'
    for public_key in "${public_keys[@]}"; do
        printf '\n%s:\n' "$public_key"
        command cat "$public_key"
    done
fi

printf '\n%s\n' 'After adding the key, test the connection with: ssh -T git@github.com'
