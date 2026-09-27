#!/usr/bin/env bash
# relay-run.sh <job-file> — 跑在【跳板机】上：把任务脚本同步到目标机，以 sudo 执行，输出回传。
#
# 这是所有"要在目标机上做的事"的统一入口。
# 不要直接在跳板机上 bash 目标机专用脚本——跳板机和目标机可能是不同发行版。
#
# 目标机连接参数（改默认值或覆盖环境变量）:
#   TARGET=arch@x.x.x.x     目标机 user@ip
#   TARGET_KEY=/root/.vps_key   授权到目标机的私钥
set -e
KEY="${TARGET_KEY:-/root/.vps_key}"
TARGET="${TARGET:-arch@203.0.113.10}"
JOB="${1:?usage: relay-run.sh <job-file>}"
B="$(basename "$JOB")"
scp -q -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 "$JOB" "$TARGET:/tmp/$B"
ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o ServerAliveInterval=20 "$TARGET" "chmod +x /tmp/$B && sudo /tmp/$B"
