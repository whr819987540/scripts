#!/usr/bin/env bash

# Show which Docker container owns each process currently using an NVIDIA GPU.

if ! command -v nvidia-smi >/dev/null 2>&1; then
    printf '%s\n' '错误: 未找到 nvidia-smi，请确认 NVIDIA 驱动已正确安装。' >&2
    exit 1
fi

if [[ ! -d /proc ]]; then
    printf '%s\n' '错误: 未找到 /proc；该脚本需要在 Linux 宿主机上运行。' >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    printf '%s\n' '错误: 未找到 docker 命令。' >&2
    exit 1
fi

gpu_pids="$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits)" || {
    printf '%s\n' '错误: 无法查询 NVIDIA GPU 进程。' >&2
    exit 1
}

if [[ -z "$gpu_pids" ]]; then
    printf '%s\n' '当前没有进程使用 NVIDIA GPU。'
    exit 0
fi

printf 'GPU 使用的 PIDs:\n%s\n' "$gpu_pids"

for pid in $gpu_pids; do
    if [[ ! -d "/proc/$pid" ]]; then
        printf 'PID %s -> 进程不存在 (可能已退出)\n' "$pid"
        continue
    fi

    # Support both systemd (.../docker-<id>.scope) and cgroupfs (.../docker/<id>).
    container_id="$(grep -oP '(?<=docker[-/])[0-9a-f]{12,64}' "/proc/$pid/cgroup" 2>/dev/null | head -n1)"

    if [[ -z "$container_id" ]]; then
        printf 'PID %s -> 不在任何 Docker 容器内 (宿主机进程)\n' "$pid"
        continue
    fi

    container_name="$(docker ps --filter "id=$container_id" --format '{{.Names}}' 2>/dev/null | head -n1)"
    if [[ -n "$container_name" ]]; then
        printf 'PID %s -> 容器: %s (%s)\n' "$pid" "$container_name" "$container_id"
    else
        printf 'PID %s -> 容器 ID %s (未找到运行中的容器名，可能已停止或无 Docker 查询权限)\n' "$pid" "$container_id"
    fi
done
