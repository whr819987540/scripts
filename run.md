# 统一入口执行步骤

`run.sh` 根据命令名称下载对应脚本，并将剩余参数传给该脚本。

## 直接使用

1. 查看可用命令。

   ```bash
   source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) help
   ```

2. 选择命令执行。例如，根据当前系统和 CPU 架构无交互安装 Miniconda：

   ```bash
   source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) miniconda
   ```

   需要修改当前终端环境的 `set-proxy` 和 `unset-proxy` 命令也必须使用 `source`。例如，使用默认地址设置代理：

   ```bash
   source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) set-proxy
   ```

   也可以通过参数或 `proxy` 环境变量指定地址：

   ```bash
   source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) \
       set-proxy 192.168.1.10:7890

   proxy=socks5://127.0.0.1:1080 \
   source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) set-proxy
   ```

3. 原有的 `silent` 参数仍可使用，行为与不传参数相同：

   ```bash
   source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) miniconda silent
   ```

4. 指定已有安装器的完整路径时会直接复用，不再下载：

   ```bash
   source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) \
       miniconda /data/installers/Miniconda3-latest-Linux-x86_64.sh
   ```

## 分步执行

1. 下载统一入口。

   ```bash
   curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh -o /tmp/scripts-run.sh
   ```

2. 查看帮助或执行所需命令。

   ```bash
   source /tmp/scripts-run.sh help
   source /tmp/scripts-run.sh miniconda /data/installers/Miniconda3-latest-Linux-x86_64.sh
   ```

3. 删除下载的入口脚本。

   ```bash
   rm -f /tmp/scripts-run.sh
   ```

入口内部下载的具体功能脚本使用临时文件，执行结束后会自动删除。
