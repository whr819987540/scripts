# 取消代理步骤

`unset_proxy.sh` 清除当前 shell 中常见的大小写代理环境变量。该脚本必须使用 `source` 执行，直接启动子进程无法修改当前终端环境。

1. 清除小写代理变量。

   ```bash
   unset http_proxy https_proxy ftp_proxy all_proxy
   ```

2. 清除大写代理变量。

   ```bash
   unset HTTP_PROXY HTTPS_PROXY FTP_PROXY ALL_PROXY
   ```

3. 确认这些变量已没有值。

   ```bash
   env | rg -i '^(http|https|ftp|all)_proxy='
   ```

   命令没有输出即表示清除完成。

也可以通过统一入口一次完成：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) unset-proxy
```
