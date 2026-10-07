# Clash 安装与运行步骤

`clash.sh` 下载 Clash 和订阅配置，自动避开已占用的监听端口，然后以前台进程或 systemd 服务运行。

执行前需要准备 Clash 订阅地址，并确保已安装 `curl`、`ss` 和 `unzip`。

## 前台运行

1. 创建安装目录。

   ```bash
   mkdir -p ~/clash
   ```

2. 下载并解压 Clash。仓库当前目录已有 `clash-linux.zip` 时，可跳过下载。

   ```bash
   curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/clash-linux.zip \
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

   如果端口已被占用，将配置中的该端口依次加一，直到找到空闲端口。脚本执行时会自动完成这一步。

5. 找到 Clash 可执行文件并添加执行权限。

   ```bash
   find ~/clash -maxdepth 2 -type f -name 'clash-linux-amd64-*' -print
   chmod a+x ~/clash/<Clash可执行文件>
   ```

6. 验证配置，然后以前台方式启动。

   ```bash
   ~/clash/<Clash可执行文件> -t -f ~/clash/glados.yaml -d ~/clash
   ~/clash/<Clash可执行文件> -f ~/clash/glados.yaml -d ~/clash
   ```

也可以通过统一入口一次完成：

```bash
config_url='<订阅地址>' \
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash
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
config_url='<订阅地址>' \
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) clash serve
```
