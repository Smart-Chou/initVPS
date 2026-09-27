#!/usr/bin/env bash
# relay-pull.sh <src-on-target> <dest-on-jump> — 跑在【跳板机】上：从目标机取文件回来。
#
# 示例: ./relay-pull.sh /root/vps-backup-YYYYMMDD/sing-box.tar.gz /root/sing-box-backup.tgz
set -e
KEY="${TARGET_KEY:-/root/.vps_key}"
TARGET="${TARGET:-arch@203.0.113.10}"
if [ $# -lt 2 ]; then echo "usage: relay-pull.sh <src> <dest>"; exit 1; fi
scp -q -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 "$TARGET:$1" "$2"
echo "PULLED: $1 -> $2"
