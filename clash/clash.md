# Clash 安装与运行步骤

`clash.sh` 下载 Clash 和订阅配置，自动避开已占用的监听端口，然后以前台进程、后台进程或 systemd 服务运行。

执行前需要准备 Clash 订阅地址，并确保已安装 `curl`、`ss` 和 `unzip`。

## 前台运行

1. 创建安装目录。

   ```bash
   mkdir -p ~/clash
   ```

2. 下载并解压 Clash。仓库 `clash/` 目录下已有 `clash-linux.zip` 时，可跳过下载。

   ```bash
   curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/clash/clash-linux.zip \
       -o /tmp/clash-linux.zip
   unzip -oq /tmp/clash-linux.zip -d ~/clash
   ```

3. 下载订阅配置并限制文件权限。将 `<订阅地址>` 替换为实际地址。

   ```bash
   curl -fsSL '<订阅地址>' -o ~/clash/glados.yaml
   chmod 600 ~/clash/glados.yaml
   ```

4. 检查配置中的监听端口是否被占用。

   ```bash
   rg '^(port|socks-port|mixed-port|redir-port|tproxy-port|external-controller):|^[[:space:]]+listen:' \
       ~/clash/glados.yaml
   ss -lnt
   ss -lnu
   ```

   如果端口已被占用，将配置中的该端口依次加一，直到找到空闲端口。想固定使用某个端口时，直接把配置中的值改成该端口，例如 `port: 7890`；配置中没有该项时自行添加一行。脚本执行时会自动完成这一步，并在启动前打印最终使用的端口，见下文“端口”一节。

5. 找到 Clash 可执行文件并添加执行权限。

   ```bash
   find ~/clash -maxdepth 2 -type f -name 'clash-linux-amd64-*' -print
   chmod a+x ~/clash/<Clash可执行文件>
   ```

   再把压缩包自带的 GeoIP 数据库 `Country.mmdb`（与可执行文件同在 `~/clash/clash/`）复制到 `~/clash`。Clash 只在 `-d` 指定的目录中查找该文件，找不到时会从 jsdelivr 下载；机器无法访问 jsdelivr 时，下一步的验证会报 `can't download MMDB` 并失败。`cp -n` 不会覆盖已有的文件。

   ```bash
   cp -n ~/clash/clash/Country.mmdb ~/clash/
   ```

6. 验证配置，然后以前台方式启动。

   ```bash
   ~/clash/<Clash可执行文件> -t -f ~/clash/glados.yaml -d ~/clash
   ~/clash/<Clash可执行文件> -f ~/clash/glados.yaml -d ~/clash
   ```

也可以通过统一入口一次完成：

```bash
export config_url='<订阅地址>'
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash
```

`config_url` 和下文的端口变量都要用 `export` 设置。写在 `source` 前面的临时变量（`config_url=... source ...`）在 zsh 中不会传给入口启动的脚本。

## 后台运行

前台运行的 Clash 会随终端退出而停止。后台运行让 Clash 脱离终端，关闭终端或断开 SSH 后继续运行，适合没有 systemd 或 sudo 权限的环境（例如容器）。

1. 如果之前已在后台启动过 Clash，先停止它，否则它占用的端口会在第 2 步被判定为已占用。

   ```bash
   kill "$(cat ~/clash/clash.pid)"
   rm -f ~/clash/clash.pid
   ```

2. 完成前台运行部分的第 1 至 5 步，再执行第 6 步中带 `-t` 的验证命令。

3. 用 `setsid -f` 在新会话中启动 Clash 并立即返回。新会话没有控制终端，终端退出时 Clash 不会收到 SIGHUP。输出写入日志，进程号写入 PID 文件。

   ```bash
   setsid -f ~/clash/<Clash可执行文件> -f ~/clash/glados.yaml -d ~/clash \
       </dev/null >~/clash/clash.log 2>&1
   pgrep -n -f "$HOME/clash/glados.yaml" >~/clash/clash.pid
   ```

4. 确认进程在运行（`TT` 列为 `?` 表示已脱离终端），并查看日志。

   ```bash
   ps -o pid,tty,args -p "$(cat ~/clash/clash.pid)"
   tail -f ~/clash/clash.log
   ```

也可以通过统一入口一次完成：

```bash
export config_url='<订阅地址>'
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash bg
```

脚本会自动停止上一次 `bg` 启动的 Clash 后再启动新的，所以重复执行相当于重启，并且会沿用原来的端口。日志在每次启动时清空。停止后台 Clash：

```bash
kill "$(cat ~/clash/clash.pid)"
```

## systemd 服务运行

完成前台运行部分的第 1 至 6 步后：

1. 创建 `/etc/systemd/system/clash.service`，将 `<当前用户名>` 和 `<Clash可执行文件>` 替换为实际值。

   ```ini
   [Unit]
   Description=Clash proxy service
   After=network-online.target
   Wants=network-online.target

   [Service]
   Type=simple
   User=<当前用户名>
   WorkingDirectory=/home/<当前用户名>/clash
   ExecStart=/home/<当前用户名>/clash/<Clash可执行文件> -f /home/<当前用户名>/clash/glados.yaml -d /home/<当前用户名>/clash
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```

2. 重新加载 systemd，启用并立即启动服务。

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now clash.service
   sudo systemctl status --no-pager clash.service
   ```

也可以通过统一入口一次完成：

```bash
export config_url='<订阅地址>'
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash serve
```

## 端口

脚本把配置中被占用的监听端口依次加一，并在启动 Clash 前打印最终使用的端口，以及在其他终端使用该代理的 `set-proxy` 命令（HTTP 代理端口取 `mixed-port`，没有时取 `port`），例如：

```text
Clash listening ports (kept in /home/whr/clash/glados.yaml):
  port                 7891
  socks-port           7892
  external-controller  127.0.0.1:9090
Use the proxy in a shell:
  source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) set-proxy 127.0.0.1:7891
```

错过了这段输出时，可以在配置文件中查看；后台运行时也可以在日志中查看：

```bash
grep -E '^(port|socks-port|mixed-port|redir-port|tproxy-port|external-controller):' \
    ~/clash/glados.yaml
grep 'listening at' ~/clash/clash.log
```

要固定使用某个端口，在执行脚本前设置对应的环境变量。指定的端口被占用时脚本报错退出，不会改用其他端口；配置中没有该项时脚本会自动添加。其余未指定的端口仍按上面的规则自动调整，并避开指定的端口。

| 环境变量 | 配置项 |
| --- | --- |
| `clash_port` | `port`（HTTP 代理） |
| `clash_socks_port` | `socks-port`（SOCKS5 代理） |
| `clash_mixed_port` | `mixed-port`（同时提供 HTTP 和 SOCKS5 代理） |
| `clash_redir_port` | `redir-port` |
| `clash_tproxy_port` | `tproxy-port` |
| `clash_controller_port` | `external-controller` 中的端口 |

例如固定 HTTP 代理端口为 7890、控制端口为 9090，并在后台运行：

```bash
export config_url='<订阅地址>' clash_port=7890 clash_controller_port=9090
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash bg
```

这些变量导出后会一直留在当前 shell 中，之后再次执行时仍然生效。不再需要时用 `unset clash_port clash_controller_port` 取消。手动执行时，按前台运行第 4 步直接修改配置中的端口即可。
