#!/usr/bin/env bash

_set_proxy_usage() {
    cat <<'EOF'
Usage:
  source set_proxy.sh [proxy]

Arguments:
  proxy    Proxy URL or host:port (default: 127.0.0.1:7890)

Environment:
  proxy    Proxy URL or host:port; overridden by the command argument
EOF
}

if [[ $# -gt 1 ]]; then
    printf '%s\n\n' 'Too many arguments.' >&2
    _set_proxy_usage >&2
    unset -f _set_proxy_usage
    return 2 2>/dev/null || exit 2
fi

case "${1:-}" in
    help|-h|--help)
        _set_proxy_usage
        unset -f _set_proxy_usage
        return 0 2>/dev/null || exit 0
        ;;
esac

_set_proxy_value="${1:-${proxy:-127.0.0.1:7890}}"
if [[ "$_set_proxy_value" != *://* ]]; then
    _set_proxy_value="http://${_set_proxy_value}"
fi

export http_proxy="$_set_proxy_value"
export https_proxy="$_set_proxy_value"
export ftp_proxy="$_set_proxy_value"
export all_proxy="$_set_proxy_value"
export HTTP_PROXY="$_set_proxy_value"
export HTTPS_PROXY="$_set_proxy_value"
export FTP_PROXY="$_set_proxy_value"
export ALL_PROXY="$_set_proxy_value"

printf 'Proxy set to %s\n' "$_set_proxy_value"

unset _set_proxy_value
unset -f _set_proxy_usage
