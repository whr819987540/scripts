# 实用脚本

**这个仓库用来存放一些实用的脚本。**

## Linux 远程执行

通过统一入口传入命令名称：

```bash
source <(curl -fsSL https://raw.githubusercontent.com/whr819987540/scripts/main/run.sh) <command>
```

例如，取消当前终端中的代理环境变量：

```bash
source <(curl -fsSL https://raw.githubusercontent.com/whr819987540/scripts/main/run.sh) unset-proxy
```

安装 Docker：

```bash
source <(curl -fsSL https://raw.githubusercontent.com/whr819987540/scripts/main/run.sh) docker
```

查看 NVIDIA GPU 进程所属的 Docker 容器：

```bash
source <(curl -fsSL https://raw.githubusercontent.com/whr819987540/scripts/main/run.sh) gpu-docker-processes
```

查看所有可用命令：

```bash
source <(curl -fsSL https://raw.githubusercontent.com/whr819987540/scripts/main/run.sh) help
```
