# 添加 SSH 授权公钥步骤

`add_authorized_key.sh` 将内置的 SSH 公钥添加到当前用户的 `~/.ssh/authorized_keys`。重复执行不会重复添加公钥，也不会覆盖文件中的其他授权项。

不要使用 `sudo` 执行整个脚本，否则公钥可能会被添加到 root 用户的主目录。需要信任公钥的用户应直接执行以下步骤。

1. 创建当前用户的 SSH 配置目录并设置安全权限。

   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   ```

2. 创建授权文件并设置安全权限。

   ```bash
   touch ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

3. 检查完整公钥是否已经存在；仅在不存在时追加。下面的命令也会处理原文件末尾缺少换行符的情况。

   ```bash
   grep -Fqx -- 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCz5k2gaUzhBZwKCTKfKzYVrzLLoKu2+7Bdcm5uLDZeOUfw2fD3zBsf/M8iHkax1u3Umr9qZgiskgU3vpSEg1Wh1zdiYjTZysEAVNk+9007m6zoEtv/eXnGXukIJLae3CBTNwpjy42ceTYorhVq2PkLkx2R4qfLWiKRSMrFd8utbVDzLa6Uyh75B0UjrSA9MeN3QCei+YuG+UnP2Vuf1g4caoDZjvLKgCE97HxrPxQAxLxvJxmUA+dvknyfQZMj4EUi3bc1UlD8zq78waGVssgt2+BJ6TKFaPGeqZG/9MBMMr4bAJhGyeQYCun34fFc+6kjyhW4+a03NpGKthLaiRV0rbZ3cm/+vYrFYV/4eUjztyHFp9j1kmRRTAOC/GfCsRUmWWA8bHaNITH3I8lfZcxRxG4vOzwnZubtA/epsCzB1rIuxynfRKkSGLQRd6KtmJeyhkxxuzT/eMSjOQpghRex7VMeSJzBgzOVz79ZLQynTX2fsR8IKCLzhTv430vNWN8= 819987540@qq.com' ~/.ssh/authorized_keys || {
       if [ -s ~/.ssh/authorized_keys ] && [ -n "$(tail -c 1 ~/.ssh/authorized_keys)" ]; then
           printf '\n' >> ~/.ssh/authorized_keys
       fi
       printf '%s\n' 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCz5k2gaUzhBZwKCTKfKzYVrzLLoKu2+7Bdcm5uLDZeOUfw2fD3zBsf/M8iHkax1u3Umr9qZgiskgU3vpSEg1Wh1zdiYjTZysEAVNk+9007m6zoEtv/eXnGXukIJLae3CBTNwpjy42ceTYorhVq2PkLkx2R4qfLWiKRSMrFd8utbVDzLa6Uyh75B0UjrSA9MeN3QCei+YuG+UnP2Vuf1g4caoDZjvLKgCE97HxrPxQAxLxvJxmUA+dvknyfQZMj4EUi3bc1UlD8zq78waGVssgt2+BJ6TKFaPGeqZG/9MBMMr4bAJhGyeQYCun34fFc+6kjyhW4+a03NpGKthLaiRV0rbZ3cm/+vYrFYV/4eUjztyHFp9j1kmRRTAOC/GfCsRUmWWA8bHaNITH3I8lfZcxRxG4vOzwnZubtA/epsCzB1rIuxynfRKkSGLQRd6KtmJeyhkxxuzT/eMSjOQpghRex7VMeSJzBgzOVz79ZLQynTX2fsR8IKCLzhTv430vNWN8= 819987540@qq.com' >> ~/.ssh/authorized_keys
   }
   ```

4. 确认权限和公钥记录。

   ```bash
   stat -c '%a %n' ~/.ssh ~/.ssh/authorized_keys
   grep -F '819987540@qq.com' ~/.ssh/authorized_keys
   ```

也可以通过统一入口一次完成：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) add-authorized-key
```
