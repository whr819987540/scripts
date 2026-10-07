# 新用户创建步骤

`new_user.sh` 创建固定用户名 `whr`，设置密码和用户组，并写入脚本内置的 SSH 公钥。执行前确认系统存在 `user`、`docker` 和 `sudo` 用户组。

1. 创建用户并交互设置密码。

   ```bash
   sudo useradd whr
   sudo passwd whr
   ```

2. 将用户加入 `user`、`docker` 和 `sudo` 组。

   ```bash
   sudo usermod -aG user,docker,sudo whr
   ```

3. 切换到新用户，并进入其主目录。

   ```bash
   su - whr
   ```

4. 创建 SSH 配置目录并设置安全权限。

   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   ```

5. 将 `new_user.sh` 第 2 行的公钥内容追加到授权文件，然后设置权限。

   ```bash
   printf '%s\n' '<SSH公钥>' >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

也可以通过统一入口执行原脚本：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) new-user
```

注意：原脚本中的 `su whr` 会启动子 shell，退出该 shell 后才继续执行后续命令；分步执行时应确认第 4、5 步确实以 `whr` 用户执行。
