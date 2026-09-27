#!/usr/bin/env bash
# test-hysteria2-e2e.sh — hysteria2 端到端测试：在本机起一个真 sing-box 客户端走隧道，
# 验证出口 IP == 服务器 IP。
#
# 跑在一台网络干净的机器上（比如跳板机），别在被墙的机器上跑。
# 从服务器端 config.json 读 hysteria2 的端口和密码，不改服务器任何东西。
#
# Usage:
#   SERVER_IP=x.x.x.x SERVER_CONFIG=/root/sberestore/sing-box/config.json ./test-hysteria2-e2e.sh
# 可选:
#   SB_VERSION=1.14.2   WORKDIR=/root/hytest   SERVER_NAME=localhost
set -e
SERVER_IP="${SERVER_IP:?set SERVER_IP}"
SERVER_CONFIG="${SERVER_CONFIG:?path to the server-side sing-box config.json}"
SB_VERSION="${SB_VERSION:-1.14.2}"
WORKDIR="${WORKDIR:-/root/hytest}"
mkdir -p "$WORKDIR" && cd "$WORKDIR"

if [ ! -x ./sing-box ]; then
  echo "== download sing-box client =="
  curl -sL -o sb.tgz "https://github.com/SagerNet/sing-box/releases/download/v${SB_VERSION}/sing-box-${SB_VERSION}-linux-amd64.tar.gz"
  tar xzf sb.tgz
  find . -name sing-box -type f | head -1 | xargs -I{} cp {} ./sing-box
  chmod +x ./sing-box
fi
./sing-box version 2>&1 | head -2

python3 - "$SERVER_CONFIG" "$SERVER_IP" "${SERVER_NAME:-localhost}" <<'PY'
import json, sys
cfg_path, server_ip, sni = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(cfg_path))
pw = None; port = 8443
for ib in d.get('inbounds', []):
    if ib.get('type') == 'hysteria2':
        pw = ib['users'][0].get('password')
        port = ib.get('listen_port', port)
client = {
    "inbounds":  [{"type": "socks", "listen": "127.0.0.1", "listen_port": 10999}],
    "outbounds": [{"type": "hysteria2", "server": server_ip, "server_port": port,
                   "password": pw, "tls": {"enabled": True, "insecure": True, "server_name": sni}}],
}
json.dump(client, open('client.json', 'w'), indent=1)
print("client config written; hy2 port:", port, "password_len:", len(pw or ''))
PY

nohup ./sing-box run -c client.json > "$WORKDIR/run.log" 2>&1 &
sleep 5
echo "== exit ip via hy2 tunnel (expect: $SERVER_IP) =="
curl -s -m 12 --socks5-hostname 127.0.0.1:10999 https://api.ipify.org || echo "(curl ipify failed)"
echo ""
curl -s -m 12 --socks5-hostname 127.0.0.1:10999 https://ifconfig.me/ip || echo "(curl ifconfig failed)"
echo ""
echo "== client log tail =="
tail -14 "$WORKDIR/run.log"
pkill -f 'sing-box run -c client.json' 2>/dev/null || true
echo "HY2TEST-DONE"
