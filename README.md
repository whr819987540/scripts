# 实用脚本

**这个仓库用来存放一些实用的脚本。**

## Linux 远程执行

通过统一入口传入命令名称：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) <command>
```

默认从 [Gitee](https://gitee.com/hit_whr/scripts) 下载入口脚本和后续脚本。如果需要使用 GitHub，可以通过环境变量切换下载源：

```bash
export SCRIPTS_BASE_URL=https://raw.githubusercontent.com/whr819987540/scripts/main
source <(curl -fsSL "$SCRIPTS_BASE_URL/run.sh") docker
```

安装clash:

```bash
export clash_download_url="https://gitee.com/hit_whr/scripts/raw/main/clash-linux.zip"
export config_url="xxx"
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash
```

例如，取消当前终端中的代理环境变量：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) unset-proxy
```

使用默认地址 `127.0.0.1:7890` 设置当前终端的代理环境变量：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) set-proxy
```

也可以通过参数或 `proxy` 环境变量指定代理：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) \
    set-proxy 192.168.1.10:7890

proxy=socks5://127.0.0.1:1080 \
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) set-proxy
```

安装 Docker：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) docker
```

查看 NVIDIA GPU 进程所属的 Docker 容器：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) gpu-docker-processes
```

构建并运行 GPU 互联带宽、延迟和 NCCL AllReduce 测试：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) \
    gpu-interconnect-benchmark /data/gpu-benchmark 0,1,2,3
```

持续查看网卡的区间平均和累计平均速度：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) network-speed eth0 1
```

查看所有可用命令：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) help
```
