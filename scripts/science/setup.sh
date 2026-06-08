#!/bin/bash

################################################################################
#
# VLESS + Reality 一键部署脚本 (Xray-core)
#
# 版本: v3.5.0
# 功能:
#   1. 下载并安装 Xray-core 最新版
#   2. 自动生成 X25519 密钥对
#   3. 配置 VLESS + Reality (伪装: www.microsoft.com)
#   4. 默认端口 8443 (不冲突现有 Nginx 443)
#   5. 下载 geoip.dat / geosite.dat
#   6. 开启 BBR 加速
#
# 用法:
#   ./setup.sh           # 交互式部署
#   ./setup.sh -h        # 显示帮助
#
# 前置条件:
#   - Root 权限
#   - 境外 VPS (Debian/Ubuntu/CentOS)
#   - 无需域名 / 无需 SSL 证书
#
################################################################################

set -euo pipefail

# ==================== 加载公共库 ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# ==================== 帮助信息 ====================
show_help() {
    cat <<'EOF'
VLESS + Reality 一键部署脚本

用法:
  ./setup.sh              # 交互式部署
  ./setup.sh -h           # 显示此帮助

环境变量 (可选):
  DEST_SNI=www.example.com    # 伪装目标 (默认: www.microsoft.com)
  REALITY_PORT=8443           # 监听端口 (默认: 8443)
  INFO_FILE=/path/to/info     # 信息输出文件

说明:
  - 自动下载 Xray-core 最新版
  - 生成 X25519 密钥对
  - 配置 VLESS + XTLS-Vision + Reality
  - 开启 TCP BBR 加速
EOF
    exit 0
}

# ==================== 参数解析 ====================
for arg in "$@"; do
    case "$arg" in
        -h|--help) show_help ;;
    esac
done

# ==================== 全局配置 ====================
# HONGAIBOX_* variables take precedence over legacy DEST_SNI/REALITY_PORT.
DEST_SNI="${HONGAIBOX_DEST_SNI:-${DEST_SNI:-www.microsoft.com}}"
REALITY_PORT="${HONGAIBOX_REALITY_PORT:-${REALITY_PORT:-8443}}"
XRAY_DIR="/usr/local/etc/xray"
INFO_FILE="${INFO_FILE:-$(dirname "$(readlink -f "$0")")/reality_node_info.txt}"

# ==================== 部署流程 ====================
check_root
setup_logging "science-setup"

print_header "VLESS + Reality 部署"

echo -e "服务器 IP: ${GREEN}$(detect_server_ip)${NC}"
echo ""

# ==================== 步骤 1: 安装 Xray-core ====================

log_step "[1/6] 下载安装 Xray-core..."

if ! command -v xray &>/dev/null; then
    XRAY_VERSION=$(curl -sL --connect-timeout 10 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1) || true
    [ -z "$XRAY_VERSION" ] && XRAY_VERSION="v26.3.27"
    log_info "版本: $XRAY_VERSION"

    XRAY_ARCH=$(detect_arch)
    case "$XRAY_ARCH" in
        linux_amd64)   XRAY_ARCH="linux-64" ;;
        linux_arm64)   XRAY_ARCH="linux-arm64-v8a" ;;
        linux_arm32*)  XRAY_ARCH="linux-arm32-v7a" ;;
        *) log_error "不支持架构: $(uname -m)"; exit 1 ;;
    esac

    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-${XRAY_ARCH}.zip"

    log_info "下载: $DOWNLOAD_URL"
    cd /tmp
    rm -f xray.zip
    curl -L --connect-timeout 60 -o xray.zip "$DOWNLOAD_URL" || {
        log_error "下载失败"
        exit 1
    }

    unzip -o xray.zip >/dev/null 2>&1 || true
    cp xray /usr/local/bin/
    chmod +x /usr/local/bin/xray

    # Systemd 服务
    cat > /etc/systemd/system/xray.service <<'SVC'
[Unit]
Description=Xray Service
After=network.target
[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
SVC
    systemctl daemon-reload
fi

log_success "Xray-core 就绪"
/usr/local/bin/xray version 2>/dev/null | head -1 || true

# ==================== 步骤 2: 生成密钥 ====================

log_step "[2/6] 生成 X25519 密钥对..."

KEYS=$(/usr/local/bin/xray x25519 2>/dev/null) || true
PRIVATE_KEY=$(echo "$KEYS" | grep "^PrivateKey:" | awk '{print $NF}') || true
PUBLIC_KEY=$(echo "$KEYS" | grep "^Password (PublicKey):" | awk '{print $NF}') || true
SHORT_ID=$(openssl rand -hex 8 2>/dev/null || head -c 8 /dev/urandom | xxd -p 2>/dev/null || tr -dc 'a-f0-9' < /dev/urandom | head -c 16)
UUID=$(cat /proc/sys/kernel/random/uuid)

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    log_error "密钥生成失败"
    exit 1
fi

echo -e "  Private: ${YELLOW}$PRIVATE_KEY${NC}"
echo -e "  Public:  ${YELLOW}$PUBLIC_KEY${NC}"
echo -e "  shortId: ${YELLOW}$SHORT_ID${NC}"
echo -e "  UUID:    ${YELLOW}$UUID${NC}"

# ==================== 步骤 3: 下载 geo 数据 ====================

log_step "[3/6] 下载 geoip/geosite 数据..."

cd /usr/local/bin
curl -sL --connect-timeout 30 -o geoip.dat \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" &
PID1=$!
curl -sL --connect-timeout 30 -o geosite.dat \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" &
PID2=$!
wait $PID1 2>/dev/null || true
wait $PID2 2>/dev/null || true
log_success "geo 数据就绪"

# ==================== 步骤 4: 生成配置 ====================

log_step "[4/6] 配置 Xray Reality..."

mkdir -p "$XRAY_DIR" /var/log/xray

cat > "$XRAY_DIR/config.json" <<XEOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [{
    "port": $REALITY_PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "$UUID",
        "flow": "xtls-rprx-vision"
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$DEST_SNI:443",
        "xver": 0,
        "serverNames": ["$DEST_SNI"],
        "privateKey": "$PRIVATE_KEY",
        "shortIds": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "tag": "direct"
  }]
}
XEOF

log_success "配置完成"

# ==================== 步骤 5: 启动 ====================

log_step "[5/6] 启动 Xray 服务..."

systemctl daemon-reload
systemctl enable xray 2>/dev/null || true
systemctl restart xray || true
sleep 2

if systemctl is-active --quiet xray; then
    log_success "Xray 运行中"
    ss -tlnp 2>/dev/null | grep ":$REALITY_PORT" || true
else
    log_error "启动失败，日志:"
    journalctl -u xray -n 15 --no-pager || true
    exit 1
fi

# ==================== 步骤 6: BBR ====================

log_step "[6/6] 系统优化 (BBR)..."

modprobe tcp_bbr 2>/dev/null || true
if ! grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true
fi
log_success "BBR 就绪"

# ==================== 输出结果 ====================

SERVER_IP=$(detect_server_ip)
VLESS_LINK="vless://$UUID@$SERVER_IP:$REALITY_PORT?type=tcp&security=reality&flow=xtls-rprx-vision&fp=chrome&sni=$DEST_SNI&pbk=$PUBLIC_KEY&sid=$SHORT_ID#MeiDe_Reality"

cat > "$INFO_FILE" <<EOF
================================================
     VLESS + Reality 节点配置
================================================
部署时间: $(date '+%Y-%m-%d %H:%M:%S')
伪装目标: $DEST_SNI
服务器:   $SERVER_IP
端口:     $REALITY_PORT

[连接参数]
协议:      VLESS
地址:      $SERVER_IP
端口:      $REALITY_PORT
UUID:      $UUID
Flow:      xtls-rprx-vision
传输:      tcp
安全:      reality
公钥:      $PUBLIC_KEY
SNI:       $DEST_SNI
Fingerprint: chrome
shortId:   $SHORT_ID

[分享链接]
$VLESS_LINK

[Clash Meta 订阅格式]
  - name: "MeiDe_Reality"
    type: vless
    server: $SERVER_IP
    port: $REALITY_PORT
    uuid: $UUID
    flow: xtls-rprx-vision
    tls: true
    network: tcp
    servername: $DEST_SNI
    reality-opts:
      public-key: $PUBLIC_KEY
      short-id: $SHORT_ID
    client-fingerprint: chrome

[服务管理]
启动: systemctl start xray
停止: systemctl stop xray
重启: systemctl restart xray
查看: systemctl status xray
日志: journalctl -u xray -f

[卸载]
systemctl stop xray && systemctl disable xray
rm -rf /usr/local/bin/xray /usr/local/etc/xray /var/log/xray
rm -f /etc/systemd/system/xray.service /usr/local/bin/*.dat
systemctl daemon-reload
================================================
EOF

echo ""
echo -e "${BOLD}${GREEN}"
echo "========================================"
echo "   VLESS + Reality 部署完成！"
echo "========================================"
echo -e "${NC}"
echo ""
echo -e "伪装: ${GREEN}$DEST_SNI${NC}"
echo -e "端口: ${GREEN}$REALITY_PORT${NC}"
echo ""
echo -e "${CYAN}▸ 分享链接:${NC}"
echo -e "${BOLD}$VLESS_LINK${NC}"
echo ""
echo -e "详情: ${YELLOW}$INFO_FILE${NC}"
echo ""
log_success "日志已保存: $DEPLOY_LOG_FILE"
