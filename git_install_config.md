# Git 安装与配置步骤

`git_install_config.sh` 按需安装 Git 和 OpenBSD netcat，配置全局 Git 身份及代理，复用或生成 SSH 公钥，并让 GitHub SSH 连接通过 HTTP 代理访问 `ssh.github.com:443`。

请以要配置的用户身份运行，不要整体加 `sudo`，否则配置的是 root 的 Git 和 SSH。缺少 Git 或 `nc` 时，脚本以 root 身份运行安装命令：当前已是 root（例如容器内）时直接执行，否则通过 `sudo` 执行；已经安装所需命令时不需要 root 权限。

1. 设置代理地址。未设置时，脚本默认使用 `http://127.0.0.1:7890`。

   ```bash
   export http_proxy='http://127.0.0.1:7890'
   export https_proxy="$http_proxy"
   ```

2. 检查 Git，仅在命令不存在时安装。

   ```bash
   if ! command -v git >/dev/null 2>&1; then
       sudo apt-get update
       sudo apt-get install -y git
   fi
   ```

3. 检查 SSH 代理依赖，仅在 `nc` 不存在时安装。

   ```bash
   if ! command -v nc >/dev/null 2>&1; then
       sudo apt-get update
       sudo apt-get install -y netcat-openbsd
   fi
   ```

   以 root 身份运行时（例如容器内没有 `sudo`）去掉命令前的 `sudo`。

4. 设置提交身份、HTTP/HTTPS 代理和编辑器。

   ```bash
   git config --global user.email '819987540@qq.com'
   git config --global user.name 'whr81998754'
   git config --global http.proxy "$http_proxy"
   git config --global https.proxy "${https_proxy:-$http_proxy}"
   git config --global core.editor /usr/bin/vim
   ```

5. 创建 SSH 目录并设置权限。

   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   ```

6. 检查公钥。只在 `~/.ssh` 中不存在任何 `*.pub` 文件时生成 Ed25519 密钥；已有公钥时跳过此命令。

   ```bash
   ls ~/.ssh/*.pub
   ssh-keygen -t ed25519 -C '819987540@qq.com'
   ```

7. 在 `~/.ssh/config` 中加入 GitHub 配置。脚本通过带标记的管理区块重复更新该配置，并保留文件中其他 SSH 主机设置。

   ```sshconfig
   # BEGIN scripts: github proxy
   Host github.com
       HostName ssh.github.com
       Port 443
       User git
       ProxyCommand nc -X connect -x 127.0.0.1:7890 %h %p
   # END scripts: github proxy
   ```

   然后设置配置文件权限：

   ```bash
   chmod 600 ~/.ssh/config
   ```

8. 将脚本输出的公钥添加到 GitHub 的 **Settings > SSH and GPG keys**，再测试连接。

   ```bash
   ssh -T git@github.com
   ```

也可以通过统一入口一次完成：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) git
```
