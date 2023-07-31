sudo apt update
sudo apt install -y git

# 配置
git config --global user.email "819987540@qq.com"
git config --global user.name "whr81998754"
git config --global http.proxy "http://127.0.0.1:7890/"

# github ssh login
ssh-keygen
# 在github上添加该机器的公钥
