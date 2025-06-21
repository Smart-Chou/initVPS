#!/bin/bash

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 sudo 或以 root 用户运行此脚本！"
    exit 1
fi

# 检查 ufw 是否安装
if ! command -v ufw &> /dev/null; then
    echo "ufw 未安装，正在安装..."
    apt update && apt install -y ufw
fi

# 定义要屏蔽的 IP 段（IPv4 和 IPv6）
IP_BLOCKS=(
    "66.132.159.0/24"
    "162.142.125.0/24"
    "167.94.138.0/24"
    "167.94.145.0/24"
    "167.94.146.0/24"
    "167.248.133.0/24"
    "199.45.154.0/24"
    "199.45.155.0/24"
    "206.168.34.0/24"
    "206.168.35.0/24"
    "66.132.148.0/24"
    "206.168.32.0/24"
    "66.132.153.0/24"
    "2602:80d:1000:b0cc:e::/80"
    "2620:96:e000:b0cc:e::/80"
    "2602:80d:1003::/112"
    "2602:80d:1004::/112"
)

# 添加屏蔽规则
echo "正在添加屏蔽规则..."
for block in "${IP_BLOCKS[@]}"; do
    ufw deny from "$block"
    echo "已屏蔽: $block"
done

# 启用 ufw（如果未启用）
if ! ufw status | grep -q "Status: active"; then
    echo "启用 ufw..."
    ufw --force enable
fi

# 显示当前规则
echo "当前 ufw 规则："
ufw status numbered

echo "所有 IP 段已成功屏蔽！"
