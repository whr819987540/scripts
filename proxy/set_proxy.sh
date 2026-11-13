#!/usr/bin/env bash

_set_proxy_usage() {
    cat <<'EOF'
Usage:
  source set_proxy.sh [proxy]

Arguments:
  proxy    Proxy URL or host:port (default: 127.0.0.1:7890)

Environment:
  proxy    Proxy URL or host:port; overridden by the command argument
  no_proxy, NO_PROXY
           Hosts that bypass the proxy. Existing entries are kept and merged
           into the defaults: localhost, 127.0.0.1, ::1 and the private IPv4
           ranges 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16. CIDR ranges work
           with curl 7.86+, Python requests/pip and Go; older curl and wget
           ignore them.
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

if [[ -n "${1:-}" ]]; then
    _set_proxy_value="$1"
    _set_proxy_source='command argument'
elif [[ -n "${proxy:-}" ]]; then
    _set_proxy_value="$proxy"
    _set_proxy_source='proxy variable'
else
    _set_proxy_value='127.0.0.1:7890'
    _set_proxy_source='default'
fi
printf 'Proxy address: %s (%s)\n' "$_set_proxy_value" "$_set_proxy_source"

if [[ "$_set_proxy_value" != *://* ]]; then
    _set_proxy_value="http://${_set_proxy_value}"
    printf 'No scheme given; using %s\n' "$_set_proxy_value"
fi

# Merge the entries already in no_proxy/NO_PROXY into the default bypass list,
# skipping duplicates, so running set-proxy again or after a system-wide
# no_proxy does not drop or repeat anything.
_set_proxy_bypass='localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16'
_set_proxy_kept=''
_set_proxy_rest="${no_proxy:-},${NO_PROXY:-}"
while [[ -n "$_set_proxy_rest" ]]; do
    _set_proxy_entry="${_set_proxy_rest%%,*}"
    if [[ "$_set_proxy_rest" == *,* ]]; then
        _set_proxy_rest="${_set_proxy_rest#*,}"
    else
        _set_proxy_rest=''
    fi
    _set_proxy_entry="${_set_proxy_entry// /}"
    if [[ -n "$_set_proxy_entry" && ",${_set_proxy_bypass}," != *",${_set_proxy_entry},"* ]]; then
        _set_proxy_bypass="${_set_proxy_bypass},${_set_proxy_entry}"
        _set_proxy_kept="${_set_proxy_kept:+${_set_proxy_kept},}${_set_proxy_entry}"
    fi
done
if [[ -n "$_set_proxy_kept" ]]; then
    printf 'Kept existing no_proxy entries: %s\n' "$_set_proxy_kept"
fi

printf '%s\n' 'Exported in the current shell:'
for _set_proxy_name in http_proxy https_proxy ftp_proxy all_proxy \
    HTTP_PROXY HTTPS_PROXY FTP_PROXY ALL_PROXY; do
    export "${_set_proxy_name}=${_set_proxy_value}"
    printf 'export %s=%s\n' "$_set_proxy_name" "$_set_proxy_value"
done
for _set_proxy_name in no_proxy NO_PROXY; do
    export "${_set_proxy_name}=${_set_proxy_bypass}"
    printf 'export %s=%s\n' "$_set_proxy_name" "$_set_proxy_bypass"
done
printf '%s\n' \
    'Programs started from this shell that read these variables (curl, wget,' \
    'pip, git, ...) now use the proxy, except for the hosts in no_proxy.' \
    'Other terminals are not affected.'
printf 'Undo: source <(curl -fsSL %s/run.sh) unset-proxy\n' \
    "${SCRIPTS_BASE_URL:-https://gitee.com/hit_whr/scripts/raw/main}"

unset _set_proxy_value _set_proxy_source _set_proxy_name _set_proxy_bypass \
    _set_proxy_kept _set_proxy_rest _set_proxy_entry
unset -f _set_proxy_usage
