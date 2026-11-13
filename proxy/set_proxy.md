# 设置代理步骤

`set_proxy.sh` 为当前 shell 设置常见的大小写代理环境变量。该脚本必须使用 `source` 执行，直接启动子进程无法修改当前终端环境。

代理地址的优先级为：命令参数、`proxy` 环境变量、默认值 `127.0.0.1:7890`。地址未包含协议时，脚本会自动添加 `http://`。

脚本同时设置 `no_proxy` 和 `NO_PROXY`，列出不走代理的地址：本机（`localhost`、`127.0.0.1`、`::1`）和私有网段（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）。这样代理在另一台机器上时，访问本机服务也不会被转发过去。当前 shell 中已有的 `no_proxy`/`NO_PROXY` 条目会合并保留，不会重复。网段写法（CIDR）只有 curl 7.86 及以上、Python requests/pip、Go 程序等支持；更早的 curl 和 wget 会忽略这些条目，访问内网 IP 时仍然走代理，本机地址不受影响。

这些变量只对当前 shell 及其启动的程序生效（curl、wget、pip、git 等会读取它们），其他终端不受影响。执行时脚本会打印代理地址及其来源、是否补全了协议、保留的已有 `no_proxy` 条目、设置的每个变量，以及撤销用的 `unset-proxy` 命令，例如：

```text
Proxy address: 127.0.0.1:7890 (default)
No scheme given; using http://127.0.0.1:7890
Exported in the current shell:
  http_proxy=http://127.0.0.1:7890
  https_proxy=http://127.0.0.1:7890
  ftp_proxy=http://127.0.0.1:7890
  all_proxy=http://127.0.0.1:7890
  HTTP_PROXY=http://127.0.0.1:7890
  HTTPS_PROXY=http://127.0.0.1:7890
  FTP_PROXY=http://127.0.0.1:7890
  ALL_PROXY=http://127.0.0.1:7890
  no_proxy=localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
  NO_PROXY=localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
Programs started from this shell that read these variables (curl, wget,
pip, git, ...) now use the proxy, except for the hosts in no_proxy.
Other terminals are not affected.
Undo: source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) unset-proxy
```

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

4. 设置不走代理的地址。已有 `no_proxy` 时，把其中的条目用逗号追加到末尾。

   ```bash
   no_proxy_list=localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
   export no_proxy="$no_proxy_list"
   export NO_PROXY="$no_proxy_list"
   ```

5. 确认代理变量的值。

   ```bash
   env | sort | rg -i '^(http|https|ftp|all|no)_proxy='
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
