# Git 安装与配置步骤

`git_install_config.sh` 安装 Git，设置全局身份、HTTP 代理和编辑器，最后交互生成 SSH 密钥。

1. 更新软件索引并安装 Git。

   ```bash
   sudo apt update
   sudo apt install -y git
   ```

2. 设置提交使用的全局邮箱和用户名。

   ```bash
   git config --global user.email "819987540@qq.com"
   git config --global user.name "whr81998754"
   ```

3. 设置 Git HTTP 代理。脚本读取当前终端的 `http_proxy`；分步执行时将 `<代理地址>` 替换为实际地址，例如 `http://127.0.0.1:7890`。

   ```bash
   git config --global http.proxy '<代理地址>'
   ```

   不需要代理时跳过此步；清除已有配置可执行：

   ```bash
   git config --global --unset http.proxy
   ```

4. 将 Vim 设置为命令行 Git 编辑器。

   ```bash
   git config --global core.editor /usr/bin/vim
   ```

5. 按提示生成 SSH 密钥。

   ```bash
   ssh-keygen
   ```

6. 查看并将公钥添加到 GitHub 账户。

   ```bash
   cat ~/.ssh/id_*.pub
   ```

也可以通过统一入口一次完成。执行前需先设置 `http_proxy`，否则脚本会把 Git 代理配置成空值。

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) git
```
