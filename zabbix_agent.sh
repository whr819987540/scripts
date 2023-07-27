# 安装
sudo wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-4+ubuntu20.04_all.deb
sudo dpkg -i zabbix-release_6.0-4+ubuntu20.04_all.deb
sudo apt update
sudo apt install -y zabbix-agent
sudo systemctl restart zabbix-agent
sudo systemctl enable zabbix-agent
sudo iptables -I INPUT -p tcp --dport 10050 -j ACCEPT

# 配置server地址
export SERVERIP=192.168.124.101
sudo sed -i "s#Server=127.0.0.1#Server=${SERVERIP}#g"  /etc/zabbix/zabbix_agentd.conf
sudo sed -i "s#ServerActive=127.0.0.1#ServerActive=${SERVERIP}#g"  /etc/zabbix/zabbix_agentd.conf
unset SERVERIP

# 配置外部命令可执行
sudo sed -i "s@# DenyKey=system\.run\[\*\]@AllowKey=system\.run\[\*\]@g" /etc/zabbix/zabbix_agentd.conf

sudo systemctl restart zabbix-agent