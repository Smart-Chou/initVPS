#!/bin/bash
# install-singbox.sh — 用包管理器安装 sing-box（Arch / extra 仓库示例）。经 relay-run.sh 在目标机执行。
# 其他发行版：把 pacman 行换成 apt/dnf + 官方源即可；再确认一下 unit 文件位置。
set -e
echo "== pacman install sing-box =="
pacman -S --noconfirm sing-box 2>&1 | tail -10
echo "== unit file =="
systemctl cat sing-box.service 2>/dev/null | head -25 || echo "(no unit)"
echo "== /etc/sing-box now =="
ls -la /etc/sing-box/ 2>/dev/null || echo "(no dir yet)"
echo "== firewall INPUT chain =="
nft list chain ip filter INPUT 2>/dev/null | head -20 || echo "(no INPUT chain / nft table)"
echo "== iptables fallback =="
iptables -S 2>/dev/null | head -12 || echo "(iptables missing or empty)"
echo "J02-DONE"
