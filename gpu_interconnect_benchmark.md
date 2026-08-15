# GPU 互联带宽测试步骤

`gpu_interconnect_benchmark.sh` 收集 GPU 拓扑和 NVLink 状态，并依次构建、执行 NVIDIA `nvbandwidth`、CUDA Samples 的 `p2pBandwidthLatencyTest` 以及 NCCL Tests 的 `all_reduce_perf`。默认测试 `nvidia-smi` 检测到的全部 GPU。

下面以 CUDA 安装在 `/usr/local/cuda`、测试 GPU `0,1,2,3`、工作目录 `~/gpu-interconnect-benchmark` 为例。逐步执行时不依赖脚本中的环境变量。

## 1. 检查基础信息

确认至少有两张 GPU，并查看 GPU 间拓扑及每条 NVLink 的状态和速率：

```bash
nvidia-smi -L
nvidia-smi topo -m
nvidia-smi nvlink -s
```

## 2. 构建并运行 nvbandwidth

```bash
mkdir -p ~/gpu-interconnect-benchmark/src
cd ~/gpu-interconnect-benchmark/src
git clone https://github.com/NVIDIA/nvbandwidth.git

cmake -S nvbandwidth -B nvbandwidth/build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc
cmake --build nvbandwidth/build --parallel "$(nproc)"

CUDA_VISIBLE_DEVICES=0,1,2,3 \
LD_LIBRARY_PATH=/usr/local/cuda/lib64 \
nvbandwidth/build/nvbandwidth \
    -t device_to_device_bidirectional_memcpy_read_ce
```

重点查看 `Total bandwidth (GB/s)` 矩阵。这里的每个非对角值已经是两个方向同时传输的总带宽，不需要再乘以 2；矩阵 `SUM` 会把有向单元格全部相加，也不能直接和单张 GPU 的官方互联带宽比较。

## 3. 构建并运行 CUDA P2P Sample

```bash
cd ~/gpu-interconnect-benchmark/src
git clone https://github.com/NVIDIA/cuda-samples.git
cd cuda-samples/Samples/5_Domain_Specific/p2pBandwidthLatencyTest

cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc
cmake --build build --parallel "$(nproc)"

CUDA_VISIBLE_DEVICES=0,1,2,3 \
LD_LIBRARY_PATH=/usr/local/cuda/lib64 \
./build/p2pBandwidthLatencyTest
```

旧版 `cuda-samples` 的目录可能是 `cpp/5_Domain_Specific/p2pBandwidthLatencyTest`。重点查看 `P2P=Enabled` 的单向、双向带宽与延迟；CUDA Samples 自身也提示该示例并非严格的性能测量工具。

## 4. 构建并运行 NCCL Tests

```bash
cd ~/gpu-interconnect-benchmark/src
git clone https://github.com/NVIDIA/nccl-tests.git
make -C nccl-tests -j"$(nproc)" CUDA_HOME=/usr/local/cuda

cd nccl-tests
CUDA_VISIBLE_DEVICES=0,1,2,3 \
LD_LIBRARY_PATH=/usr/local/cuda/lib64 \
NCCL_DEBUG=INFO \
NCCL_P2P_DISABLE=0 \
NCCL_IB_DISABLE=1 \
./build/all_reduce_perf -b 8M -e 8G -f 2 -g 4 -w 20 -n 100 \
    | tee a800_4gpu_allreduce.log
```

`algbw` 表示算法有效带宽，`busbw` 是 NCCL 按集合通信流量模型归一化后的总线带宽。`busbw` 适合判断 AllReduce 效率，但不是某一条 NVLink 的直接测量结果。

## 5. 理解官方双向带宽

厂商标称的 NVLink 带宽通常指单张 GPU 跨全部 NVLink 的聚合双向带宽。比较测试结果时应保持相同口径：

- `nvbandwidth` 的 `Total` 和 CUDA Sample 的 `Bidirectional` 已经包含两个方向，不要再次翻倍。
- 点对点矩阵中的一个非对角单元表示一对 GPU 的并发双向结果。
- 矩阵 `SUM` 累加了多个 GPU 对以及对称位置，不能与单张 GPU 的官方标称值直接比较。
- NCCL `busbw` 是集合通信指标，不等于单链路或单 GPU 的原始 NVLink 带宽。

## 通过统一入口执行

默认测试全部检测到的 GPU，并把源码、构建产物和带时间戳的日志保存到 `~/gpu-interconnect-benchmark`：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) \
    gpu-interconnect-benchmark
```

指定工作目录和 GPU，例如只测试物理 GPU `0,1,2,3`：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) \
    gpu-interconnect-benchmark /data/gpu-benchmark 0,1,2,3
```

已有源码仓库会原样复用，不会自动执行 `git pull` 或覆盖本地修改。每次运行的日志位于 `<工作目录>/results/<时间戳>/`。
