# Miniconda 安装步骤

`miniconda_install.sh` 会根据当前操作系统和 CPU 架构选择最新版 Miniconda
安装器，并以批处理模式安装到 `~/miniconda3`。批处理模式会接受安装器协议并使用
预设选项，整个安装过程不需要用户输入。安装器默认保存在
`~/.cache/miniconda/`；该文件已存在且非空时会直接复用，不重复下载。安装完成后，
脚本会关闭 `base` 环境的自动激活。

支持的平台：

| 操作系统 | CPU 架构 |
| --- | --- |
| Linux | `x86_64`、`aarch64`、`ppc64le`、`s390x` |
| macOS | `x86_64`、`arm64` |

## 分步执行

1. 查看当前系统和 CPU 架构。

   ```bash
   uname -s
   uname -m
   ```

2. 根据输出设置安装器名称。以下示例适用于 Linux x86_64；其他平台请按上表替换
   `Linux` 和 `x86_64`。

   ```bash
   installer_name=Miniconda3-latest-Linux-x86_64.sh
   ```

3. 设置安装器保存路径并创建目录。

   ```bash
   installer_path="${HOME}/.cache/miniconda/${installer_name}"
   mkdir -p "$(dirname "${installer_path}")"
   ```

4. 仅在安装器不存在或为空时下载。脚本实际下载时会先写入 `.part` 文件，下载成功
   后再移动到指定位置，防止复用不完整的下载文件。

   ```bash
   if [[ ! -s "${installer_path}" ]]; then
       curl -fL --retry 3 \
           "https://repo.anaconda.com/miniconda/${installer_name}" \
           -o "${installer_path}.part"
       mv -f "${installer_path}.part" "${installer_path}"
   fi
   ```

   系统没有 `curl` 时可以使用 `wget`：

   ```bash
   if [[ ! -s "${installer_path}" ]]; then
       wget --tries=3 \
           "https://repo.anaconda.com/miniconda/${installer_name}" \
           -O "${installer_path}.part"
       mv -f "${installer_path}.part" "${installer_path}"
   fi
   ```

5. 使用批处理模式安装或更新 Miniconda。`-b` 表示接受安装器协议并使用默认选项，
   `-u` 允许更新已有安装，`-p` 指定安装目录。

   ```bash
   bash "${installer_path}" -b -u -p "${HOME}/miniconda3"
   ```

6. 关闭 `base` 环境的自动激活，避免打开新终端时自动进入该环境。

   ```bash
   "${HOME}/miniconda3/bin/conda" config --set auto_activate_base false
   ```

脚本会自动完成以上判断和操作：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) miniconda
```

原有的 `silent` 参数仍可使用，行为与不传参数相同：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) miniconda silent
```

要复用指定位置的安装器，将完整路径放在命令之后：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) \
    miniconda /data/installers/Miniconda3-latest-Linux-x86_64.sh
```

与 `silent` 兼容参数一起使用时，安装器路径是第二个参数：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) \
    miniconda silent /data/installers/Miniconda3-latest-Linux-x86_64.sh
```

安装完成后，在当前终端启用 Conda：

```bash
source ~/miniconda3/bin/activate
```
