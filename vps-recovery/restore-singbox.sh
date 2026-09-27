#!/bin/bash
# restore-singbox.sh — 放置 sing-box 配置/证书 → 校验 → 启动。经 relay-run.sh 在目标机执行。
# 前置: relay-push.sh <sing-box-backup.tgz> /tmp/sb-files.tgz
# 包内结构（备份即原样）: sing-box/config.json、sing-box/cert/{fullchain,privkey}.pem
set -e
SB_TGZ="${SB_TGZ:-/tmp/sb-files.tgz}"
echo "== place config + certs =="
mkdir -p /etc/sing-box/cert /tmp/sbfiles && cd /tmp/sbfiles
tar xzf "$SB_TGZ"
cp -f sing-box/config.json        /etc/sing-box/config.json
cp -f sing-box/cert/fullchain.pem /etc/sing-box/cert/fullchain.pem
cp -f sing-box/cert/privkey.pem   /etc/sing-box/cert/privkey.pem
chmod 600 /etc/sing-box/cert/privkey.pem
chmod 644 /etc/sing-box/config.json /etc/sing-box/cert/fullchain.pem
ls -la /etc/sing-box /etc/sing-box/cert
echo "== validate config =="
sing-box check -c /etc/sing-box/config.json && echo CHECK-OK || echo CHECK-FAILED
echo "== enable + start =="
systemctl enable --now sing-box 2>&1 | tail -3
sleep 3
systemctl status sing-box --no-pager 2>&1 | head -12
echo "== listening（端口按你的配置核对） =="
ss -lntup | grep -E ':(443|8443)\b' || echo "(no matching listeners)"
echo "== recent log =="
journalctl -u sing-box -n 30 --no-pager 2>&1 | tail -30
echo "J03-DONE"
