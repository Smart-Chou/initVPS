#!/usr/bin/env bash
# inventory-from-backup-details.sh — 更细一层的备份盘点：
# 把 compose 配置抽出来看端口/挂载/env 键名、各目录体量、sing-box 入站结构。
#
# 跑在【跳板机】上、备份目录下执行。先跑一次 inventory-from-backup.sh 生成 LIST_CACHE。
#
# Usage: BACKUP_DIR=/root/vps-backup-YYYYMMDD ./inventory-from-backup-details.sh
set -u
BACKUP_DIR="${BACKUP_DIR:-/root/vps-backup}"
LIST_CACHE="${LIST_CACHE:-/tmp/vps-backup-list.txt}"
WORK="${WORK:-/tmp/vps-inv}"
cd "$BACKUP_DIR" || { echo "no such dir: $BACKUP_DIR"; exit 1; }
[ -s "$LIST_CACHE" ] || tar tzvf 1panel.tar.gz > "$LIST_CACHE" 2>/dev/null

echo "===== [A] extract compose files ====="
rm -rf "$WORK" && mkdir -p "$WORK/compose"
tar xzf 1panel.tar.gz -C "$WORK/compose" --wildcards \
  '1panel/apps/*/*/docker-compose.y*ml' \
  '1panel/apps/*/*/*/docker-compose.y*ml' \
  '1panel/docker/compose/*/docker-compose.y*ml' 2>/dev/null
find "$WORK/compose" -type f | sort
echo
echo "===== [B] compose summary (images/ports/volumes/env-keys — 不看值) ====="
python3 - "$WORK/compose" <<'PYEOF'
import re, glob, sys
files = sorted(glob.glob(sys.argv[1] + '/**/docker-compose.y*ml', recursive=True))
for f in files:
    rel = f.split(sys.argv[1], 1)[-1].lstrip('/')
    print('### ' + rel)
    txt = open(f, errors='replace').read()
    for ln in txt.splitlines():
        s = ln.strip()
        m = re.match(r'^- ([A-Z][A-Z0-9_]{2,})=', s)
        if m: print('    env-key:', m.group(1)); continue
        m = re.match(r'^([A-Z][A-Z0-9_]{2,}):', s)
        if m: print('    env-key:', m.group(1)); continue
        if re.match(r'^(image|container_name):', s) or re.match(r'^- "?\d+:\d+"?$', s) or re.match(r'^- [/.]', s):
            print('   ', s[:120])
    print()
PYEOF
echo
echo "===== [C] docker/ breakdown (top dirs) ====="
python3 - "$LIST_CACHE" <<'PYEOF'
import collections, sys
size=collections.Counter(); cnt=collections.Counter()
for line in open(sys.argv[1], errors='replace'):
    p=line.split()
    if not p: continue
    path=p[-1]; seg=path.split('/')
    if len(seg)>=3 and seg[0]=='1panel' and seg[1]=='docker':
        key='/'.join(seg[2:4])
        cnt[key]+=1
        try: size[key]+=int(p[2])
        except: pass
for k in sorted(size,key=lambda x:-size[x])[:30]:
    print("%-44s %10.2f MB (%d files)"%(k,size[k]/1048576,cnt[k]))
PYEOF
echo
echo "===== [D] 关注应用的数据文件（示例: n8n / uptime-kuma，按需改） ====="
grep -E "1panel/apps/(uptime-kuma|n8n)/" "$LIST_CACHE" | awk '{n=$NF; sub(/^1panel\/apps\//,"",n); print n, $3}' | head -60
echo
echo "===== [E] sing-box config shape ====="
mkdir -p "$WORK/sbx" && tar xzf sing-box.tar.gz -C "$WORK/sbx" 2>/dev/null
python3 - "$WORK/sbx" <<'PYEOF'
import json, sys, glob
paths = glob.glob(sys.argv[1] + '/sing-box/config.json')
if not paths:
    print('(no sing-box/config.json found)')
else:
    d = json.load(open(paths[0]))
    print("top keys:", sorted(d.keys()))
    for i in d.get('inbounds', []):
        print("inbound:", i.get('type'), i.get('listen'), i.get('listen_port'), "tag=", i.get('tag'))
    print("outbound types:", [(o.get('type'), o.get('tag')) for o in d.get('outbounds', [])])
PYEOF
echo "DONE2 $(date '+%H:%M:%S')"
