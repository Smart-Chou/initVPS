#!/bin/bash
# verify-services.sh — 逐服务验收：日志 / 数据挂载 / 健康检查 / 监听端口。经 relay-run.sh 在目标机执行。
# 服务名和端口按你的实际栈改（本示例 = n8n + beszel-agent + drydock）。
echo "== n8n logs =="
docker logs n8n --tail 22 2>&1 | tail -22
echo ""
echo "== n8n data mounted =="
docker exec n8n sh -c 'ls -la /home/node/.n8n | head -14' 2>&1 | head -16
echo ""
echo "== n8n healthz =="
curl -s -m 6 http://127.0.0.1:35678/healthz; echo ""
echo "== beszel-agent logs =="
docker logs beszel-agent --tail 22 2>&1 | tail -22
echo ""
echo "== drydock-agent logs =="
docker logs drydock-agent --tail 28 2>&1 | tail -28
echo ""
echo "== drydock socket-proxy logs =="
docker logs drydock-socket-proxy --tail 6 2>&1 | tail -6
echo ""
echo "== final listeners =="
ss -lntu | grep -E ':(443|8443|35678|34300)\b' || true
echo ""
echo "== panel firewall chain (if any) =="
iptables -S 1PANEL_BASIC 2>/dev/null | head -24
echo "J05-DONE"
