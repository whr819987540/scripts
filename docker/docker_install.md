# Docker 安装步骤

`docker_install.sh` 在 Ubuntu 上添加 Docker 官方软件源，安装 Docker Engine，并启用服务。

1. 更新软件索引并安装添加软件源所需的工具。

   ```bash
   sudo apt update
   sudo apt install -y software-properties-common curl
   ```

2. 导入 Docker 软件源的 GPG 密钥。

   ```bash
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
   ```

3. 添加与当前 Ubuntu 版本对应的 Docker stable 软件源。

   ```bash
   sudo add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
   ```

4. 安装 Docker Engine、命令行工具和 containerd。

   ```bash
   sudo apt install -y docker-ce docker-ce-cli containerd.io
   ```

5. 启用、重启并检查 Docker 服务。

   ```bash
   sudo systemctl enable docker
   sudo systemctl restart docker
   sudo systemctl status docker
   ```

也可以通过统一入口一次完成：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) docker
```
