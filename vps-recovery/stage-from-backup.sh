#!/usr/bin/env bash
# stage-from-backup.sh — 从大备份里抽出"要恢复的服务"子集，摆平目录结构，打成小恢复包。
#
# 跑在【跳板机】上。目录结构在打包前就摆平（避免目标机解包多一层——真踩过这个坑）。
#
# Usage:  BACKUP_DIR=/root/vps-backup-20260927 ./stage-from-backup.sh
# 输出:   $BUNDLE（默认 /root/vps-restore-bundle.tgz）→ 用 relay-push.sh 推给目标机
#         /root/sberestore/  —— sing-box 备份的解包镜像（给端到端测试用）
set -e
BACKUP_DIR="${BACKUP_DIR:-/root/vps-backup}"
STAGE="${STAGE:-/root/restore-stage}"
BUNDLE="${BUNDLE:-/root/vps-restore-bundle.tgz}"

rm -rf "$STAGE"; mkdir -p "$STAGE/extract" "$STAGE/out"
cd "$STAGE"

echo "== extracting subset from 1panel.tar.gz =="
# 成员清单按需改：本示例恢复 n8n（在 apps 下）+ beszel-agent / drydock（在 docker/compose 下）
tar xzf "$BACKUP_DIR/1panel.tar.gz" -C extract \
  '1panel/apps/n8n/n8n/data' '1panel/apps/n8n/n8n/.env' '1panel/apps/n8n/n8n/docker-compose.yml' \
  '1panel/docker/compose/beszel-agent' '1panel/docker/compose/drydock'

echo "== staging final layout (flat — no extra nesting) =="
mkdir -p out/n8n
cp -a extract/1panel/apps/n8n/n8n/data out/n8n/data
cp -a extract/1panel/apps/n8n/n8n/.env out/n8n/.env
cp -a extract/1panel/apps/n8n/n8n/docker-compose.yml out/n8n/docker-compose.yml
cp -a extract/1panel/docker/compose/beszel-agent out/beszel-agent
cp -a extract/1panel/docker/compose/drydock out/drydock

echo "== n8n .env（重点核对占位符，如 HOST_IP） =="
python3 - <<'PY'
for ln in open('out/n8n/.env', errors='replace'):
    ln = ln.rstrip('\n')
    if ln.strip():
        print('  ', ln[:120])
PY

echo "== tree =="
find out -maxdepth 2 | head -30
du -sh out/n8n/data

echo "== make bundle =="
tar czf "$BUNDLE" -C "$STAGE/out" .
ls -l "$BUNDLE"

echo "== sing-box: unpack to a mirror dir for the e2e test =="
rm -rf /root/sberestore && mkdir -p /root/sberestore && cd /root/sberestore
tar xzf "$BACKUP_DIR/sing-box.tar.gz"
find . -maxdepth 3 | head -25

echo "STAGE-DONE"
