#!/usr/bin/env bash
# backup-vps.sh — 重装 / DD 前把目标机关键数据打包成 tarball。
#
# 跑在【跳板机】上，通过 SSH 进目标机、在目标机本地打包（之后可再拉回跳板机留档）。
#
# Usage:
#   export TARGET_HOST='x.x.x.x' TARGET_PORT=22 TARGET_PASS='***'
#   ./backup-vps.sh [tag]        # tag 默认日期；备份落在目标机 /root/vps-backup-<tag>/
#
# 注意：DATA_DIRS 相关的几条 tar 命令请按你这台机器的实际情况增删；
#       默认覆盖 sing-box + 1Panel 全家桶（1Panel 数据里已含各 Docker 应用）。
set -u
TAG="${1:-$(date +%Y%m%d)}"
TARGET_HOST="${TARGET_HOST:?set TARGET_HOST}"
TARGET_PORT="${TARGET_PORT:-22}"
TARGET_USER="${TARGET_USER:-root}"

export SSHPASS="${TARGET_PASS:?set TARGET_PASS (or switch this script to key auth)}"
sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -p "$TARGET_PORT" "$TARGET_USER@$TARGET_HOST" "TAG='$TAG' bash -s" <<'REMOTE'
set -u
DEST="/root/vps-backup-$TAG"
mkdir -p "$DEST"
echo "== sing-box (/etc/sing-box) =="
tar czf "$DEST/sing-box.tar.gz" -C /etc sing-box && echo ok-singbox
echo "== 1Panel full data (/opt/1panel, ~2GB, 1-3 min) =="
tar czf "$DEST/1panel.tar.gz" -C /opt 1panel && echo ok-1panel
echo "== extra dirs outside /opt (EDIT THIS LIST per machine) =="
tar czf "$DEST/lsky_pro.tar.gz" -C /data lsky_pro 2>/dev/null && echo ok-extra || echo skip-extra
echo "== metadata (what was running) =="
{
  echo "=== network ==="; ip -4 addr; ip route; grep -v '^#' /etc/resolv.conf
  echo "=== hostname ==="; hostname
  echo "=== system ==="; uname -a; lsblk; df -h
  echo "=== services running ==="; systemctl list-units --type=service --state=running --no-legend
  echo "=== docker ps ==="; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"
} > "$DEST/meta.txt" 2>&1
echo "== done =="
ls -lh "$DEST/"; df -h / | tail -1
REMOTE
echo "BACKUP-DONE rc=$?"
