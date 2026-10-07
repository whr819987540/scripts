# 设置代理步骤

`set_proxy.sh` 为当前 shell 设置常见的大小写代理环境变量。该脚本必须使用 `source` 执行，直接启动子进程无法修改当前终端环境。

代理地址的优先级为：命令参数、`proxy` 环境变量、默认值 `127.0.0.1:7890`。地址未包含协议时，脚本会自动添加 `http://`。

1. 确定代理地址。以下示例使用默认地址：

   ```bash
   proxy_address=http://127.0.0.1:7890
   ```

2. 设置小写代理变量。

   ```bash
   export http_proxy="$proxy_address"
   export https_proxy="$proxy_address"
   export ftp_proxy="$proxy_address"
   export all_proxy="$proxy_address"
   ```

3. 设置大写代理变量。

   ```bash
   export HTTP_PROXY="$proxy_address"
   export HTTPS_PROXY="$proxy_address"
   export FTP_PROXY="$proxy_address"
   export ALL_PROXY="$proxy_address"
   ```

4. 确认代理变量的值。

   ```bash
   env | sort | rg -i '^(http|https|ftp|all)_proxy='
   ```

也可以通过统一入口使用默认地址一次完成：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) set-proxy
```

通过命令参数指定代理：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) \
    set-proxy 192.168.1.10:7890
```

或通过 `proxy` 环境变量指定代理：

```bash
proxy=socks5://127.0.0.1:1080 \
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) set-proxy
```
