#!/usr/bin/env bash
# status-check.sh — 密码 SSH 快速检查一轮目标机状态（重装前后都能用）。
#
# Usage: TARGET_HOST=x.x.x.x TARGET_PORT=22 TARGET_PASS='***' ./status-check.sh
set -u
export SSHPASS="${TARGET_PASS:?set TARGET_PASS}"
sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=12 -p "${TARGET_PORT:-22}" "${TARGET_USER:-root}@${TARGET_HOST:?set TARGET_HOST}" '
echo "== connected =="
echo "-- os-release --"; head -3 /etc/os-release 2>/dev/null
echo "-- cmdline --"; head -c 220 /proc/cmdline; echo
echo "-- uptime --"; uptime | head -1
echo "-- root fs --"; df -h / | tail -1
echo "-- sshd --"; systemctl is-active sshd 2>/dev/null || echo unknown
echo "-- done --"
' 2>&1
echo "STATUS rc=$?"
