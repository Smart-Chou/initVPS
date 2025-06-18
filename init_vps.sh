#!/bin/bash

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本！"
    exit 1
fi

# 设置非交互式环境，避免弹出选项框
export DEBIAN_FRONTEND=noninteractive

# 更新系统
echo "正在更新系统..."
apt-get update && apt-get -y upgrade
echo "系统更新完成！"

# 安装Docker
read -p "是否安装Docker？(y/n): " install_docker
if [ "$install_docker" = "y" ] || [ "$install_docker" = "Y" ]; then
    echo "正在安装Docker..."
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
    echo "Docker安装完成！"

    # 验证Docker安装
    docker --version
fi

# 安装Docker Compose
read -p "是否安装Docker Compose？(y/n): " install_compose
if [ "$install_compose" = "y" ] || [ "$install_compose" = "Y" ]; then
    echo "正在安装Docker Compose..."
    LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    echo "Docker Compose安装完成！"

    # 验证Docker Compose安装
    docker-compose --version
fi

# 设置服务器时间
read -p "是否设置服务器时区？(y/n): " set_timezone
if [ "$set_timezone" = "y" ] || [ "$set_timezone" = "Y" ]; then
    echo "当前时区：$(timedatectl | grep "Time zone")"
    read -p "请输入时区（例如：Asia/Shanghai）: " timezone
    timedatectl set-timezone "$timezone"
    echo "时区已设置为：$timezone"
fi

# 同步时间
echo "正在同步时间..."
apt-get install -y ntp
systemctl enable ntp
systemctl start ntp
echo "时间同步完成！"

echo "服务器初始化完成！"
