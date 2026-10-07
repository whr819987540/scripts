#!/usr/bin/env bash

# Monitor interval and cumulative average throughput for a Linux network interface.

export LC_ALL=C

usage() {
    cat <<'EOF'
Usage:
  network_speed.sh [interface] [interval]

Arguments:
  interface  Network interface to monitor (default: eth0)
  interval   Sampling interval in seconds; decimals are allowed (default: 1)

Press Ctrl+C to stop measuring.
EOF
}

if [[ $# -gt 2 ]]; then
    printf '%s\n\n' 'Too many arguments.' >&2
    usage >&2
    exit 2
fi

case "${1:-}" in
    help|-h|--help)
        usage
        exit 0
        ;;
esac

interface="${1:-eth0}"
interval="${2:-1}"

if [[ ! -r /proc/net/dev || ! -r /proc/uptime ]]; then
    printf '%s\n' 'Error: this script requires Linux /proc/net/dev and /proc/uptime.' >&2
    exit 1
fi

if ! command -v awk >/dev/null 2>&1 || ! command -v sleep >/dev/null 2>&1; then
    printf '%s\n' 'Error: awk and sleep are required.' >&2
    exit 1
fi

if [[ ! "$interval" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] \
    || ! awk -v value="$interval" 'BEGIN {exit !(value > 0)}'; then
    printf 'Error: interval must be a number greater than zero: %s\n' "$interval" >&2
    exit 2
fi

read_counters() {
    awk -v iface="$interface" '
        $1 == iface ":" {
            print $2, $10
            found = 1
            exit
        }
        END {if (!found) exit 1}
    ' /proc/net/dev
}

read_uptime() {
    awk '{print $1; exit}' /proc/uptime
}

if ! counters="$(read_counters)"; then
    printf 'Error: network interface not found: %s\n' "$interface" >&2
    exit 1
fi

read -r previous_rx previous_tx <<<"$counters"
previous_time="$(read_uptime)"
start_rx="$previous_rx"
start_tx="$previous_tx"
start_time="$previous_time"

printf 'Measuring %s every %s second(s); press Ctrl+C to stop.\n' \
    "$interface" "$interval"

while true; do
    sleep "$interval"

    if ! counters="$(read_counters)"; then
        printf 'Error: network interface is no longer available: %s\n' "$interface" >&2
        exit 1
    fi

    read -r current_rx current_tx <<<"$counters"
    current_time="$(read_uptime)"

    if ((current_rx < previous_rx || current_tx < previous_tx)); then
        printf '[%s] Network counters were reset; restarting cumulative measurement.\n' \
            "$interface" >&2
        previous_rx="$current_rx"
        previous_tx="$current_tx"
        previous_time="$current_time"
        start_rx="$current_rx"
        start_tx="$current_tx"
        start_time="$current_time"
        continue
    fi

    interval_rx_bytes=$((current_rx - previous_rx))
    interval_tx_bytes=$((current_tx - previous_tx))
    total_rx_bytes=$((current_rx - start_rx))
    total_tx_bytes=$((current_tx - start_tx))

    awk \
        -v iface="$interface" \
        -v interval_rx="$interval_rx_bytes" \
        -v interval_tx="$interval_tx_bytes" \
        -v total_rx="$total_rx_bytes" \
        -v total_tx="$total_tx_bytes" \
        -v previous_time="$previous_time" \
        -v start_time="$start_time" \
        -v current_time="$current_time" '
        BEGIN {
            interval_elapsed = current_time - previous_time
            total_elapsed = current_time - start_time
            if (interval_elapsed <= 0 || total_elapsed <= 0) {
                exit 1
            }

            printf "[%s] Interval avg (%.2fs) RX: %.2f Mbps | TX: %.2f Mbps", \
                iface, interval_elapsed, \
                interval_rx * 8 / interval_elapsed / 1000000, \
                interval_tx * 8 / interval_elapsed / 1000000
            printf " || Total avg (%.2fs) RX: %.2f Mbps | TX: %.2f Mbps\n", \
                total_elapsed, \
                total_rx * 8 / total_elapsed / 1000000, \
                total_tx * 8 / total_elapsed / 1000000
        }
    ' || {
        printf '%s\n' 'Error: failed to calculate elapsed time.' >&2
        exit 1
    }

    previous_rx="$current_rx"
    previous_tx="$current_tx"
    previous_time="$current_time"
done
