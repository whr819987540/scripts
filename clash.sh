# 下载
config_url=""
cd ~
curl https://glados.rocks/tools/clash-linux.zip -o clash.zip
unzip clash.zip
cd clash
curl $config_url > glados.yaml
chmod a+x ./带版本号的可执行文件

# 运行
./clash-linux-amd64-v1.10.0 -f glados.yaml -d ./

# 运行测试
curl --proxy http://127.0.0.1:7890 https://www.google.com/
pip install graphviz torchviz --proxy http://127.0.0.1:7890

# 服务
export HOME=~
# sudo cat > filename <<EOF不行, 因为>也是操作符
sudo sh -c "
cat > /etc/systemd/system/clash.service <<EOF
[Unit]
Description=clash for windows

[Service]
Type=simple
ExecStart=$HOME/clash/clash-linux-amd64-v1.10.0 -f $HOME/clash/glados.yaml -d $HOME/clash
ExecReload=$HOME/clash/clash-linux-amd64-v1.10.0 -f $HOME/clash/glados.yaml -d $HOME/clash
RemainAfterExit=yes
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF
"
unset HOME
# 重载配置文件
sudo systemctl daemon-reload
# 启动
sudo systemctl start clash
# 检查是否启动成功
sudo systemctl status clash
# 开机自启
sudo systemctl enable clash

# 环境变量
echo "http_proxy=http://127.0.0.1:7890" >> ~/.bashrc
echo "https_proxy=http://127.0.0.1:7890" >> ~/.bashrc
source ~/.bashrc
echo $http_proxy
