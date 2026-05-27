#!/bin/bash

################################################################################
#
# VLESS + Reality 一键部署脚本 (Xray-core)
#
# 版本: v1.1
# 功能:
#   1. 下载并安装 Xray-core 最新版
#   2. 自动生成 X25519 密钥对
#   3. 配置 VLESS + Reality (伪装: www.microsoft.com)
#   4. 默认端口 8443 (不冲突现有 Nginx 443)
#   5. 下载 geoip.dat / geosite.dat
#   6. 开启 BBR 加速
#
# 前置条件:
#   - Root 权限
#   - 境外 VPS (Debian/Ubuntu/CentOS)
#   - 无需域名 / 无需 SSL 证书
#
################################################################################

set -e

# ==================== 全局配置 ====================

DEST_SNI="${DEST_SNI:-www.microsoft.com}"
REALITY_PORT="${REALITY_PORT:-8443}"
XRAY_DIR="/usr/local/etc/xray"
INFO_FILE="${INFO_FILE:-$(dirname "$(readlink -f "$0")")/reality_node_info.txt}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║     VLESS + Reality 部署 v1.1                ║"
echo "║     伪装: ${DEST_SNI}                  ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ==================== 环境检查 ====================

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 需要 root 权限。${NC}"
    exit 1
fi

if ! command -v curl &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq curl 2>/dev/null || yum install -y curl 2>/dev/null
fi

SERVER_IP=$(curl -s4 --connect-timeout 5 https://api.ipify.org 2>/dev/null \
    || curl -s4 --connect-timeout 5 https://ifconfig.me 2>/dev/null \
    || hostname -I | awk '{print $1}')

if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}错误: 无法获取服务器 IP。${NC}"
    exit 1
fi

echo -e "服务器 IP: ${GREEN}$SERVER_IP${NC}"
echo ""

# ==================== 步骤 1: 安装 Xray-core ====================

echo -e "${CYAN}>>> [1/6] 下载安装 Xray-core...${NC}"

if ! command -v xray &>/dev/null; then
    XRAY_VERSION=$(curl -sL --connect-timeout 10 \
        "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\(.*\)".*/\1/')
    [ -z "$XRAY_VERSION" ] && XRAY_VERSION="v26.3.27"

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  XRAY_ARCH="linux-64" ;;
        aarch64) XRAY_ARCH="linux-arm64-v8a" ;;
        armv7l)  XRAY_ARCH="linux-arm32-v7a" ;;
        *) echo -e "${RED}不支持架构: $ARCH${NC}"; exit 1 ;;
    esac

    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-${XRAY_ARCH}.zip"

    echo "  下载: $DOWNLOAD_URL"
    cd /tmp
    rm -f xray.zip
    curl -L --connect-timeout 60 -o xray.zip "$DOWNLOAD_URL" || {
        echo -e "${RED}下载失败${NC}"
        exit 1
    }

    unzip -o xray.zip >/dev/null 2>&1
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

echo -e "${GREEN}✓ Xray-core 就绪${NC}"
/usr/local/bin/xray version 2>/dev/null | head -1

# ==================== 步骤 2: 生成密钥 ====================

echo -e "${CYAN}>>> [2/6] 生成 X25519 密钥对...${NC}"

KEYS=$(/usr/local/bin/xray x25519 2>/dev/null)
PRIVATE_KEY=$(echo "$KEYS" | grep "^PrivateKey:" | awk '{print $NF}')
PUBLIC_KEY=$(echo "$KEYS" | grep "^Password (PublicKey):" | awk '{print $NF}')
SHORT_ID=$(openssl rand -hex 8 2>/dev/null || head -c 8 /dev/urandom | xxd -p 2>/dev/null || tr -dc 'a-f0-9' < /dev/urandom | head -c 16)
UUID=$(cat /proc/sys/kernel/random/uuid)

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo -e "${RED}密钥生成失败${NC}"
    exit 1
fi

echo -e "  Private: ${YELLOW}$PRIVATE_KEY${NC}"
echo -e "  Public:  ${YELLOW}$PUBLIC_KEY${NC}"
echo -e "  shortId: ${YELLOW}$SHORT_ID${NC}"
echo -e "  UUID:    ${YELLOW}$UUID${NC}"

# ==================== 步骤 3: 下载 geo 数据 ====================

echo -e "${CYAN}>>> [3/6] 下载 geoip/geosite 数据...${NC}"

cd /usr/local/bin
curl -sL --connect-timeout 30 -o geoip.dat \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" &
PID1=$!
curl -sL --connect-timeout 30 -o geosite.dat \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" &
PID2=$!
wait $PID1 2>/dev/null || true
wait $PID2 2>/dev/null || true
echo -e "${GREEN}✓ geo 数据就绪${NC}"

# ==================== 步骤 4: 生成配置 ====================

echo -e "${CYAN}>>> [4/6] 配置 Xray Reality...${NC}"

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

echo -e "${GREEN}✓ 配置完成${NC}"

# ==================== 步骤 5: 启动 ====================

echo -e "${CYAN}>>> [5/6] 启动 Xray 服务...${NC}"

systemctl daemon-reload
systemctl enable xray 2>/dev/null || true
systemctl restart xray
sleep 2

if systemctl is-active --quiet xray; then
    echo -e "${GREEN}✓ Xray 运行中${NC}"
    ss -tlnp | grep ":$REALITY_PORT"
else
    echo -e "${RED}✗ 启动失败，日志:${NC}"
    journalctl -u xray -n 15 --no-pager
    exit 1
fi

# ==================== 步骤 6: BBR ====================

echo -e "${CYAN}>>> [6/6] 系统优化 (BBR)...${NC}"

modprobe tcp_bbr 2>/dev/null || true
if ! grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
fi
echo -e "${GREEN}✓ BBR 就绪${NC}"

# ==================== 输出结果 ====================

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
