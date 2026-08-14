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

安装 Docker：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) docker
```

查看 NVIDIA GPU 进程所属的 Docker 容器：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) gpu-docker-processes
```

查看所有可用命令：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) help
```
