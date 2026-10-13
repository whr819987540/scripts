# Zabbix Agent 安装与配置步骤

`zabbix_agent.sh` 在 Ubuntu 20.04 上安装 Zabbix Agent 6.0，放行 TCP 10050 端口，并把服务端地址设置为 `192.168.124.101`。

1. 下载并安装 Zabbix 6.0 软件源配置包。

   ```bash
   wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-4+ubuntu20.04_all.deb
   sudo dpkg -i zabbix-release_6.0-4+ubuntu20.04_all.deb
   ```

2. 更新软件索引并安装 Agent。

   ```bash
   sudo apt update
   sudo apt install -y zabbix-agent
   ```

3. 重启 Agent、设置开机启动，并放行 TCP 10050 端口。

   ```bash
   sudo systemctl restart zabbix-agent
   sudo systemctl enable zabbix-agent
   sudo iptables -I INPUT -p tcp --dport 10050 -j ACCEPT
   ```

4. 配置被动和主动检查使用的服务端地址。需要其他地址时，将命令中的 `192.168.124.101` 替换为实际地址。

   ```bash
   sudo sed -i 's#Server=127.0.0.1#Server=192.168.124.101#g' \
       /etc/zabbix/zabbix_agentd.conf
   sudo sed -i 's#ServerActive=127.0.0.1#ServerActive=192.168.124.101#g' \
       /etc/zabbix/zabbix_agentd.conf
   ```

5. 允许服务端通过 `system.run[*]` 执行外部命令。

   ```bash
   sudo sed -i 's@# DenyKey=system\.run\[\*\]@AllowKey=system.run[*]@g' \
       /etc/zabbix/zabbix_agentd.conf
   ```

6. 重启服务使配置生效，并检查状态。

   ```bash
   sudo systemctl restart zabbix-agent
   sudo systemctl status --no-pager zabbix-agent
   ```

也可以通过统一入口一次完成：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) zabbix-agent
```
