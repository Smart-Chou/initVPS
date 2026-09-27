#!/usr/bin/env bash
# inventory-from-backup.sh — 从备份 tarball 盘点"原来装过什么"（只读，不改动备份）。
#
# 跑在【跳板机】上、备份目录下执行。
#
# Usage: BACKUP_DIR=/root/vps-backup-YYYYMMDD ./inventory-from-backup.sh
# 注: LIST_CACHE 缓存一份 tar 列表，避免反复遍历大 tarball。
set -u
BACKUP_DIR="${BACKUP_DIR:-/root/vps-backup}"
LIST_CACHE="${LIST_CACHE:-/tmp/vps-backup-list.txt}"
cd "$BACKUP_DIR" || { echo "no such dir: $BACKUP_DIR"; exit 1; }

echo "===== [0] backup dir ====="
ls -la
echo
echo "===== [1] META.TXT (what was running) ====="
cat meta.txt 2>/dev/null
echo
echo "===== [2] top-level dirs under 1panel/ ====="
[ -s "$LIST_CACHE" ] || tar tzvf 1panel.tar.gz > "$LIST_CACHE" 2>/dev/null
echo "listing lines: $(wc -l < "$LIST_CACHE")"
grep -oE "1panel/[^/]+/" "$LIST_CACHE" | sort | uniq -c | sort -rn | head -40
echo
echo "===== [3] apps present ====="
grep -oE "1panel/apps/[^/]+/" "$LIST_CACHE" | sort -u
echo
echo "===== [4] compose file paths ====="
grep -E "/docker-compose\.ya?ml$" "$LIST_CACHE" | awk '{print $NF}'
echo
echo "===== [5] per-app size ====="
python3 - "$LIST_CACHE" <<'PYEOF'
import collections, sys
size=collections.Counter(); cnt=collections.Counter()
for line in open(sys.argv[1], errors='replace'):
    parts=line.split()
    if not parts: continue
    path=parts[-1]; seg=path.split('/')
    if len(seg)>=3 and seg[0]=='1panel' and seg[1]=='apps':
        a=seg[2]; cnt[a]+=1
        try: size[a]+=int(parts[2])
        except: pass
for a in sorted(size,key=lambda x:-size[x]):
    print("%-28s %10.1f MB (%d files)"%(a,size[a]/1048576,cnt[a]))
PYEOF
echo
echo "===== [6] other tarballs ====="
for f in sing-box.tar.gz lsky_pro.tar.gz 1panel-v1-backups.tar.gz; do
  if [ -f "$f" ]; then
    echo "--- $f"
    tar tzvf "$f" | head -25
    echo "entries: $(tar tzf "$f" | wc -l)"
    echo
  fi
done
echo "DONE $(date '+%H:%M:%S')"
