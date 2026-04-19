#!/usr/bin/env bash
set -Eeuo pipefail

#######################################
# RustDesk Server Installer (Refactored)
# Target: Debian / Ubuntu with systemd
# Features:
# - Non-interactive
# - Safer defaults
# - Optional domain / IP
# - Optional version pin
# - Optional auto-detect public IP
# - Optional install path / user
#######################################

SCRIPT_NAME="$(basename "$0")"

#######################################
# Defaults
#######################################
INSTALL_DIR="/opt/rustdesk"
LOG_DIR="/var/log/rustdesk"
SERVICE_USER=""
SERVICE_GROUP=""
USE_SUDO="auto"
SERVER_HOST=""
RESOLVE_IP="false"
RUSTDESK_VERSION=""
GITHUB_API="https://api.github.com"
RUSTDESK_REPO="rustdesk/rustdesk-server"
ARCH=""
OS_ID=""
OS_VERSION=""
PKG_MANAGER=""
SKIP_START="false"
FORCE="false"

#######################################
# Helpers
#######################################
log() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

error() {
  echo "[ERROR] $*" >&2
}

die() {
  error "$*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

cleanup_on_error() {
  error "脚本执行失败，行号: ${1:-unknown}"
}
trap 'cleanup_on_error $LINENO' ERR

usage() {
  cat <<'EOF'
用法:
  install-rustdesk-server.sh [options]

选项:
  --host <ip-or-domain>       指定客户端连接地址（推荐：域名）
  --resolve-ip                自动探测当前公网 IP
  --version <tag>             指定 RustDesk Server 版本，例如 1.1.14
  --install-dir <path>        安装目录，默认 /opt/rustdesk
  --log-dir <path>            日志目录，默认 /var/log/rustdesk
  --user <username>           指定运行服务的用户，默认当前用户
  --group <groupname>         指定运行服务的组，默认用户主组
  --no-sudo                   不使用 sudo
  --skip-start                仅安装，不启动服务
  --force                     覆盖已有文件/重复安装时继续
  -h, --help                  显示帮助

示例:
  sudo bash install-rustdesk-server.sh --host rustdesk.example.com
  sudo bash install-rustdesk-server.sh --resolve-ip
  sudo bash install-rustdesk-server.sh --host 1.2.3.4 --version 1.1.14
EOF
}

#######################################
# Argument parsing
#######################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        shift
        [[ $# -gt 0 ]] || die "--host 缺少参数"
        SERVER_HOST="$1"
        ;;
      --resolve-ip)
        RESOLVE_IP="true"
        ;;
      --version)
        shift
        [[ $# -gt 0 ]] || die "--version 缺少参数"
        RUSTDESK_VERSION="$1"
        ;;
      --install-dir)
        shift
        [[ $# -gt 0 ]] || die "--install-dir 缺少参数"
        INSTALL_DIR="$1"
        ;;
      --log-dir)
        shift
        [[ $# -gt 0 ]] || die "--log-dir 缺少参数"
        LOG_DIR="$1"
        ;;
      --user)
        shift
        [[ $# -gt 0 ]] || die "--user 缺少参数"
        SERVICE_USER="$1"
        ;;
      --group)
        shift
        [[ $# -gt 0 ]] || die "--group 缺少参数"
        SERVICE_GROUP="$1"
        ;;
      --no-sudo)
        USE_SUDO="false"
        ;;
      --skip-start)
        SKIP_START="true"
        ;;
      --force)
        FORCE="true"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "未知参数: $1"
        ;;
    esac
    shift
  done
}

#######################################
# Sudo handling
#######################################
init_sudo() {
  if [[ "$USE_SUDO" == "false" ]]; then
    SUDO=""
    return
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=""
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    die "当前不是 root，且系统没有 sudo。请使用 root 执行或安装 sudo。"
  fi
}

#######################################
# Detect OS
#######################################
detect_os() {
  [[ -f /etc/os-release ]] || die "无法识别系统：缺少 /etc/os-release"

  # shellcheck disable=SC1091
  . /etc/os-release

  OS_ID="${ID:-}"
  OS_VERSION="${VERSION_ID:-}"

  case "$OS_ID" in
    ubuntu|debian)
      PKG_MANAGER="apt"
      ;;
    *)
      die "当前仅支持 Debian / Ubuntu，检测到系统: ${OS_ID:-unknown}"
      ;;
  esac

  log "检测到系统: $OS_ID $OS_VERSION"
}

#######################################
# Detect architecture
#######################################
detect_arch() {
  local machine
  machine="$(uname -m)"

  case "$machine" in
    x86_64|amd64)
      ARCH="amd64"
      ;;
    aarch64|arm64)
      ARCH="arm64v8"
      ;;
    armv7l)
      ARCH="armv7"
      ;;
    *)
      die "不支持的架构: $machine"
      ;;
  esac

  log "检测到架构: $machine -> $ARCH"
}

#######################################
# Validate host
#######################################
is_valid_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    [[ "$o" -ge 0 && "$o" -le 255 ]] || return 1
  done
  return 0
}

is_valid_hostname() {
  local host="$1"
  [[ ${#host} -le 253 ]] || return 1
  [[ "$host" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]
}

resolve_public_ip() {
  local ip=""
  ip="$(curl -fsSL https://api.ipify.org || true)"
  [[ -n "$ip" ]] || ip="$(curl -fsSL https://ifconfig.me || true)"
  [[ -n "$ip" ]] || die "公网 IP 自动探测失败，请改用 --host 手动指定"

  is_valid_ipv4 "$ip" || die "自动探测到的公网 IP 非法: $ip"
  SERVER_HOST="$ip"
}

validate_host_choice() {
  if [[ "$RESOLVE_IP" == "true" && -n "$SERVER_HOST" ]]; then
    die "--host 与 --resolve-ip 不能同时使用"
  fi

  if [[ "$RESOLVE_IP" == "true" ]]; then
    resolve_public_ip
  fi

  [[ -n "$SERVER_HOST" ]] || die "必须指定 --host 或 --resolve-ip"

  if is_valid_ipv4 "$SERVER_HOST"; then
    log "使用 IPv4 地址: $SERVER_HOST"
    return
  fi

  if is_valid_hostname "$SERVER_HOST"; then
    log "使用域名: $SERVER_HOST"
    return
  fi

  die "无效的 host: $SERVER_HOST"
}

#######################################
# Init service user/group
#######################################
init_service_identity() {
  if [[ -z "$SERVICE_USER" ]]; then
    SERVICE_USER="$(id -un)"
  fi

  if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    die "指定用户不存在: $SERVICE_USER"
  fi

  if [[ -z "$SERVICE_GROUP" ]]; then
    SERVICE_GROUP="$(id -gn "$SERVICE_USER")"
  fi

  getent group "$SERVICE_GROUP" >/dev/null 2>&1 || die "指定组不存在: $SERVICE_GROUP"

  log "服务运行用户: $SERVICE_USER:$SERVICE_GROUP"
}

#######################################
# Install dependencies
#######################################
install_dependencies() {
  log "安装依赖..."
  case "$PKG_MANAGER" in
    apt)
      $SUDO apt-get update
      DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y \
        curl wget unzip tar ca-certificates systemd
      ;;
    *)
      die "未实现的包管理器: $PKG_MANAGER"
      ;;
  esac
}

#######################################
# Resolve latest version if not pinned
#######################################
resolve_version() {
  if [[ -n "$RUSTDESK_VERSION" ]]; then
    log "使用指定版本: $RUSTDESK_VERSION"
    return
  fi

  log "获取最新 RustDesk Server 版本..."
  RUSTDESK_VERSION="$(
    curl -fsSL "${GITHUB_API}/repos/${RUSTDESK_REPO}/releases/latest" \
      | grep '"tag_name"' \
      | sed -E 's/.*"([^"]+)".*/\1/'
  )"

  [[ -n "$RUSTDESK_VERSION" ]] || die "获取最新版本失败"
  log "检测到最新版本: $RUSTDESK_VERSION"
}

#######################################
# Download URL
#######################################
get_download_filename() {
  case "$ARCH" in
    amd64)
      echo "rustdesk-server-linux-amd64.zip"
      ;;
    arm64v8)
      echo "rustdesk-server-linux-arm64v8.zip"
      ;;
    armv7)
      echo "rustdesk-server-linux-armv7.zip"
      ;;
    *)
      die "未知 ARCH: $ARCH"
      ;;
  esac
}

get_extract_dir() {
  case "$ARCH" in
    amd64)
      echo "amd64"
      ;;
    arm64v8)
      echo "arm64v8"
      ;;
    armv7)
      echo "armv7"
      ;;
    *)
      die "未知 ARCH: $ARCH"
      ;;
  esac
}

#######################################
# Prepare directories
#######################################
prepare_dirs() {
  log "准备目录..."
  $SUDO mkdir -p "$INSTALL_DIR"
  $SUDO mkdir -p "$LOG_DIR"
  $SUDO chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR" "$LOG_DIR"
}

#######################################
# Download and install RustDesk Server
#######################################
install_rustdesk_server() {
  local filename extract_dir tmpdir url

  filename="$(get_download_filename)"
  extract_dir="$(get_extract_dir)"
  url="https://github.com/${RUSTDESK_REPO}/releases/download/${RUSTDESK_VERSION}/${filename}"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  log "下载 RustDesk Server: $url"
  curl -fL "$url" -o "${tmpdir}/${filename}"

  log "解压安装包..."
  unzip -q "${tmpdir}/${filename}" -d "$tmpdir"

  [[ -d "${tmpdir}/${extract_dir}" ]] || die "解压目录不存在: ${extract_dir}"

  if [[ -e "${INSTALL_DIR}/hbbs" || -e "${INSTALL_DIR}/hbbr" ]]; then
    if [[ "$FORCE" != "true" ]]; then
      die "检测到已有安装文件，请使用 --force 继续覆盖"
    fi
    warn "检测到已有安装，执行覆盖"
  fi

  log "复制文件到 ${INSTALL_DIR}"
  $SUDO cp -f "${tmpdir}/${extract_dir}/hbbs" "${INSTALL_DIR}/hbbs"
  $SUDO cp -f "${tmpdir}/${extract_dir}/hbbr" "${INSTALL_DIR}/hbbr"

  $SUDO chmod +x "${INSTALL_DIR}/hbbs" "${INSTALL_DIR}/hbbr"
  $SUDO chown "$SERVICE_USER:$SERVICE_GROUP" "${INSTALL_DIR}/hbbs" "${INSTALL_DIR}/hbbr"
}

#######################################
# Write systemd units
#######################################
write_systemd_units() {
  log "写入 systemd 服务文件..."

  $SUDO tee /etc/systemd/system/rustdesk-hbbs.service >/dev/null <<EOF
[Unit]
Description=RustDesk Signal Server (hbbs)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/hbbs -r ${SERVER_HOST}
Restart=always
RestartSec=5
LimitNOFILE=1048576
StandardOutput=append:${LOG_DIR}/hbbs.log
StandardError=append:${LOG_DIR}/hbbs.error.log
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

  $SUDO tee /etc/systemd/system/rustdesk-hbbr.service >/dev/null <<EOF
[Unit]
Description=RustDesk Relay Server (hbbr)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/hbbr
Restart=always
RestartSec=5
LimitNOFILE=1048576
StandardOutput=append:${LOG_DIR}/hbbr.log
StandardError=append:${LOG_DIR}/hbbr.error.log
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

  $SUDO systemctl daemon-reload
  $SUDO systemctl enable rustdesk-hbbs.service rustdesk-hbbr.service
}

#######################################
# Start services
#######################################
start_services() {
  if [[ "$SKIP_START" == "true" ]]; then
    warn "已跳过服务启动"
    return
  fi

  log "启动 RustDesk 服务..."
  $SUDO systemctl restart rustdesk-hbbs.service
  $SUDO systemctl restart rustdesk-hbbr.service

  sleep 2

  $SUDO systemctl is-active --quiet rustdesk-hbbs.service || die "hbbs 启动失败"
  $SUDO systemctl is-active --quiet rustdesk-hbbr.service || die "hbbr 启动失败"

  log "服务已启动成功"
}

#######################################
# Read public key
#######################################
read_public_key() {
  local pubkey_file

  pubkey_file="$(find "$INSTALL_DIR" -maxdepth 1 -name "*.pub" | head -n 1 || true)"
  [[ -n "$pubkey_file" ]] || die "未找到公钥文件（*.pub），请检查服务是否正常生成密钥"

  cat "$pubkey_file"
}

#######################################
# Print result
#######################################
print_summary() {
  local public_key
  public_key="$(read_public_key)"

  cat <<EOF

========================================
RustDesk Server 安装完成
========================================
版本:          ${RUSTDESK_VERSION}
地址:          ${SERVER_HOST}
安装目录:      ${INSTALL_DIR}
日志目录:      ${LOG_DIR}
运行用户:      ${SERVICE_USER}:${SERVICE_GROUP}

systemd 服务:
  - rustdesk-hbbs.service
  - rustdesk-hbbr.service

客户端需要配置:
  Host / Relay: ${SERVER_HOST}
  Key:
${public_key}

常用检查命令:
  sudo systemctl status rustdesk-hbbs.service
  sudo systemctl status rustdesk-hbbr.service
  sudo journalctl -u rustdesk-hbbs.service -n 100 --no-pager
  sudo journalctl -u rustdesk-hbbr.service -n 100 --no-pager

注意:
1. 请确保服务器安全组 / 防火墙已放行 RustDesk 所需端口
2. 推荐优先使用域名而不是裸 IP
3. 若后续需要 HTTPS / 反向代理，请额外配 Nginx / Caddy
========================================

EOF
}

#######################################
# Main
#######################################
main() {
  parse_args "$@"
  init_sudo
  detect_os
  detect_arch
  validate_host_choice
  init_service_identity
  install_dependencies
  resolve_version
  prepare_dirs
  install_rustdesk_server
  write_systemd_units
  start_services
  print_summary
}

main "$@"
