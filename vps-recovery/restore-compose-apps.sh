#!/bin/bash
# restore-compose-apps.sh — 解包恢复包 → compose up 全部应用。经 relay-run.sh 在目标机执行。
# 依赖: relay-push.sh <bundle.tgz> /tmp/vps-restore-bundle.tgz
# bundle 结构（stage-from-backup.sh 产出）: 顶层直接是各应用目录（n8n/、beszel-agent/、drydock/…）
set -e
BUNDLE="${BUNDLE:-/tmp/vps-restore-bundle.tgz}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/1panel/docker/compose}"
EXT_NET="${EXT_NET:-1panel-network}"

echo "== compose plugin check =="
if ! docker compose version >/dev/null 2>&1; then
  echo "compose plugin missing -> installing..."
  command -v pacman >/dev/null && pacman -S --noconfirm docker-compose 2>&1 | tail -4
fi
docker compose version 2>&1 | head -2

echo "== extract bundle into $COMPOSE_DIR =="
mkdir -p "$COMPOSE_DIR"
tar xzf "$BUNDLE" -C "$COMPOSE_DIR"
ls -la "$COMPOSE_DIR"

echo "== ensure shared network '$EXT_NET' exists =="
docker network ls --format '{{.Name}}' | grep -qx "$EXT_NET" || docker network create "$EXT_NET"

echo "== compose up per project =="
for d in "$COMPOSE_DIR"/*/; do
  [ -f "$d/docker-compose.yml" ] || [ -f "$d/docker-compose.yaml" ] || continue
  echo "--- $d"
  (cd "$d" && docker compose up -d 2>&1 | tail -8)
done
sleep 10
echo "== docker ps =="
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo "J04-DONE"
