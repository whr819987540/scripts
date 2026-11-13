#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  config_url=<url> [clash_download_url=<url>] clash.sh [bg|serve]
  clash.sh stop

Modes:
  (default)  Run Clash in the foreground
  bg         Run Clash in the background, detached from the terminal, so it
             keeps running after the terminal exits. Output goes to
             ~/clash/clash.log and the PID to ~/clash/clash.pid; running bg
             again first stops the background Clash it started before.
  serve      Install and start the Clash systemd service
  stop       Stop the Clash started by this script in any mode: the systemd
             service (with sudo; it stays enabled at boot), the bg instance
             and a foreground instance in another terminal. Needs no
             config_url.

Cores:
  The mihomo core is used first; if it cannot be installed or rejects the
  configuration, the original Clash v1.10.0 core is tried. Both cores and the
  GeoIP/GeoSite data mihomo needs are bundled in this repository, so nothing
  is downloaded from GitHub. The configuration is downloaded with a
  User-Agent that subscription services recognize, so they return a format
  the core supports: clash.meta for mihomo, ClashforWindows/0.20.39 for Clash.
  The running Clash and ~/clash/glados.yaml are only replaced after the new
  configuration passed validation.

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
  clash_core            auto (default; mihomo, then Clash), mihomo or clash
  clash_user_agent      User-Agent for downloading the configuration,
                        instead of the one chosen for the core
  clash_download_url    URL of clash-linux.zip for the Clash core, e.g. the
                        official https://glados.rocks/tools/clash-linux.zip
  SCRIPTS_BASE_URL      Mirror of this repository tried first for the
                        bundled files; then Gitee, then GitHub
EOF
}

mode="${1:-cli}"

case "$mode" in
    cli) ;;
    bg) ;;
    serve) ;;
    stop) ;;
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

install_dir="${HOME}/clash"
config_path="${install_dir}/glados.yaml"
log_path="${install_dir}/clash.log"
pid_path="${install_dir}/clash.pid"
service_name='clash.service'

# Succeeds when the PID is a Clash process started by this script. Every mode
# runs "<executable> -f <config_path> -d <install_dir>", so the command line
# identifies them and also guards against a stale PID file whose PID was reused.
is_script_clash() {
    local pid="$1"
    local cmdline=""

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    cmdline="$(tr '\0' ' ' 2>/dev/null <"/proc/${pid}/cmdline")" || return 1
    [[ "$cmdline" == *" -f ${config_path} -d ${install_dir} " ]]
}

# Succeeds until process $1 has finished exiting. Its command line turns empty
# early in the exit, before its sockets are closed. In a multithreaded process
# such as mihomo the main thread can already be a zombie (state Z) while other
# threads are still exiting and keep the shared file table, so wait until no
# thread is left in any other state.
process_alive() {
    local task_stat=""
    local stat=""

    for task_stat in "/proc/$1/task/"*/stat; do
        stat="$(cat "$task_stat" 2>/dev/null)" || continue
        stat="${stat##*) }"
        if [[ -n "$stat" && "${stat:0:1}" != Z ]]; then
            return 0
        fi
    done
    return 1
}

# Sends SIGTERM, waits up to 5 seconds for the process to exit, then SIGKILL.
# SIGKILL only goes to a process that is still this Clash, in case the PID was
# reused meanwhile.
stop_clash_pid() {
    local pid="$1"
    local attempt=0

    kill "$pid" 2>/dev/null || true
    while process_alive "$pid" && ((attempt < 50)); do
        sleep 0.1
        ((attempt += 1))
    done
    if is_script_clash "$pid"; then
        kill -KILL "$pid" 2>/dev/null || true
        attempt=0
        while process_alive "$pid" && ((attempt < 20)); do
            sleep 0.1
            ((attempt += 1))
        done
    fi
}

# Stops the Clash started by an earlier bg run so its ports can be reused.
stop_background_clash() {
    local pid=""

    [[ -f "$pid_path" ]] || return 0
    pid="$(<"$pid_path")"
    if is_script_clash "$pid"; then
        printf 'Stopping the background Clash started earlier (PID %s).\n' "$pid" >&2
        stop_clash_pid "$pid"
    fi
    rm -f "$pid_path"
}

# Succeeds when clash.service runs the command line that serve mode writes.
service_is_ours() {
    local exec_start=""

    exec_start="$(systemctl show -p ExecStart "$service_name" 2>/dev/null)" || return 1
    [[ "$exec_start" == *" -f ${config_path} -d ${install_dir} "* ]]
}

# Stops every Clash this script started. The systemd service goes first and
# through systemctl, because systemd would restart a killed service process.
stop_all_clash() {
    local cmdline_path=""
    local pid=""
    local stopped=false

    if command -v systemctl >/dev/null 2>&1 \
        && systemctl is-active --quiet "$service_name" 2>/dev/null; then
        if service_is_ours; then
            printf 'Stopping %s.\n' "$service_name"
            sudo systemctl stop "$service_name"
            stopped=true
            if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
                printf 'It still starts at boot; to prevent that: sudo systemctl disable %s\n' \
                    "$service_name"
            fi
        else
            printf '%s is running but does not run %s; leaving it alone.\n' \
                "$service_name" "$config_path"
        fi
    fi

    for cmdline_path in /proc/[0-9]*/cmdline; do
        pid="${cmdline_path#/proc/}"
        pid="${pid%/cmdline}"
        if is_script_clash "$pid"; then
            printf 'Stopping Clash (PID %s).\n' "$pid"
            stop_clash_pid "$pid"
            stopped=true
        fi
    done
    rm -f "$pid_path"

    if ! $stopped; then
        printf '%s\n' 'No running Clash started by this script was found.'
        return 0
    fi
    # Shells that ran set-proxy now point at a closed port, so even fetching
    # unset-proxy through curl would fail there; print the plain command.
    printf '%s\n' 'Clash is stopped. In shells where set-proxy was run, clear the proxy with:' \
        '  unset http_proxy https_proxy ftp_proxy all_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY ALL_PROXY no_proxy NO_PROXY'
}

if [[ "$mode" == stop ]]; then
    stop_all_clash
    exit 0
fi

if [[ -z "${config_url:-}" ]]; then
    printf '%s\n' 'The config_url environment variable is required.' >&2
    usage >&2
    exit 2
fi

for command_name in curl ss; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

case "${clash_core:-auto}" in
    auto) cores=(mihomo clash) ;;
    mihomo|clash) cores=("$clash_core") ;;
    *)
        printf 'clash_core must be auto, mihomo or clash: %s\n' "$clash_core" >&2
        exit 2
        ;;
esac

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

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Bundled files next to the script are only used from a checkout of this
# repository. run.sh runs a temporary copy with another name, and its directory
# (usually /tmp) may hold files planted by other users.
local_bundle=false
if [[ "$(basename -- "${BASH_SOURCE[0]}")" == clash.sh ]]; then
    local_bundle=true
fi
repo_base_urls=()
if [[ -n "${SCRIPTS_BASE_URL:-}" ]]; then
    repo_base_urls+=("$SCRIPTS_BASE_URL")
fi
repo_base_urls+=(https://gitee.com/hit_whr/scripts/raw/main
    https://raw.githubusercontent.com/whr819987540/scripts/main)
mihomo_dir="${install_dir}/mihomo"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/clash-setup.XXXXXX")"
temporary_config=""
binary_path=""

cleanup() {
    rm -rf "$work_dir"
    if [[ -n "$temporary_config" ]]; then
        rm -f "$temporary_config"
    fi
}
trap cleanup EXIT

# Copies a bundled file (a path under clash/ in this repository) to $2: from the
# checkout, or from the first mirror that serves it.
fetch_bundled_file() {
    local path="$1"
    local destination="$2"
    local base=""

    if $local_bundle && [[ -f "${script_dir}/${path}" ]]; then
        cp -f "${script_dir}/${path}" "$destination"
        return
    fi
    for base in "${repo_base_urls[@]}"; do
        if curl -fsSL --connect-timeout 15 --retry 2 "${base}/clash/${path}" -o "$destination"; then
            return 0
        fi
        printf 'Could not download %s from %s\n' "$path" "$base" >&2
    done
    return 1
}

# Succeeds when file $1 has the checksum listed for name $2 in SHA256SUMS file $3.
checksum_matches() {
    local expected=""
    local actual=""

    expected="$(awk -v name="$2" '$2 == name { print $1 }' "$3")"
    actual="$(sha256sum "$1" | cut -d' ' -f1)" || return 1
    [[ -n "$expected" && "$actual" == "$expected" ]]
}

# Moves $1 to $2 through a temporary file in the destination directory, so a
# running Clash that uses $2 keeps its open copy instead of reading a half-written
# one, and an executable in use does not fail with "Text file busy".
replace_file() {
    local staged="${2%/*}/.${2##*/}.new"

    cp -f "$1" "$staged" && mv -f "$staged" "$2"
}

# Succeeds when the geo data file $1 in the -d directory should be installed: it
# is missing or empty, or it is the 2022 Country.mmdb copied from clash-linux.zip.
# Other existing files are kept, since mihomo may have updated them itself.
needs_geo_file() {
    local target="${install_dir}/$1"

    [[ ! -s "$target" ]] && return 0
    [[ "$1" == Country.mmdb && -f "${install_dir}/clash/Country.mmdb" ]] \
        && cmp -s "$target" "${install_dir}/clash/Country.mmdb"
}

# Installs the bundled mihomo and its geo data, verified against
# clash/mihomo/SHA256SUMS, and sets binary_path. An installed binary whose
# checksum still matches is reused. Called as a condition, so each step checks
# its own failure instead of relying on set -e.
prepare_mihomo() {
    local sums="${work_dir}/SHA256SUMS"
    local sum=""
    local name=""
    local binary_name=""
    local part=""
    local file=""
    local parts=()

    if [[ "$(uname -m)" != x86_64 ]]; then
        printf 'The bundled mihomo is built for x86_64, not %s.\n' "$(uname -m)" >&2
        return 1
    fi
    for name in gzip sha256sum; do
        if ! command -v "$name" >/dev/null 2>&1; then
            printf 'mihomo needs the %s command.\n' "$name" >&2
            return 1
        fi
    done
    fetch_bundled_file mihomo/SHA256SUMS "$sums" || return 1
    while read -r sum name; do
        case "$name" in
            mihomo-*.gz.part-*) parts+=("$name") ;;
            mihomo-*) binary_name="$name" ;;
        esac
    done <"$sums"
    if [[ -z "$binary_name" || ${#parts[@]} -eq 0 ]]; then
        printf 'Unexpected contents in mihomo/SHA256SUMS.\n' >&2
        return 1
    fi

    mkdir -p "$mihomo_dir" || return 1
    binary_path="${mihomo_dir}/${binary_name}"
    if [[ -f "$binary_path" ]] && checksum_matches "$binary_path" "$binary_name" "$sums"; then
        printf 'Using the installed %s.\n' "$binary_name"
    else
        printf 'Installing %s.\n' "$binary_name"
        : >"${work_dir}/mihomo.gz" || return 1
        for part in "${parts[@]}"; do
            fetch_bundled_file "mihomo/${part}" "${work_dir}/${part}" || return 1
            if ! checksum_matches "${work_dir}/${part}" "$part" "$sums"; then
                printf 'Checksum mismatch for mihomo/%s.\n' "$part" >&2
                return 1
            fi
            cat "${work_dir}/${part}" >>"${work_dir}/mihomo.gz" || return 1
            rm -f "${work_dir}/${part}"
        done
        gzip -dc "${work_dir}/mihomo.gz" >"${work_dir}/${binary_name}" || return 1
        if ! checksum_matches "${work_dir}/${binary_name}" "$binary_name" "$sums"; then
            printf 'Checksum mismatch for the unpacked %s.\n' "$binary_name" >&2
            return 1
        fi
        chmod 755 "${work_dir}/${binary_name}" || return 1
        replace_file "${work_dir}/${binary_name}" "$binary_path" || return 1
    fi

    # mihomo reads these from the -d directory and downloads missing ones from
    # GitHub, which fails on hosts that need the proxy to reach it.
    for file in Country.mmdb GeoSite.dat; do
        needs_geo_file "$file" || continue
        printf 'Installing %s.\n' "$file"
        fetch_bundled_file "mihomo/${file}" "${work_dir}/${file}" || return 1
        if ! checksum_matches "${work_dir}/${file}" "$file" "$sums"; then
            printf 'Checksum mismatch for mihomo/%s.\n' "$file" >&2
            return 1
        fi
        replace_file "${work_dir}/${file}" "${install_dir}/${file}" || return 1
    done
}

# Installs the bundled Clash v1.10.0 and sets binary_path. Called as a condition.
prepare_clash() {
    local archive="${work_dir}/clash-linux.zip"
    local bundled_mmdb=""

    if ! command -v unzip >/dev/null 2>&1; then
        printf '%s\n' 'The Clash core needs the unzip command.' >&2
        return 1
    fi
    if [[ -n "${clash_download_url:-}" ]]; then
        curl -fsSL --connect-timeout 15 --retry 2 "$clash_download_url" -o "$archive" || return 1
    else
        fetch_bundled_file clash-linux.zip "$archive" || return 1
    fi
    unzip -oq "$archive" -d "$install_dir" || return 1
    binary_path="$(
        find "$install_dir" -maxdepth 2 -type f -name 'clash-linux-amd64-*' -print \
            | sort -V \
            | tail -n 1
    )"
    if [[ -z "$binary_path" ]]; then
        printf 'Clash executable not found under %s\n' "$install_dir" >&2
        return 1
    fi
    chmod a+x "$binary_path" || return 1

    # Clash reads Country.mmdb from the -d directory and downloads it when it is
    # missing, which fails on hosts that cannot reach the download site without
    # the proxy. Use the copy bundled next to the executable when there is none.
    bundled_mmdb="$(dirname -- "$binary_path")/Country.mmdb"
    if [[ ! -s "${install_dir}/Country.mmdb" && -f "$bundled_mmdb" ]]; then
        replace_file "$bundled_mmdb" "${install_dir}/Country.mmdb" || return 1
    fi
}

config_user_agent() {
    if [[ -n "${clash_user_agent:-}" ]]; then
        printf '%s\n' "$clash_user_agent"
    elif [[ "$1" == mihomo ]]; then
        printf '%s\n' 'clash.meta'
    else
        printf '%s\n' 'ClashforWindows/0.20.39'
    fi
}

# Explains a downloaded configuration that is not YAML at all, which the cores
# only report as a confusing YAML error.
describe_config_problem() {
    local start=""

    start="$(head -c 200 "$1" | tr -d '\r\n')"
    if [[ "$start" == '<'* ]]; then
        printf '%s\n' 'config_url returned an HTML page, not a Clash configuration.' >&2
    elif [[ -n "$start" && "$start" != *:* ]]; then
        printf '%s\n' 'config_url returned what looks like base64-encoded node links, not a Clash configuration.' >&2
    fi
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

# Try the cores in order. Each one gets the configuration downloaded with its
# own User-Agent, and must accept it before anything that is in use changes.
core=""
for candidate_core in "${cores[@]}"; do
    printf '[clash] Trying the %s core.\n' "$candidate_core"
    if ! "prepare_${candidate_core}"; then
        printf '[clash] Could not install the %s core.\n' "$candidate_core" >&2
        continue
    fi
    candidate_config="${work_dir}/config-${candidate_core}.yaml"
    if ! curl -fsSL --connect-timeout 15 --retry 2 \
        -A "$(config_user_agent "$candidate_core")" "$config_url" -o "$candidate_config"; then
        printf '[clash] Could not download config_url.\n' >&2
        continue
    fi
    if "$binary_path" -t -f "$candidate_config" -d "$install_dir"; then
        core="$candidate_core"
        break
    fi
    describe_config_problem "$candidate_config"
    printf '[clash] The configuration does not work with the %s core.\n' "$candidate_core" >&2
done

if [[ -z "$core" ]]; then
    printf '%s\n' "No core could use the configuration from config_url." \
        "The running Clash, if any, and ${config_path} were left unchanged." >&2
    exit 1
fi

if [[ "$mode" == "bg" ]]; then
    stop_background_clash
fi
install -m 600 "$candidate_config" "$config_path"
adjust_config_ports

if ! validation_output="$("$binary_path" -t -f "$config_path" -d "$install_dir" 2>&1)"; then
    printf '%s\n' "$validation_output" 'Validation failed after adjusting the ports.' >&2
    exit 1
fi

printf 'Core: %s\n' "$("$binary_path" -v 2>/dev/null | head -n 1)"
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
    if ! is_script_clash "$clash_pid"; then
        rm -f "$pid_path"
        printf 'Clash exited right after starting. Last lines of %s:\n' "$log_path" >&2
        tail -n 20 "$log_path" >&2
        exit 1
    fi

    printf 'Clash is running in the background (PID %s).\n' "$clash_pid"
    printf 'Log:  %s\n' "$log_path"
    printf 'Stop: source <(curl -fsSL %s/run.sh) clash stop\n' \
        "${SCRIPTS_BASE_URL:-https://gitee.com/hit_whr/scripts/raw/main}"
    printf '      or: kill "$(cat %s)"\n' "$pid_path"
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
