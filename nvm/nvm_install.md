# NVM 安装步骤

`nvm_install.sh` 会从 GitHub 的 latest release 地址解析最新稳定版 nvm，安装或更新
nvm，然后安装最新 stable 版 Node.js，并将 `stable` 设置为默认 Node.js 版本。

## 分步执行

1. 确认系统已安装 `curl`。

   ```bash
   command -v curl
   ```

2. 查询 GitHub 当前标记的最新稳定版 nvm。

   ```bash
   release_url="$(curl -fsSLI --retry 3 -o /dev/null -w '%{url_effective}' \
       https://github.com/nvm-sh/nvm/releases/latest)"
   nvm_version="${release_url##*/}"
   printf '%s\n' "${nvm_version}"
   ```

   输出应为 `v主版本.次版本.补丁版本`，例如 `v0.40.3`。脚本会检查该格式，无法
   确定可靠版本时停止安装。

3. 下载该版本的官方安装脚本并执行。

   ```bash
   curl -fsSL --retry 3 \
       "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" \
       -o /tmp/nvm-install.sh
   bash /tmp/nvm-install.sh
   rm -f /tmp/nvm-install.sh
   ```

4. 在当前 shell 中加载 nvm，并检查安装版本。

   ```bash
   export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
   source "$NVM_DIR/nvm.sh"
   nvm --version
   ```

5. 查看可用版本，安装最新 stable 版 Node.js。

   ```bash
   nvm ls-remote
   nvm install stable
   ```

6. 将 stable 设为默认版本，并检查结果。

   ```bash
   nvm alias default stable
   nvm ls
   node --version
   ```

也可以通过统一入口一次完成：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) nvm
```

安装完成后，新终端会根据 nvm 安装器写入的 shell 配置自动加载 nvm。需要在当前
终端立即使用时，执行第 4 步的命令。
