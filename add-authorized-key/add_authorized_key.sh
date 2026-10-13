#!/usr/bin/env bash

set -euo pipefail

_add_authorized_key_usage() {
    cat <<'EOF'
Usage:
  bash add_authorized_key.sh [public-key]

Arguments:
  public-key    Complete SSH public key enclosed in quotes
                (default: the public key built into this script)
EOF
}

readonly default_public_key='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCz5k2gaUzhBZwKCTKfKzYVrzLLoKu2+7Bdcm5uLDZeOUfw2fD3zBsf/M8iHkax1u3Umr9qZgiskgU3vpSEg1Wh1zdiYjTZysEAVNk+9007m6zoEtv/eXnGXukIJLae3CBTNwpjy42ceTYorhVq2PkLkx2R4qfLWiKRSMrFd8utbVDzLa6Uyh75B0UjrSA9MeN3QCei+YuG+UnP2Vuf1g4caoDZjvLKgCE97HxrPxQAxLxvJxmUA+dvknyfQZMj4EUi3bc1UlD8zq78waGVssgt2+BJ6TKFaPGeqZG/9MBMMr4bAJhGyeQYCun34fFc+6kjyhW4+a03NpGKthLaiRV0rbZ3cm/+vYrFYV/4eUjztyHFp9j1kmRRTAOC/GfCsRUmWWA8bHaNITH3I8lfZcxRxG4vOzwnZubtA/epsCzB1rIuxynfRKkSGLQRd6KtmJeyhkxxuzT/eMSjOQpghRex7VMeSJzBgzOVz79ZLQynTX2fsR8IKCLzhTv430vNWN8= 819987540@qq.com'
readonly ssh_dir="${HOME:?HOME is not set}/.ssh"
readonly authorized_keys_file="${ssh_dir}/authorized_keys"

if [[ $# -gt 1 ]]; then
    printf '%s\n\n' 'Too many arguments; enclose the complete public key in quotes.' >&2
    _add_authorized_key_usage >&2
    exit 2
fi

case "${1:-}" in
    help|-h|--help)
        _add_authorized_key_usage
        exit 0
        ;;
esac

readonly public_key="${1:-$default_public_key}"

if [[ "$public_key" == *$'\n'* || "$public_key" == *$'\r'* ]]; then
    printf '%s\n' 'Invalid SSH public key: only one line is allowed.' >&2
    exit 2
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
    printf '%s\n' 'ssh-keygen is required to validate the public key.' >&2
    exit 1
fi

if ! ssh-keygen -l -f <(printf '%s\n' "$public_key") >/dev/null 2>&1; then
    printf '%s\n' 'Invalid SSH public key.' >&2
    exit 2
fi

mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
touch "$authorized_keys_file"
chmod 600 "$authorized_keys_file"

if grep -Fqx -- "$public_key" "$authorized_keys_file"; then
    printf 'SSH public key is already trusted in %s\n' "$authorized_keys_file"
    exit 0
fi

# Prevent an existing final line without a newline from being joined to the key.
if [[ -s "$authorized_keys_file" ]] && [[ -n "$(tail -c 1 "$authorized_keys_file")" ]]; then
    printf '\n' >> "$authorized_keys_file"
fi

printf '%s\n' "$public_key" >> "$authorized_keys_file"
printf 'SSH public key added to %s\n' "$authorized_keys_file"
