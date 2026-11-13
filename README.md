# 实用脚本

**这个仓库用来存放一些实用的脚本。**

## 目录结构

每个功能一个目录，目录名与 `run.sh` 的命令名一致，脚本和同名的 step-by-step 文档放在一起：

| 目录 | `run.sh` 命令 | 内容 |
|---|---|---|
| `proxy/` | `set-proxy`、`unset-proxy` | 设置 / 清除当前 shell 的代理环境变量 |
| `docker/` | `docker` | 安装 Docker |
| `git/` | `git` | 安装配置 Git、SSH 密钥和 GitHub SSH 代理 |
| `miniconda/` | `miniconda` | 无交互安装 Miniconda |
| `nvm/` | `nvm` | 安装 nvm 和 Node.js |
| `zsh/` | `zsh` | 安装配置 Zsh、Oh My Zsh 和插件 |
| `tmux/` | `tmux` | 安装 tmux 3.7b 并写入 `~/.tmux.conf` |
| `new-user/` | `new-user` | 创建并配置用户 |
| `add-authorized-key/` | `add-authorized-key` | 添加 SSH 授权公钥 |
| `zabbix-agent/` | `zabbix-agent` | 安装配置 Zabbix Agent |
| `clash/` | `clash` | 安装运行 Clash（mihomo 内核，备用 Clash v1.10.0；含 `mihomo/` 和 `clash-linux.zip`） |
| `gpu-docker-processes/` | `gpu-docker-processes` | 查看 GPU 进程所属的 Docker 容器 |
| `gpu-interconnect-benchmark/` | `gpu-interconnect-benchmark` | GPU 互联带宽与 NCCL 测试 |
| `network-speed/` | `network-speed` | 监控网卡速度 |
| `container-mem/` | `container-mem` | 分析容器内存占用 |
| `claude-sync-settings/` | `claude-sync` | 多机同步 Claude Code 用户级配置和状态栏（原 claude-sync-settings 仓库） |
| `python-utils/` | — | Python 日志初始化等工具函数 |

根目录只保留统一入口 `run.sh` 及其文档 `run.md`。

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
export config_url="xxx"
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash
```

默认使用 mihomo 内核，装不上或不支持配置时改用 Clash v1.10.0 内核。内核和 geo 数据都随仓库提供，先从 Gitee 下载，不需要访问 GitHub。用 `export clash_core=clash` 可以只用旧内核。

在后台运行，关闭终端后继续运行（日志 `~/clash/clash.log`）：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash bg
```

停止 Clash（前台、后台和 systemd 服务方式启动的都能停，不需要 `config_url`）：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash stop
```

被占用的端口会自动加一，最终使用的端口在启动前打印出来。要固定端口，先 `export clash_port=7890`（HTTP 代理端口）等变量，详见 `clash/clash.md` 的“端口”一节。

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

安装 tmux 3.7b 到 `~/.local/bin`（非交互式 shell 也能使用），并写入 `~/.tmux.conf`：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) tmux
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

分析当前容器的内存占用（`-n N` 指定进程列表显示前 N 项，默认 15）：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) container-mem
```

把共享的 Claude Code 配置和状态栏同步到本机（每处改动都会先确认，需要 Python 3.8+；`--dry-run` 只看差异）：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) claude-sync
```

比对规则和 Windows 下的用法见 [`claude-sync-settings/README.md`](claude-sync-settings/README.md)。

查看所有可用命令：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) help
```
