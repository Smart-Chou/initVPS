#!/bin/bash
# state-check.sh — 目标机全量状态盘点（经 relay-run.sh 在目标机执行）。
# 输出：身份 / 负载 / 磁盘 / 失败单元 / 关键服务 / 监听端口 / docker / 防火墙 / sing-box / 包管理器。
# 注: pacman 两行按发行版换成 apt/dnf；服务名与目录按你的实际栈调整。
echo "=== identity ==="
hostnamectl 2>/dev/null | head -6; id; uname -r
echo "=== uptime/load ==="; uptime
echo "=== mem ==="; free -h
echo "=== disk ==="; df -h / /tmp /var/tmp 2>/dev/null | head -6
echo "=== failed units ==="; systemctl --failed --no-pager --no-legend | head
echo "=== key services ==="; for s in sshd 1panel-core 1panel-agent docker containerd; do printf "%s: " $s; systemctl is-active $s 2>/dev/null; done
echo "=== listening ==="; ss -tlnp | head -30
echo "=== docker ps -a ==="; docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null | head -12
echo "=== compose dirs ==="; ls -la /opt/1panel/docker/compose/ 2>/dev/null
echo "=== apps dir ==="; ls /opt/1panel/apps/ 2>/dev/null
echo "=== firewall (nft) ==="; nft list ruleset 2>/dev/null | head -50
echo "=== /etc/sing-box ==="; ls -la /etc/sing-box/ 2>/dev/null || echo "(no sing-box dir)"
echo "=== sing-box pkg ==="; pacman -Si sing-box 2>/dev/null | head -6 || echo "(not in sync repos)"
echo "=== pacman recent ==="; grep -E 'installed|upgraded' /var/log/pacman.log 2>/dev/null | tail -6
echo "DONE-J01"
