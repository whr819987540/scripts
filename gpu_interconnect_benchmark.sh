#!/usr/bin/env bash

# Build and run NVIDIA GPU interconnect benchmarks with reproducible logs.

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  gpu_interconnect_benchmark.sh [work-dir] [gpu-devices]

Arguments:
  work-dir    Source, build, and result directory
              (default: $HOME/gpu-interconnect-benchmark)
  gpu-devices Comma-separated physical GPU indexes (default: all detected GPUs)

Environment:
  CUDA_HOME       CUDA Toolkit location (default: /usr/local/cuda)
  NCCL_MIN_BYTES  all_reduce_perf minimum message size (default: 8M)
  NCCL_MAX_BYTES  all_reduce_perf maximum message size (default: 8G)
  NCCL_WARMUP     all_reduce_perf warmup iterations (default: 20)
  NCCL_ITERS      all_reduce_perf measurement iterations (default: 100)

The script requires nvidia-smi, git, CMake, Make, a C++ compiler, and CUDA.
Existing source repositories are reused without being updated or overwritten.
EOF
}

case "${1:-}" in
    help|-h|--help)
        usage
        exit 0
        ;;
esac

if [[ $# -gt 2 ]]; then
    printf '%s\n\n' 'Error: too many arguments.' >&2
    usage >&2
    exit 2
fi

readonly work_dir="${1:-${HOME}/gpu-interconnect-benchmark}"
readonly requested_devices="${2:-}"
readonly cuda_home="${CUDA_HOME:-/usr/local/cuda}"
readonly nccl_min_bytes="${NCCL_MIN_BYTES:-8M}"
readonly nccl_max_bytes="${NCCL_MAX_BYTES:-8G}"
readonly nccl_warmup="${NCCL_WARMUP:-20}"
readonly nccl_iters="${NCCL_ITERS:-100}"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Error: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

for required_command in nvidia-smi git cmake make tee nproc date; do
    require_command "$required_command"
done

if [[ ! -x "$cuda_home/bin/nvcc" ]]; then
    printf 'Error: CUDA compiler not found: %s/bin/nvcc\n' "$cuda_home" >&2
    printf '%s\n' 'Set CUDA_HOME to the CUDA Toolkit installation directory.' >&2
    exit 1
fi

export PATH="$cuda_home/bin:$PATH"
export LD_LIBRARY_PATH="$cuda_home/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LC_ALL=C

if ! gpu_index_output="$(
    nvidia-smi --query-gpu=index --format=csv,noheader,nounits
)"; then
    printf '%s\n' 'Error: failed to query physical GPU indexes.' >&2
    exit 1
fi
mapfile -t detected_gpu_indexes <<<"$gpu_index_output"
gpu_count="${#detected_gpu_indexes[@]}"
if ((gpu_count < 2)); then
    printf 'Error: at least two NVIDIA GPUs are required; detected: %s\n' "$gpu_count" >&2
    exit 1
fi

declare -A detected_gpu_index_set=()
for gpu_index in "${detected_gpu_indexes[@]}"; do
    detected_gpu_index_set[$gpu_index]=1
done

if [[ -n "$requested_devices" ]]; then
    IFS=',' read -r -a gpu_devices <<<"$requested_devices"
else
    gpu_devices=("${detected_gpu_indexes[@]}")
fi

if ((${#gpu_devices[@]} < 2)); then
    printf '%s\n' 'Error: gpu-devices must contain at least two indexes.' >&2
    exit 2
fi

declare -A selected_gpu_indexes=()
for gpu_index in "${gpu_devices[@]}"; do
    if [[ ! "$gpu_index" =~ ^[0-9]+$ ]] \
        || [[ -z "${detected_gpu_index_set[$gpu_index]:-}" ]]; then
        printf 'Error: invalid GPU index %q; detected indexes: %s\n' \
            "$gpu_index" "${detected_gpu_indexes[*]}" >&2
        exit 2
    fi
    if [[ -n "${selected_gpu_indexes[$gpu_index]:-}" ]]; then
        printf 'Error: duplicate GPU index: %s\n' "$gpu_index" >&2
        exit 2
    fi
    selected_gpu_indexes[$gpu_index]=1
done

gpu_devices_csv="$(IFS=,; printf '%s' "${gpu_devices[*]}")"
readonly gpu_devices_csv
readonly selected_gpu_count="${#gpu_devices[@]}"
readonly parallel_jobs="$(nproc)"

mkdir -p "$work_dir/src" "$work_dir/results"
readonly result_dir="$work_dir/results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$result_dir"

clone_if_missing() {
    local repository_url="$1"
    local destination="$2"

    if [[ -d "$destination/.git" ]]; then
        printf 'Reusing source repository: %s\n' "$destination"
        return 0
    fi
    if [[ -e "$destination" ]]; then
        printf 'Error: destination exists but is not a Git repository: %s\n' \
            "$destination" >&2
        exit 1
    fi
    git clone "$repository_url" "$destination"
}

run_logged() {
    local log_file="$1"
    shift

    printf '\n>>> '
    printf '%q ' "$@"
    printf '\n'
    "$@" 2>&1 | tee "$result_dir/$log_file"
}

readonly nvbandwidth_dir="$work_dir/src/nvbandwidth"
readonly cuda_samples_dir="$work_dir/src/cuda-samples"
readonly p2p_sample_dir="$cuda_samples_dir/Samples/5_Domain_Specific/p2pBandwidthLatencyTest"
readonly legacy_p2p_sample_dir="$cuda_samples_dir/cpp/5_Domain_Specific/p2pBandwidthLatencyTest"
readonly nccl_tests_dir="$work_dir/src/nccl-tests"

printf 'Work directory: %s\n' "$work_dir"
printf 'Result directory: %s\n' "$result_dir"
printf 'CUDA Toolkit: %s\n' "$cuda_home"
printf 'Selected physical GPUs: %s\n' "$gpu_devices_csv"

run_logged gpu-list.log nvidia-smi -L
run_logged gpu-topology.log nvidia-smi topo -m
run_logged nvlink-status.log nvidia-smi nvlink -s

clone_if_missing https://github.com/NVIDIA/nvbandwidth.git "$nvbandwidth_dir"
cmake -S "$nvbandwidth_dir" -B "$nvbandwidth_dir/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_COMPILER="$cuda_home/bin/nvcc"
cmake --build "$nvbandwidth_dir/build" --parallel "$parallel_jobs"

export CUDA_VISIBLE_DEVICES="$gpu_devices_csv"
run_logged nvbandwidth-bidirectional.log \
    "$nvbandwidth_dir/build/nvbandwidth" \
    -t device_to_device_bidirectional_memcpy_read_ce

clone_if_missing https://github.com/NVIDIA/cuda-samples.git "$cuda_samples_dir"
if [[ -d "$p2p_sample_dir" ]]; then
    selected_p2p_sample_dir="$p2p_sample_dir"
elif [[ -d "$legacy_p2p_sample_dir" ]]; then
    selected_p2p_sample_dir="$legacy_p2p_sample_dir"
else
    printf '%s\n' 'Error: p2pBandwidthLatencyTest was not found in cuda-samples.' >&2
    exit 1
fi
readonly selected_p2p_sample_dir

cmake -S "$selected_p2p_sample_dir" -B "$selected_p2p_sample_dir/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_COMPILER="$cuda_home/bin/nvcc"
cmake --build "$selected_p2p_sample_dir/build" --parallel "$parallel_jobs"
run_logged cuda-p2p-bandwidth-latency.log \
    "$selected_p2p_sample_dir/build/p2pBandwidthLatencyTest"

clone_if_missing https://github.com/NVIDIA/nccl-tests.git "$nccl_tests_dir"
make -C "$nccl_tests_dir" -j"$parallel_jobs" CUDA_HOME="$cuda_home"

export NCCL_DEBUG=INFO
export NCCL_P2P_DISABLE=0
export NCCL_IB_DISABLE=1
run_logged nccl-all-reduce.log \
    "$nccl_tests_dir/build/all_reduce_perf" \
    -b "$nccl_min_bytes" -e "$nccl_max_bytes" -f 2 \
    -g "$selected_gpu_count" -w "$nccl_warmup" -n "$nccl_iters"

cat <<EOF

All benchmarks completed. Logs: $result_dir

Interpretation:
  * nvbandwidth "Total" and CUDA Samples "Bidirectional" values already add
    simultaneous traffic in both directions. Do not multiply them by two.
  * A vendor's quoted NVLink bandwidth is normally aggregate bidirectional
    bandwidth per GPU across its links, not a sum of every cell in a GPU matrix.
  * NCCL busbw is a topology-normalized collective metric. It is useful for
    comparing all-reduce efficiency, but is not a direct measurement of one link.
EOF
