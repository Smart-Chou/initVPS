# vps-recovery —— 海外 VPS「备份 → 重建 → 服务恢复 → 验证」工具链

一套实际跑通过的脚本集合，用于把一台**从本地直连不稳定**的海外 VPS
在重装（DD / 迁移）之后，把所有服务从备份里完整恢复回来，并做端到端验证。

## 适用场景

- VPS 要重装换系统（DD 镜像 / 迁移到新机），重建后要把原有服务一个个恢复回来
- 机器直连被干扰（SSH 时通时断 / 连上后被 reset），需要海外跳板机中转
- 服务跑在 1Panel / Docker Compose 上：数据散在 `apps/<app>/data`、`docker/compose/<name>/`、`/etc/sing-box` 等位置

## 三个角色

```
[操作端] ──ssh──▶ [跳板机 jump] ──ssh + key──▶ [目标机 target]
                      │
                      └─ 存备份 / 放任务脚本 / 跑诊断
```

| 角色 | 说明 |
|---|---|
| 操作端 | 你的电脑，负责指挥 |
| 跳板机 | 一台网络干净的海外机器（脚本大多在这里跑） |
| 目标机 | 要重建 / 恢复的 VPS |

## 一次性准备（在跳板机上）

1. 生成一把专用密钥，把公钥授权到目标机（cloud-init 注入，或写进目标机 `~/.ssh/authorized_keys`）。
2. 私钥放跳板机：

   ```bash
   scp ~/.ssh/mykey root@jump:/root/.vps_key
   ssh root@jump 'chmod 600 /root/.vps_key'
   ```

3. 跳板机依赖：`sshpass`（密码登录用）、`expect`、`python3`、`curl`。
   需要密码 SSH 时用 `exp/` 里的助手，密码只走环境变量，不落盘。

## 典型工作流

### 0. 探测可达性（诊断用，可选）

```bash
TARGET_IP=x.x.x.x ./probe-reachability.sh
```

在**两个位置**各跑一次（你的电脑 + 海外跳板机）。两边结果不一致时，问题多半在链路而不是机器。

### 1. 重装前：备份 + 盘点

```bash
# 跳板机：ssh 进目标机打包数据（打包结果落在目标机本地留档）
TARGET_HOST=x.x.x.x TARGET_PORT=22 TARGET_PASS='***' ./backup-vps.sh

# 从备份 tarball 里盘点"原来装过什么"（只读，不改备份）
BACKUP_DIR=/root/vps-backup-YYYYMMDD ./inventory-from-backup.sh
BACKUP_DIR=/root/vps-backup-YYYYMMDD ./inventory-from-backup-details.sh
```

### 2. 重装完成后：先看状态

```bash
# 经跳板中转，在目标机上跑状态盘点
TARGET=arch@x.x.x.x ./relay-run.sh state-check.sh

# 或从跳板机用密码直接看一眼
TARGET_HOST=x.x.x.x TARGET_PORT=22 TARGET_PASS='***' ./status-check.sh
```

### 3. 恢复服务

```bash
# 跳板机：从大备份里抽出服务子集，做成一个小恢复包
BACKUP_DIR=/root/vps-backup-YYYYMMDD ./stage-from-backup.sh

# 推给目标机并执行恢复任务
./relay-push.sh /root/vps-restore-bundle.tgz /tmp/vps-restore-bundle.tgz
./relay-run.sh install-singbox.sh
./relay-push.sh /root/sing-box-backup.tgz /tmp/sb-files.tgz
./relay-run.sh restore-singbox.sh
./relay-run.sh restore-compose-apps.sh

# 逐服务验证 + 端到端测试
./relay-run.sh verify-services.sh
SERVER_IP=x.x.x.x SERVER_CONFIG=/root/sberestore/sing-box/config.json ./test-hysteria2-e2e.sh
```

## 脚本清单

| 脚本 | 跑在哪 | 做什么 |
|---|---|---|
| `probe-reachability.sh` | 任意位置 | 端口 banner / SSH 握手探测：判断"机器挂了"还是"链路被干扰" |
| `backup-vps.sh` | 跳板机 | 重装前把关键数据打包（tar over ssh） |
| `inventory-from-backup.sh` | 跳板机 | 从备份里盘点装过哪些应用、各自大小 |
| `inventory-from-backup-details.sh` | 跳板机 | 深入看 compose 端口/挂载/env 键名、sing-box 配置结构 |
| `deep-inventory.sh` | 跳板机（ssh 到目标） | 目标机现状深挖：容器挂载、compose 路径、数据目录大小 |
| `relay-run.sh` | 跳板机 | 把任务脚本同步到目标机并以 sudo 执行（推荐统一入口） |
| `relay-push.sh` / `relay-pull.sh` | 跳板机 | 跳板机 ⇄ 目标机的文件互传 |
| `exp/ssh_run.exp` | 跳板机 | 密码 SSH 单命令执行（密码走 env，不落盘） |
| `exp/scp_push.exp` / `exp/scp_pull.exp` | 跳板机 | 密码 scp 上传 / 下载 |
| `status-check.sh` | 跳板机 | 密码登录快速看一眼系统状态 |
| `state-check.sh` | 目标机（经 relay） | 全量状态盘点：服务、监听、docker、防火墙、包管理器 |
| `stage-from-backup.sh` | 跳板机 | 从大备份抽服务子集 → 生成小恢复包 |
| `install-singbox.sh` | 目标机（经 relay） | 用包管理器安装 sing-box（Arch 示例） |
| `restore-singbox.sh` | 目标机（经 relay） | 放置配置/证书 → 校验 → 启动 |
| `restore-compose-apps.sh` | 目标机（经 relay） | 解包 → compose up 全部应用 |
| `verify-services.sh` | 目标机（经 relay） | 逐服务看日志 / 健康检查 / 监听端口 |
| `test-hysteria2-e2e.sh` | 任意有干净网络的机器 | 起真客户端走隧道，验证出口 IP |

## 踩坑备忘（都是真踩过的）

- **任务脚本别直接在跳板机上 `bash` 跑。** 跳板机和目标机可能是不同发行版，
  在跳板机上执行"目标机专用"脚本会得到莫名其妙的结果（在 Debian 上跑 Arch 脚本 → `pacman: command not found`）。
  统一走 `relay-run.sh`。
- **tar 打包注意别多嵌套一层。** `tar czf x.tgz -C dir .` 解出来就是 `dir` 的内容；
  如果 `dir` 里还留着一层同名子目录，目标机解包就会多套一层。打包前把目录结构摆平，比事后补救靠谱。
- **SQLite 系应用（n8n 等）恢复要 `db + -wal + -shm` 三件套。**
  只拷主文件会丢最近写入：WAL 里可能压着绝大部分未合并的数据（见过主文件 147KB、WAL 1.69MB 的情况）。
- **sing-box 的 systemd 单位用 `-C /etc/sing-box` 加载整个目录**：目录里所有 `*.json` 都会被读，
  改配置时别把 `config.json.bak` 留在原地，否则两份配置冲突起不来。
- **1Panel 的防火墙链（`1PANEL_BASIC*`）可能"存在但未挂载"**：INPUT 链没引用它们时防火墙实际是关的。
  在面板里启用防火墙之前，先确认放行清单（SSH 端口、业务端口），别把自己锁在外面。
- **"端口开着"可能是假象。** 有本地代理 / 中间层时，TCP 连接会被中间层接住，
  看起来端口全开。判断端口状态要在网络干净的一侧复测（这就是 `probe-reachability.sh` 的用途）。
- **expect 脚本匹配认证失败要收紧句式**：远程命令输出里普通的 `Permission denied` 会被误判成"认证失败"而提前退出。
  只匹配 `Permission denied, please try again` / `Permission denied (publickey)` 这类认证阶段专有句式。
