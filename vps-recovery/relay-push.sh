#!/usr/bin/env bash
# relay-push.sh <src-on-jump> <dest-on-target> — 跑在【跳板机】上：把文件传给目标机。
#
# 示例: ./relay-push.sh /root/vps-restore-bundle.tgz /tmp/vps-restore-bundle.tgz
set -e
KEY="${TARGET_KEY:-/root/.vps_key}"
TARGET="${TARGET:-arch@203.0.113.10}"
if [ $# -lt 2 ]; then echo "usage: relay-push.sh <src> <dest>"; exit 1; fi
scp -q -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 "$1" "$TARGET:$2"
echo "PUSHED: $1 -> $2"
