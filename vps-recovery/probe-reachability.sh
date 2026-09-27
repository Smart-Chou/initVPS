#!/usr/bin/env bash
# probe-reachability.sh — 诊断「机器挂了」还是「链路被干扰」。
#
# 关键用法：在【两个视角】各跑一次（你的电脑 + 海外跳板机）。
# 两边结果不一致 → 问题在链路，不在机器。中间层接住 TCP 连接时，
# 会表现为"端口全开但拿不到 banner / 握手超时"。
#
# Usage:
#   TARGET_IP=x.x.x.x ./probe-reachability.sh
#   TARGET_IP=x.x.x.x SSH_PORT=22 PORTS="22 80 443" ./probe-reachability.sh
#   TARGET_IP=x.x.x.x HTTP_PORT=36038 HTTP_PATH=/login ./probe-reachability.sh
# 可选:
#   TARGET_IP6=...   # 顺便探测 IPv6
set -u
IP="${TARGET_IP:?set TARGET_IP}"
SSH_PORT="${SSH_PORT:-22}"
PORTS="${PORTS:-22 80 443}"
python3 - "$IP" "$SSH_PORT" "$PORTS" "${TARGET_IP6:-}" <<'PYEOF'
import socket, sys, time
host, ssh_port, ports, host6 = sys.argv[1], int(sys.argv[2]), sys.argv[3].split(), sys.argv[4]

print("=== [1] TCP + banner probe ===")
probe_ports = [ssh_port] + [int(p) for p in ports if int(p) != ssh_port]
for port in probe_ports:
    try:
        s = socket.create_connection((host, port), timeout=8)
        s.settimeout(6)
        try:
            d = s.recv(200)
            print(f"{host}:{port}: recv[{len(d)}]: {d[:120]!r}")
        except Exception as e:
            print(f"{host}:{port}: connected but recv-err: {e}  <- 中间层接住连接的典型特征")
        s.close()
    except Exception as e:
        print(f"{host}:{port}: connect-err: {e}")

print(f"--- manual SSH banner exchange on {ssh_port} ---")
try:
    s = socket.create_connection((host, ssh_port), timeout=8); s.settimeout(6)
    try:
        d = s.recv(120); print("pre-send:", d[:100])
    except Exception as e:
        print("pre-send err:", e)
    try:
        s.sendall(b"SSH-2.0-Probe\r\n")
        print("sent client banner")
        d = s.recv(300); print("post-send:", d[:200])
    except Exception as e:
        print("post-send err:", e)
    s.close()
except Exception as e:
    print("probe2 connect err:", e)

print("--- banner retry x3 (rate-limit check) ---")
for i in range(1, 4):
    try:
        s = socket.create_connection((host, ssh_port), timeout=8); s.settimeout(5)
        try:
            d = s.recv(120); print(f"attempt {i}: recv:", d[:100])
        except Exception as e: print(f"attempt {i}: recv-err:", e)
        s.close()
    except Exception as e: print(f"attempt {i}: connect-err:", e)
    time.sleep(3)

if host6:
    print("--- IPv6 attempt ---")
    try:
        s = socket.create_connection((host6, ssh_port), timeout=8); s.settimeout(6)
        try:
            d = s.recv(200); print("v6 recv:", d[:120])
        except Exception as e: print("v6 recv-err:", e)
        s.close()
    except Exception as e: print("v6 connect-err:", e)
PYEOF
echo ""
echo "=== [2] ssh verbose attempt ==="
timeout 18 ssh -vv -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=none -p "$SSH_PORT" "root@$IP" "echo SHOULD_NOT_REACH" 2>&1 | tail -16
echo ""
echo "=== [3] HTTP probe (optional) ==="
if [ -n "${HTTP_PORT:-}" ]; then
  curl -s -m 8 -o /dev/null -w "root: http=%{http_code} redirect=%{redirect_url}\n" "http://$IP:$HTTP_PORT/"
  curl -s -m 8 -D- -o /dev/null "http://$IP:$HTTP_PORT${HTTP_PATH:-/}" | head -14
else
  echo "(set HTTP_PORT=xxxx to probe an HTTP service)"
fi
echo "=== done ==="
