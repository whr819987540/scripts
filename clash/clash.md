# Clash 安装与运行步骤

`clash.sh` 优先使用 mihomo 内核，装不上或不支持订阅配置时改用原版 Clash v1.10.0 内核。它下载订阅配置并验证通过后，才替换正在使用的配置和后台进程，自动避开已占用的监听端口，然后以前台进程、后台进程或 systemd 服务运行。

执行前需要准备 Clash 订阅地址，并确保已安装 `curl` 和 `ss`。mihomo 内核还需要 `gzip` 和 `sha256sum`，Clash 内核需要 `unzip`。

## 内核

两个内核都随仓库提供，脚本依次尝试 `SCRIPTS_BASE_URL`（设置了的话）、Gitee、GitHub，所以机器不需要能访问 GitHub：

- mihomo v1.19.33，x86_64 的 compatible 构建（不要求 CPU 支持 AVX2），放在 `clash/mihomo/`：
  - `mihomo-linux-amd64-compatible-v1.19.33.gz.part-NN`：官方发布的 `.gz` 按 9 MB 切成的分片。目前只确认过 Gitee raw 能下载 10 MB 左右的文件，所以切分；
  - `Country.mmdb`、`GeoSite.dat`：来自 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) 的 `country.mmdb` 和 `geosite.dat`（2026-11-13）。mihomo 在 `-d` 目录中找不到它们时会从 GitHub 下载，而 hpc 这类机器在代理启动前访问不了 GitHub；
  - `SHA256SUMS`：上述文件和解压后的可执行文件的校验和，脚本逐个校验。
- Clash v1.10.0：`clash/clash-linux.zip`，不支持 vless、hysteria2 等新协议和 mihomo 的配置写法。

下文的 `<内核可执行文件>` 指 `mihomo/mihomo-linux-amd64-compatible-v1.19.33` 或 `clash/clash-linux-amd64-v1.10.0`（相对 `~/clash`）。

机场的订阅地址常按 User-Agent 返回不同格式：curl 默认的 User-Agent 拿到的往往是 base64 编码的节点链接，不是 Clash 配置；`clash.meta` 拿到 mihomo 格式，节点最全；`ClashforWindows` 拿到原版 Clash 能用的格式，通常只剩 ss 等老协议。所以脚本给 mihomo 下载配置时用 `clash.meta`，给 Clash 内核用 `ClashforWindows/0.20.39`。GLaDOS 的地址不看 User-Agent，`/clash/` 和 `/mihomo/` 路径分别返回两种格式，两种 mihomo 都能用。

环境变量：

- `clash_core`：`auto`（默认，先 mihomo 再 Clash）、`mihomo` 或 `clash`；
- `clash_user_agent`：下载订阅配置用的 User-Agent，覆盖上面的默认值；
- `clash_download_url`：Clash 内核 `clash-linux.zip` 的地址，例如官方的 `https://glados.rocks/tools/clash-linux.zip`。

## 前台运行

以下用 mihomo 内核；mihomo 不能用时见下一节。

1. 创建安装目录，进入一个临时目录下载文件。

   ```bash
   mkdir -p ~/clash/mihomo
   cd "$(mktemp -d)"
   base=https://gitee.com/hit_whr/scripts/raw/main/clash/mihomo
   name=mihomo-linux-amd64-compatible-v1.19.33
   ```

2. 下载 mihomo 分片、geo 数据和校验清单，并校验下载的文件。`--ignore-missing` 跳过还没解压出来的可执行文件。

   ```bash
   curl -fsSLO "$base/SHA256SUMS"
   for f in $(awk '{ print $2 }' SHA256SUMS | grep -E '\.part-|\.mmdb$|\.dat$'); do
       curl -fsSLO "$base/$f"
   done
   sha256sum -c --ignore-missing SHA256SUMS
   ```

3. 拼接分片并解压，校验解压出的可执行文件，再安装到 `~/clash/mihomo/`。

   ```bash
   cat "$name".gz.part-* | gzip -dc > "$name"
   sha256sum -c --ignore-missing SHA256SUMS
   install -m 755 "$name" ~/clash/mihomo/
   ```

4. 把 geo 数据放到 `~/clash`。已有的文件可能是 mihomo 自己更新过的，`cp -n` 不覆盖它们；但旧版 Clash 自带的 2022 年 `Country.mmdb` 要换掉。

   ```bash
   cmp -s ~/clash/Country.mmdb ~/clash/clash/Country.mmdb && rm ~/clash/Country.mmdb
   cp -n Country.mmdb GeoSite.dat ~/clash/
   ```

5. 用 `clash.meta` 作为 User-Agent 下载订阅配置，先在临时目录中验证。将 `<订阅地址>` 替换为实际地址。验证失败时不要继续，改用下一节的 Clash 内核。

   ```bash
   curl -fsSL -A clash.meta '<订阅地址>' -o config.yaml
   ~/clash/mihomo/"$name" -t -f config.yaml -d ~/clash
   ```

6. 安装配置并限制文件权限，然后检查配置中的监听端口是否被占用。

   ```bash
   install -m 600 config.yaml ~/clash/glados.yaml
   rg '^(port|socks-port|mixed-port|redir-port|tproxy-port|external-controller):|^[[:space:]]+listen:' \
       ~/clash/glados.yaml
   ss -lnt
   ss -lnu
   ```

   如果端口已被占用，将配置中的该端口依次加一，直到找到空闲端口。想固定使用某个端口时，直接把配置中的值改成该端口，例如 `port: 7890`；配置中没有该项时自行添加一行。脚本执行时会自动完成这一步，并在启动前打印最终使用的端口，见下文“端口”一节。

7. 再次验证配置，然后以前台方式启动。

   ```bash
   ~/clash/mihomo/"$name" -t -f ~/clash/glados.yaml -d ~/clash
   ~/clash/mihomo/"$name" -f ~/clash/glados.yaml -d ~/clash
   ```

## 使用 Clash v1.10.0 内核

mihomo 不能用（例如不是 x86_64）或不支持订阅配置时，用旧内核代替前台运行的第 1 至 5 步：

1. 下载并解压 Clash。仓库 `clash/` 目录下已有 `clash-linux.zip` 时，可跳过下载。

   ```bash
   mkdir -p ~/clash
   cd "$(mktemp -d)"
   curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/clash/clash-linux.zip -o clash-linux.zip
   unzip -oq clash-linux.zip -d ~/clash
   chmod a+x ~/clash/clash/clash-linux-amd64-v1.10.0
   ```

2. 把压缩包自带的 GeoIP 数据库 `Country.mmdb` 复制到 `~/clash`。Clash 只在 `-d` 指定的目录中查找该文件，找不到时会从 jsdelivr 下载；机器无法访问 jsdelivr 时，验证会报 `can't download MMDB` 并失败。`cp -n` 不会覆盖已有的文件。

   ```bash
   cp -n ~/clash/clash/Country.mmdb ~/clash/
   ```

3. 用 `ClashforWindows/0.20.39` 作为 User-Agent 下载订阅配置并验证。

   ```bash
   curl -fsSL -A ClashforWindows/0.20.39 '<订阅地址>' -o config.yaml
   ~/clash/clash/clash-linux-amd64-v1.10.0 -t -f config.yaml -d ~/clash
   ```

然后执行前台运行的第 6、7 步，把其中的 `~/clash/mihomo/"$name"` 换成 `~/clash/clash/clash-linux-amd64-v1.10.0`。

## 通过统一入口运行

前台运行可以通过统一入口一次完成，内核按上文的顺序自动选择：

```bash
export config_url='<订阅地址>'
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash
```

`config_url` 和下文的端口变量都要用 `export` 设置。写在 `source` 前面的临时变量（`config_url=... source ...`）在 zsh 中不会传给入口启动的脚本。

## 后台运行

前台运行的 Clash 会随终端退出而停止。后台运行让 Clash 脱离终端，关闭终端或断开 SSH 后继续运行，适合没有 systemd 或 sudo 权限的环境（例如容器）。

1. 完成前台运行部分的第 1 至 5 步，在临时目录中下载并验证新配置。这时旧的后台 Clash 还在运行，验证失败也不影响它。

2. 如果之前已在后台启动过 Clash，停止它，否则它占用的端口会在下一步被判定为已占用。

   ```bash
   kill "$(cat ~/clash/clash.pid)"
   rm -f ~/clash/clash.pid
   ```

3. 执行前台运行的第 6 步，再执行第 7 步中带 `-t` 的验证命令。

4. 用 `setsid -f` 在新会话中启动 Clash 并立即返回。新会话没有控制终端，终端退出时 Clash 不会收到 SIGHUP。输出写入日志，进程号写入 PID 文件。

   ```bash
   setsid -f ~/clash/<内核可执行文件> -f ~/clash/glados.yaml -d ~/clash \
       </dev/null >~/clash/clash.log 2>&1
   pgrep -n -f "$HOME/clash/glados.yaml" >~/clash/clash.pid
   ```

5. 确认进程在运行（`TT` 列为 `?` 表示已脱离终端），并查看日志。

   ```bash
   ps -o pid,tty,args -p "$(cat ~/clash/clash.pid)"
   tail -f ~/clash/clash.log
   ```

也可以通过统一入口一次完成：

```bash
export config_url='<订阅地址>'
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash bg
```

脚本在新配置验证通过后，才停止上一次 `bg` 启动的 Clash 并启动新的，所以重复执行相当于重启，并且会沿用原来的端口；新配置不能用时，旧的 Clash 照常运行。日志在每次启动时清空。停止方法见下文“停止”一节。

## systemd 服务运行

完成前台运行部分的第 1 至 6 步，并执行第 7 步中带 `-t` 的验证命令后：

1. 创建 `/etc/systemd/system/clash.service`，将 `<当前用户名>` 和 `<内核可执行文件>` 替换为实际值。

   ```ini
   [Unit]
   Description=Clash proxy service
   After=network-online.target
   Wants=network-online.target

   [Service]
   Type=simple
   User=<当前用户名>
   WorkingDirectory=/home/<当前用户名>/clash
   ExecStart=/home/<当前用户名>/clash/<内核可执行文件> -f /home/<当前用户名>/clash/glados.yaml -d /home/<当前用户名>/clash
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

## 停止

脚本以任何方式、用任何内核启动的 Clash，命令行都是 `<内核可执行文件> -f ~/clash/glados.yaml -d ~/clash`，按这一点就能找到它们。

1. 如果是 systemd 服务，用 systemctl 停止。直接结束进程没有用，`Restart=always` 会让 systemd 在 5 秒后重新启动它。服务仍然开机自启，不需要时再禁用。

   ```bash
   systemctl is-active clash.service
   sudo systemctl stop clash.service
   sudo systemctl disable clash.service
   ```

2. 停止后台运行的 Clash，以及在其他终端前台运行的 Clash（也可以在那个终端里按 `Ctrl+C`）。

   ```bash
   pgrep -af "$HOME/clash/glados.yaml -d $HOME/clash"
   pkill -f "$HOME/clash/glados.yaml -d $HOME/clash"
   rm -f ~/clash/clash.pid
   ```

3. 在执行过 `set-proxy` 的终端里清除代理变量，否则 curl、git、pip 等会连向已经关闭的端口。此时通过统一入口下载 `unset-proxy` 也会因为走代理而失败，所以直接执行：

   ```bash
   unset http_proxy https_proxy ftp_proxy all_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY ALL_PROXY no_proxy NO_PROXY
   ```

也可以通过统一入口一次完成第 1、2 步，不需要设置 `config_url`。服务正在运行时会用 sudo 停止它，但不会禁用开机自启：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash stop
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

这些变量导出后会一直留在当前 shell 中，之后再次执行时仍然生效。不再需要时用 `unset clash_port clash_controller_port` 取消。手动执行时，按前台运行第 6 步直接修改配置中的端口即可。

## 更新仓库中的 mihomo 和 geo 数据

在能访问 GitHub 的机器上、仓库根目录中执行。`version` 改成要使用的版本；建议选发布满两周的版本。

1. 下载 mihomo，并与 GitHub 记录的 sha256 核对。

   ```bash
   version=v1.19.33
   name=mihomo-linux-amd64-compatible-$version
   cd "$(mktemp -d)"
   curl -fsSLO "https://github.com/MetaCubeX/mihomo/releases/download/$version/$name.gz"
   curl -fsSL "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/$version" \
       | grep -A1 "\"name\": \"$name.gz\"" ; sha256sum "$name.gz"
   gzip -dc "$name.gz" > "$name" && chmod +x "$name" && "./$name" -v
   ```

   第二条命令的输出中有 `"digest": "sha256:..."`，应与 `sha256sum` 的结果一致。

2. 下载 geo 数据，并用发布页附带的校验文件核对。

   ```bash
   base=https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest
   for f in country.mmdb geosite.dat; do
       curl -fsSLO "$base/$f" && curl -fsSLO "$base/$f.sha256sum" && sha256sum -c "$f.sha256sum"
   done
   ```

3. 替换仓库中的文件：按 9 MB 切分 `.gz`，重新生成 `SHA256SUMS`。`clash.sh` 从 `SHA256SUMS` 读取文件名，不需要修改；只要把本文中的版本号和 geo 数据日期改成新的。

   ```bash
   repo=<仓库根目录>
   rm -f "$repo"/clash/mihomo/*
   split -b 9M -d -a 2 "$name.gz" "$repo/clash/mihomo/$name.gz.part-"
   cp country.mmdb "$repo/clash/mihomo/Country.mmdb"
   cp geosite.dat "$repo/clash/mihomo/GeoSite.dat"
   (cd "$repo/clash/mihomo" && sha256sum "$name".gz.part-* Country.mmdb GeoSite.dat) \
       > SHA256SUMS && sha256sum "$name" >> SHA256SUMS && mv SHA256SUMS "$repo/clash/mihomo/"
   ```
