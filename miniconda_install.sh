# https://docs.conda.io/en/latest/miniconda.html#installing
wget https://repo.anaconda.com/miniconda/Miniconda3-py38_23.5.2-0-Linux-x86_64.sh
chmod a+x Miniconda3-py38_23.5.2-0-Linux-x86_64.sh
./Miniconda3-py38_23.5.2-0-Linux-x86_64.sh
conda init bash
conda update -n base -c defaults conda
conda config --show
conda config --set proxy_servers.http $http_proxy
conda config --set proxy_servers.https $http_proxy
