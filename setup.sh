#!/bin/bash

# 参数定义
DOMAIN=""
INSTALL_DOCKER=false
USE_ALIYUN_MIRROR=false
INSTALL_CERTBOT_NGINX=false
INSTALL_GO=false
GO_VERSION="latest"
INSTALL_NVM=false
NODE_VERSION=""
INSTALL_CONDA=false
CONDA_ENV_NAME=""
PYTHON_VERSION=""
SSH_PUBKEY=""

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            DOMAIN="$2"
            INSTALL_CERTBOT_NGINX=true
            shift 2
            ;;
        --install-docker)
            INSTALL_DOCKER=true
            shift
            ;;
        --use-aliyun)
            USE_ALIYUN_MIRROR=true
            shift
            ;;
        --install-go)
            INSTALL_GO=true
            if [[ "$2" =~ ^[0-9] ]]; then
                GO_VERSION="$2"
                shift 2
            else
                shift
            fi
            ;;
        --install-nvm)
            INSTALL_NVM=true
            if [[ "$2" =~ ^[0-9] ]]; then
                NODE_VERSION="$2"
                shift 2
            else
                shift
            fi
            ;;
        --install-conda)
            INSTALL_CONDA=true
            if [[ "$2" != --* ]] && [[ -n "$2" ]]; then
                CONDA_ENV_NAME="$2"
                if [[ "$3" =~ ^[0-9] ]]; then
                    PYTHON_VERSION="$3"
                    shift 3
                else
                    shift 2
                fi
            else
                shift
            fi
            ;;
        --ssh-pubkey)
            SSH_PUBKEY="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 检查/创建 ubuntu 用户
if ! id -u ubuntu &>/dev/null; then
    echo "创建 ubuntu 用户..."
    sudo useradd -m -s /bin/bash ubuntu
    echo "设置 ubuntu 用户免密码 sudo..."
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu-nopasswd
    sudo chmod 440 /etc/sudoers.d/ubuntu-nopasswd
fi

# 配置 SSH 公钥登录
if [[ -n "$SSH_PUBKEY" ]]; then
    echo "配置 SSH 公钥登录..."
    sudo mkdir -p /home/ubuntu/.ssh
    echo "$SSH_PUBKEY" | sudo tee /home/ubuntu/.ssh/authorized_keys
    sudo chown -R ubuntu:ubuntu /home/ubuntu/.ssh
    sudo chmod 700 /home/ubuntu/.ssh
    sudo chmod 600 /home/ubuntu/.ssh/authorized_keys
    
    echo "配置 SSH 安全设置..."
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sudo sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
    
    sudo systemctl restart sshd
fi

# 安装 Docker
if [[ "$INSTALL_DOCKER" == true ]]; then
    echo "安装 Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    if [[ "$USE_ALIYUN_MIRROR" == true ]]; then
        echo "使用阿里云镜像安装 Docker..."
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    else
        echo "使用官方源安装 Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    echo "配置 Docker 用户组..."
    sudo usermod -aG docker ubuntu
    newgrp docker
    
    # 配置 Docker 镜像加速
    if [[ "$USE_ALIYUN_MIRROR" == true ]]; then
        echo "配置 Docker 镜像加速器..."
        sudo mkdir -p /etc/docker
        sudo tee /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.mybacc.com",
    "https://dytt.online",
    "https://lispy.org",
    "https://docker.xiaogenban1993.com",
    "https://docker.yomansunter.com",
    "https://aicarbon.xyz",
    "https://666860.xyz",
    "https://docker.zhai.cm",
    "https://a.ussh.net",
    "https://hub.littlediary.cn",
    "https://hub.rat.dev",
    "https://docker.m.daocloud.io"
  ]
}
EOF
        sudo systemctl daemon-reload
        sudo systemctl restart docker
    fi
fi

# 安装 Go
if [[ "$INSTALL_GO" == true ]]; then
    echo "安装 Go 语言..."
    
    if [[ "$GO_VERSION" == "latest" ]]; then
        echo "获取最新 Go 版本..."
        GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1)
    else
        GO_VERSION="go${GO_VERSION}"
    fi
    
    echo "安装版本: $GO_VERSION"
    
    if ! wget "https://mirrors.aliyun.com/golang/${GO_VERSION}.linux-amd64.tar.gz"; then
        echo "从阿里云下载失败，尝试备用镜像..."
        wget "https://mirrors.ustc.edu.cn/golang/${GO_VERSION}.linux-amd64.tar.gz" || \
        wget "https://mirrors.cloud.tencent.com/golang/${GO_VERSION}.linux-amd64.tar.gz"
    fi
    
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "${GO_VERSION}.linux-amd64.tar.gz"
    rm "${GO_VERSION}.linux-amd64.tar.gz"
    
    echo "export PATH=\$PATH:/usr/local/go/bin" | sudo tee /etc/profile.d/go.sh
    echo "export GOPROXY=https://goproxy.cn,direct" | sudo tee -a /etc/profile.d/go.sh
    source /etc/profile.d/go.sh
    
    echo "Go 版本信息:"
    /usr/local/go/bin/go version
fi

# 安装 NVM 和 Node
if [[ "$INSTALL_NVM" == true ]]; then
    echo "安装 NVM 和 Node.js..."
    
    # 根据 USE_ALIYUN_MIRROR 决定是否使用国内镜像
    if [[ "$USE_ALIYUN_MIRROR" == true ]]; then
        echo "使用国内镜像下载 NVM..."
        NVM_INSTALL_URL="https://gitee.com/mirrors/nvm/raw/v0.39.5/install.sh"
        # 备用镜像列表
        BACKUP_MIRRORS=(
            "https://ghproxy.com/https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh"
            "https://mirror.ghproxy.com/https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh"
            "https://hub.fastgit.xyz/nvm-sh/nvm/raw/v0.39.5/install.sh"
        )
    else
        echo "通过 GitHub 下载 NVM..."
        NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh"
    fi
    
    # 尝试安装 NVM
    if ! sudo -u ubuntu bash -c "curl -o- $NVM_INSTALL_URL | bash"; then
        echo "主要镜像下载失败，尝试备用镜像..."
        if [[ "$USE_ALIYUN_MIRROR" == true ]]; then
            # 尝试备用镜像
            for MIRROR in "${BACKUP_MIRRORS[@]}"; do
                echo "尝试镜像: $MIRROR"
                if sudo -u ubuntu bash -c "curl -o- $MIRROR | bash"; then
                    echo "NVM 安装成功！"
                    break
                fi
            done
        else
            echo "GitHub 源下载失败，尝试国内镜像..."
            sudo -u ubuntu bash -c 'curl -o- https://gitee.com/mirrors/nvm/raw/v0.39.5/install.sh | bash'
        fi
    fi

    # 确保 NVM 目录存在
    export NVM_DIR="/home/ubuntu/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # 设置 Node 镜像（仅在使用国内镜像时）
    if [[ "$USE_ALIYUN_MIRROR" == true ]]; then
        echo "配置国内 Node 镜像..."
        sudo -u ubuntu bash -c 'echo -e "\n# Node 镜像配置" >> ~/.bashrc'
        sudo -u ubuntu bash -c 'echo "export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node" >> ~/.bashrc'
        sudo -u ubuntu bash -c 'echo "export NVM_IOJS_ORG_MIRROR=https://npmmirror.com/mirrors/iojs" >> ~/.bashrc'
        sudo -u ubuntu bash -c 'echo "export NVM_GITHUB_MIRROR=https://ghproxy.com" >> ~/.bashrc'
        
        # 立即生效
        export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node
        export NVM_IOJS_ORG_MIRROR=https://npmmirror.com/mirrors/iojs
        export NVM_GITHUB_MIRROR=https://ghproxy.com
    fi
    
    # 配置 npm 镜像（仅在使用国内镜像时）
    if [[ "$USE_ALIYUN_MIRROR" == true ]]; then
        mkdir -p /home/ubuntu/.npm-global
        sudo chown -R ubuntu:ubuntu /home/ubuntu/.npm-global
        
        sudo -u ubuntu bash -c 'source ~/.nvm/nvm.sh && npm config set registry https://registry.npmmirror.com'
        sudo -u ubuntu bash -c 'source ~/.nvm/nvm.sh && npm config set prefix "~/.npm-global"'
        
        # 添加 npm 全局路径到 PATH
        sudo -u ubuntu bash -c 'echo -e "\n# NPM 全局路径配置" >> ~/.bashrc'
        sudo -u ubuntu bash -c 'echo "export PATH=~/.npm-global/bin:\$PATH" >> ~/.bashrc'
    fi
    
    # 安装指定版本或 LTS 版 Node.js
    if [[ -n "$NODE_VERSION" ]]; then
        echo "安装 Node.js $NODE_VERSION..."
        if [[ "$USE_ALIYUN_MIRROR" == true ]]; then
            sudo -u ubuntu bash -c 'source ~/.nvm/nvm.sh && NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node nvm install '"$NODE_VERSION"' && nvm alias default '"$NODE_VERSION"
        else
            sudo -u ubuntu bash -c 'source ~/.nvm/nvm.sh && nvm install '"$NODE_VERSION"' && nvm alias default '"$NODE_VERSION"
        fi
    else
        echo "安装最新 LTS 版 Node.js..."
        if [[ "$USE_ALIYUN_MIRROR" == true ]]; then
            sudo -u ubuntu bash -c 'source ~/.nvm/nvm.sh && NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node nvm install --lts && nvm alias default lts/*'
        else
            sudo -u ubuntu bash -c 'source ~/.nvm/nvm.sh && nvm install --lts && nvm alias default lts/*'
        fi
    fi
    
    # 确保环境变量持久化
    echo "持久化 NVM 环境变量..."
    {
        echo -e '\n# NVM 初始化'
        echo 'export NVM_DIR="$HOME/.nvm"'
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
    } | sudo -u ubuntu tee -a /home/ubuntu/.bashrc > /dev/null
    
    # 验证安装
    echo "Node.js 版本信息:"
    sudo -u ubuntu bash -c 'source ~/.nvm/nvm.sh && node --version && npm --version'
    
    # 当前 shell 立即生效
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
fi

# 安装 Conda
if [[ "$INSTALL_CONDA" == true ]]; then
    echo "安装 Miniconda..."
    wget https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p /home/ubuntu/miniconda
    rm miniconda.sh
    
    # 初始化 Conda
    /home/ubuntu/miniconda/bin/conda init bash
    source /home/ubuntu/.bashrc
    
    # 创建指定环境
    if [[ -n "$CONDA_ENV_NAME" ]]; then
        echo "创建 Conda 环境: $CONDA_ENV_NAME"
        if [[ -n "$PYTHON_VERSION" ]]; then
            /home/ubuntu/miniconda/bin/conda create -n "$CONDA_ENV_NAME" python="$PYTHON_VERSION" -y
        else
            /home/ubuntu/miniconda/bin/conda create -n "$CONDA_ENV_NAME" -y
        fi
        
        echo "Conda 环境列表:"
        /home/ubuntu/miniconda/bin/conda env list
    fi
fi

# 安装 Certbot 和 Nginx
if [[ "$INSTALL_CERTBOT_NGINX" == true && -n "$DOMAIN" ]]; then
    echo "安装 Nginx 和 Certbot..."
    sudo apt-get update
    sudo apt-get install -y nginx certbot python3-certbot-nginx
    
    echo "配置 Nginx 默认站点..."
    sudo tee /etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    location / {
        return 200 'Hello World';
        add_header Content-Type text/plain;
    }
}
EOF
    sudo systemctl restart nginx
    
    echo "申请 Let's Encrypt 证书..."
    sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN
    
    echo "设置证书自动续订..."
    (sudo crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet") | sudo crontab -
fi

echo "所有配置完成！"
