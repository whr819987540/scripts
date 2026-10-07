# GPU Docker 进程查询步骤

`gpu_docker_processes.sh` 查询正在使用 NVIDIA GPU 的进程，并根据 Linux cgroup 信息定位所属 Docker 容器。

1. 确认 NVIDIA 驱动、Docker 和 Linux `/proc` 文件系统可用。

   ```bash
   command -v nvidia-smi
   command -v docker
   test -d /proc
   ```

2. 查询所有正在使用 GPU 进行计算的进程 ID。

   ```bash
   nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits
   ```

   没有输出表示当前没有计算进程使用 NVIDIA GPU。

3. 对每个查询到的 `<PID>`，从 cgroup 中提取 Docker 容器 ID。

   ```bash
   grep -oP '(?<=docker[-/])[0-9a-f]{12,64}' /proc/<PID>/cgroup | head -n1
   ```

   没有容器 ID 表示该进程位于宿主机，或者运行时没有使用脚本支持的 Docker cgroup 格式。

4. 用上一步得到的 `<容器ID>` 查询运行中的容器名称。

   ```bash
   docker ps --filter 'id=<容器ID>' --format '{{.Names}}'
   ```

也可以通过统一入口自动查询全部 GPU 进程：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) gpu-docker-processes
```
