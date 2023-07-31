username="whr"2
pubkey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCz5k2gaUzhBZwKCTKfKzYVrzLLoKu2+7Bdcm5uLDZeOUfw2fD3zBsf/M8iHkax1u3Umr9qZgiskgU3vpSEg1Wh1zdiYjTZysEAVNk+9007m6zoEtv/eXnGXukIJLae3CBTNwpjy42ceTYorhVq2PkLkx2R4qfLWiKRSMrFd8utbVDzLa6Uyh75B0UjrSA9MeN3QCei+YuG+UnP2Vuf1g4caoDZjvLKgCE97HxrPxQAxLxvJxmUA+dvknyfQZMj4EUi3bc1UlD8zq78waGVssgt2+BJ6TKFaPGeqZG/9MBMMr4bAJhGyeQYCun34fFc+6kjyhW4+a03NpGKthLaiRV0rbZ3cm/+vYrFYV/4eUjztyHFp9j1kmRRTAOC/GfCsRUmWWA8bHaNITH3I8lfZcxRxG4vOzwnZubtA/epsCzB1rIuxynfRKkSGLQRd6KtmJeyhkxxuzT/eMSjOQpghRex7VMeSJzBgzOVz79ZLQynTX2fsR8IKCLzhTv430vNWN8= 819987540@qq.com"

# 添加用户
sudo useradd $username
sudo passwd $username

# 用户组
sudo usermod -aG user,docker,sudo $username

# 切换用户
su whr
# ssh公钥(免密登录)
if [ ! -d "/path/to/directory" ]; then
    mkdir ~/.ssh
fi
echo $pubkey >> ~/.ssh/authorized_keys