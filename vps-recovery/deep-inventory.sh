#!/usr/bin/env bash
# deep-inventory.sh — 目标机现状深挖：容器挂载、compose 路径、数据目录大小、监听服务。
#
# 跑在【跳板机】上，通过密码 SSH 进目标机执行（要等实机操作也可以丢给 relay-run.sh）。
#
# Usage: TARGET_HOST=x.x.x.x TARGET_PORT=22 TARGET_PASS='***' ./deep-inventory.sh
set -u
export SSHPASS="${TARGET_PASS:?set TARGET_PASS}"
sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=12 -p "${TARGET_PORT:-22}" "${TARGET_USER:-root}@${TARGET_HOST:?set TARGET_HOST}" 'bash -s' <<'REMOTE'
echo "== container mounts (all) =="
for c in $(docker ps -aq 2>/dev/null); do
  docker inspect $c --format '{{.Name}} | {{range .Mounts}}{{.Source}}=>{{.Destination}}({{.Type}}) {{end}}' 2>/dev/null
done
echo ""
echo "== compose labels (working_dir / config_files) =="
for c in $(docker ps -aq 2>/dev/null); do
  docker inspect $c --format '{{.Name}} wd={{index .Config.Labels "com.docker.compose.project.working_dir"}} cf={{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null
done
echo ""
echo "== /opt tree =="
ls /opt/
du -sh /opt/* 2>/dev/null | sort -h | tail -8
echo ""
echo "== candidate data dirs =="
du -sh /root/.n8n /opt/n8n* /srv/* /var/lib/n8n 2>/dev/null | head -10
echo ""
echo "== find compose files =="
find / -maxdepth 4 \( -name "docker-compose.y*ml" -o -name "compose.y*ml" \) -not -path "/proc/*" -not -path "/sys/*" -not -path "/var/lib/docker/*" -not -path "/snap/*" 2>/dev/null | head -12
echo ""
echo "== panel db + settings size =="
ls -la /opt/1panel/db/ 2>/dev/null | head -6
du -sh /opt/1panel/db 2>/dev/null
echo ""
echo "== running extra units (non-system) =="
systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | awk '{print $1}' | grep -vE "systemd|dbus|ssh|getty|cron|logind|journal|networkd|resolved|udev|polkit|rsyslog|docker|containerd|console" | head -18
echo ""
echo "== sing-box files =="
find /etc/sing-box -type f | head -10
REMOTE
echo "DEEP-DONE rc=$?"
