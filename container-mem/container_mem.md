# 容器内存分析步骤

`container_mem.sh` 读取当前容器的 cgroup 内存统计和 `/proc` 下的进程信息，给出内存总量、组成、回收/OOM 事件、内存压力、按进程和按程序分组的占用，以及诊断结论。支持 cgroup v1 和 v2，下面的命令都在容器内执行。

1. 判断 cgroup 版本，并进入本容器的 cgroup 目录。

   ```bash
   test -f /sys/fs/cgroup/cgroup.controllers && echo v2 || echo v1
   ```

   - v2：`cd /sys/fs/cgroup`，目录里应有 `memory.current`。
   - v1：`cd /sys/fs/cgroup/memory`，目录里应有 `memory.usage_in_bytes`。

   如果找不到对应文件，说明容器没有独立的 cgroup namespace，需要在上面的目录后面接上 `cat /proc/self/cgroup` 输出里的路径（v2 取 `0::` 开头那行，v1 取含 `memory` 的那行）。以下命令都在这个目录下执行，单位为字节。

2. 查看当前用量、上限和历史峰值。

   ```bash
   cat memory.current memory.max memory.peak                                # v2
   cat memory.usage_in_bytes memory.limit_in_bytes memory.max_usage_in_bytes  # v1
   grep MemTotal /proc/meminfo
   ```

   v2 的上限为 `max`、v1 的上限接近 2^63 时表示不限制，此时按宿主机的 `MemTotal` 计算比例。`memory.peak` 需要内核 5.19 及以上。

3. 查看内存组成。

   ```bash
   grep -E '^(anon|file|shmem|active_file|inactive_file) ' memory.stat              # v2
   grep -E '^total_(rss|cache|shmem|active_file|inactive_file) ' memory.stat        # v1
   ```

   - `anon`（v1 为 `total_rss`）：进程的堆、栈等匿名内存，没有 swap 时不可回收。
   - `file`（v1 为 `total_cache`）：文件缓存，其中 `inactive_file` 会被优先回收。
   - `shmem`：`/dev/shm` 等共享内存，计入 `file`，但没有 swap 时同样不可回收。

   再用上一步的当前用量计算三个派生值：

   - `other` = 当前用量 − anon − file：slab、页表等内核开销。
   - 工作集 = 当前用量 − inactive_file：即 `docker stats` / `kubectl top` 显示的值。
   - 不可回收 = anon + shmem + other：这部分接近上限时就会触发 OOM。

4. 查看触顶和 OOM 次数。

   ```bash
   cat memory.events                   # v2：max 为顶到上限次数，oom_kill 为进程被杀次数
   cat memory.failcnt                  # v1：顶到上限次数
   grep oom_kill memory.oom_control    # v1：进程被杀次数，需要内核 4.13 及以上
   ```

5. 查看内存压力（仅 cgroup v2，且内核开启了 PSI）。

   ```bash
   cat memory.pressure
   ```

   `some` 是至少有一个进程在等内存的时间比例，`full` 是所有进程都在等内存的时间比例；`avg10` 超过 5 说明回收已经明显拖慢运行。

6. 按 RSS 列出占用最多的进程。

   ```bash
   ps -eo pid,rss,args --sort=-rss | head -n 16
   grep -E '^(VmRSS|RssAnon):' /proc/<PID>/status
   ```

   RSS 包含映射进内存的可执行文件等文件页，所以各进程合计通常比 cgroup 的 `anon` 大；`RssAnon` 更接近进程实际占用的匿名内存。精简镜像里的 `ps` 不支持这些参数时，可以直接读 `/proc/<PID>/status`。

7. 按程序名汇总 RSS。

   ```bash
   ps -eo rss=,comm= | awk '{ s[$2] += $1; c[$2]++ } END { for (k in s) printf "%10.1f M %4d  %s\n", s[k] / 1024, c[k], k }' | sort -nr | head -n 15
   ```

   脚本的分组更细：`python`、`node` 按脚本名或 `-m` 模块名区分，VS Code / Cursor / Windsurf 的远程服务进程各自归为一组。

8. 根据前面的结果判断风险。

   - `oom_kill` 大于 0：已经有进程因为内存不足被杀。
   - 不可回收内存占上限 90% 以上很危险，75% 以上比较紧张。
   - 当前用量贴近上限且顶到上限的次数持续增加：容器一直靠回收文件缓存维持运行，`import`、编译、`git` 等频繁读文件的操作会变慢。
   - AutoDL 实例的上限不超过 3 GiB 时，通常是无卡模式开机；编译或运行大模型前需要切换到有卡模式。

也可以通过统一入口一次输出全部分析：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) container-mem
```

用 `-n` 指定进程和分组列表显示的条数，例如只看前 5 项：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) container-mem -n 5
```
