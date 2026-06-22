#!/bin/bash

################################################################################
#
# 通用 SSL 证书申请工具
# 版本: v4.0.0
#
# 功能说明：
#   - 为任意域名申请 Let's Encrypt ECC-256 证书
#   - 自动配置 Nginx（可选）
#   - 支持交互式和非交互式使用
#   - 失败时自动降级为自签名证书
#
# 使用方法：
#   交互式:   ./apply_ssl.sh
#   非交互式: ./apply_ssl.sh -d api.example.com [-s cliproxyapi] [-p 8317]
#   帮助:     ./apply_ssl.sh -h
#
# 参数说明：
#   -d DOMAIN   域名（必填）
#   -s SERVICE  服务名称（用于生成 Nginx 配置文件名，可选）
#   -p PORT     后端服务端口（可选）
#   -h          显示帮助信息
#
################################################################################

set -euo pipefail

# ==================== 加载公共库 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# ==================== 帮助信息 ====================
show_help() {
    cat <<'EOF'
通用 SSL 证书申请工具

用法:
  交互式:   ./apply_ssl.sh
  非交互式: ./apply_ssl.sh -d <域名> [-s <服务名>] [-p <端口>]
  帮助:     ./apply_ssl.sh -h

参数说明:
  -d DOMAIN   域名（必填）
  -s SERVICE  服务名称（可选），用于生成 Nginx 配置文件名
  -p PORT     后端服务端口（可选），指定后生成反向代理配置
  -h          显示此帮助信息

示例:
  ./apply_ssl.sh -d api.example.com
  ./apply_ssl.sh -d api.example.com -s cliproxyapi -p 8317

注意事项:
  1. 必须以 root 权限运行
  2. 域名需已解析到本服务器
  3. Nginx 必须已安装并运行
EOF
    exit 0
}

# ==================== 参数解析 ====================
DOMAIN=""
SERVICE=""
PORT=""

while getopts "d:s:p:h" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        s) SERVICE="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        h) show_help ;;
        *) show_help; exit 1 ;;
    esac
done

# ==================== 环境检查 ====================
check_root

if ! command -v nginx &> /dev/null; then
    echo -e "${RED}错误: 未检测到 Nginx 安装。${NC}"
    exit 1
fi

if ! systemctl is-active --quiet nginx; then
    echo -e "${RED}错误: Nginx 未运行。${NC}"
    echo -e "请先启动 Nginx: systemctl start nginx"
    exit 1
fi

ensure_commands curl openssl

# ==================== 交互式输入 ====================

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}   通用 SSL 证书申请工具 v${COMMON_VERSION}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 交互式输入域名
if [ -z "$DOMAIN" ]; then
    read -r -p "请输入域名 (例如 api.example.com): " DOMAIN
fi

# 域名验证
validate_domain "$DOMAIN" || exit 1

# 交互式输入服务名（可选）
if [ -z "$SERVICE" ]; then
    read -r -p "服务名称 (留空则不生成 Nginx 配置): " SERVICE
fi

# 交互式输入端口（可选）
if [ -z "$PORT" ] && [ -n "$SERVICE" ]; then
    read -r -p "后端服务端口 (留空则生成基础配置): " PORT
fi

# ==================== DNS 检查提示 ====================

CONF_D="/etc/nginx/conf.d"
SSL_DIR="/etc/nginx/ssl"
SERVER_IP=$(detect_server_ip)

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}⚠️  DNS 解析检查${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "域名:         ${GREEN}$DOMAIN${NC}"
echo -e "服务器 IP:    ${GREEN}$SERVER_IP${NC}"

# 检查域名解析
RESOLVED_IP=$(nslookup "$DOMAIN" 2>/dev/null | grep -A1 'Name:' | tail -n1 | awk '{print $2}' || true)
if [ -z "$RESOLVED_IP" ]; then
    RESOLVED_IP=$(dig +short "$DOMAIN" 2>/dev/null | tail -n1 || true)
fi

if [ -n "$RESOLVED_IP" ]; then
    echo -e "域名解析到:   ${GREEN}$RESOLVED_IP${NC}"

    if [ "$RESOLVED_IP" == "$SERVER_IP" ]; then
        echo -e "${GREEN}✓ 域名解析正确${NC}"
    else
        echo -e "${YELLOW}⚠ 域名未解析到本服务器，SSL 申请可能失败${NC}"
        echo -e "${YELLOW}  如果使用 Cloudflare CDN，这是正常的${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 无法解析域名，请确保 DNS 已配置${NC}"
fi

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -r -p "按回车继续申请证书..." _

# ==================== 申请 SSL 证书 ====================

echo ""
log_step "[1/3] 检查 acme.sh..."

DOMAIN_SSL_DIR="$SSL_DIR/$DOMAIN"

# 创建临时 Nginx 配置用于验证（如不存在）
NGINX_CONF="$CONF_D/${DOMAIN}.conf"
TEMP_CONF=false

if [ ! -f "$NGINX_CONF" ]; then
    log_info "创建临时 Nginx 配置用于 ACME 验证..."
    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ {
        root /var/www/acme;
    }
}
EOF
    TEMP_CONF=true
    mkdir -p /var/www/acme
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
fi

# 申请证书
log_step "[2/3] 申请 SSL 证书..."
SSL_TYPE=$(apply_ssl_certificate "$DOMAIN" "$DOMAIN_SSL_DIR" "domain")

SSL_OK=false
if [ -f "$DOMAIN_SSL_DIR/fullchain.pem" ] && [[ "$SSL_TYPE" =~ "Let's Encrypt" ]]; then
    SSL_OK=true
fi

# ==================== 配置 Nginx ====================

log_step "[3/3] 配置 Nginx..."

if [ -n "$SERVICE" ]; then
    if [ "$TEMP_CONF" = true ]; then
        FINAL_CONF="$CONF_D/${DOMAIN}.conf"
    else
        FINAL_CONF="$NGINX_CONF"
        if [ -f "$FINAL_CONF" ]; then
            backup_file "$FINAL_CONF"
        fi
    fi

    if [ -n "$PORT" ]; then
        # 生成完整反向代理配置
        cat > "$FINAL_CONF" <<NGINX_EOF
# HTTP → HTTPS 重定向
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/acme;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS 反向代理
server {
    listen 443 ssl;
    http2 on;
    server_name $DOMAIN;

    ssl_certificate $DOMAIN_SSL_DIR/fullchain.pem;
    ssl_certificate_key $DOMAIN_SSL_DIR/key.pem;
    ${NGINX_SSL_CONFIG}

    access_log /var/log/nginx/${SERVICE}_access.log main;
    error_log /var/log/nginx/${SERVICE}_error.log warn;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
}
NGINX_EOF
        log_success "已生成完整反向代理配置"
    else
        # 生成基础 HTTPS 配置
        cat > "$FINAL_CONF" <<NGINX_EOF
# HTTP → HTTPS 重定向
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/acme;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS 基础配置
server {
    listen 443 ssl;
    http2 on;
    server_name $DOMAIN;

    ssl_certificate $DOMAIN_SSL_DIR/fullchain.pem;
    ssl_certificate_key $DOMAIN_SSL_DIR/key.pem;
    ${NGINX_SSL_CONFIG}

    root /var/www/html;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGINX_EOF
        log_success "已生成基础 HTTPS 配置"
    fi

    echo -e "配置文件: ${YELLOW}$FINAL_CONF${NC}"
else
    log_info "未指定服务名，跳过 Nginx 配置生成"
fi

# 测试并重载 Nginx
if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx || true
    log_success "Nginx 配置测试通过并已重载"
else
    log_error "Nginx 配置测试失败，请检查配置"
    nginx -t 2>&1 || true
fi

# ==================== 输出结果 ====================

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   SSL 证书申请完成${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "域名:       ${CYAN}$DOMAIN${NC}"
echo -e "证书类型:   ${CYAN}$SSL_TYPE${NC}"
echo -e "证书目录:   ${CYAN}$DOMAIN_SSL_DIR/${NC}"
echo -e "  - 私钥:   ${YELLOW}key.pem${NC}"
echo -e "  - 证书:   ${YELLOW}fullchain.pem${NC}"

if [ -n "$SERVICE" ]; then
    echo -e "Nginx配置:  ${CYAN}$FINAL_CONF${NC}"
fi

echo ""
echo -e "${CYAN}[访问地址]${NC}"
echo -e "HTTP:       ${YELLOW}http://$DOMAIN${NC}"
echo -e "HTTPS:      ${YELLOW}https://$DOMAIN${NC}"

if [ "$SSL_OK" = true ]; then
    echo ""
    echo -e "${GREEN}[证书续期]${NC}"
    echo -e "acme.sh 已自动配置 cron 任务，证书将在到期前自动续期。"
    echo -e "查看任务: ${YELLOW}crontab -l | grep acme${NC}"
else
    echo ""
    echo -e "${YELLOW}[提示]${NC}"
    echo -e "使用自签名证书，客户端需要跳过证书验证或手动信任。"
    echo -e "建议确保域名正确解析后，重新运行此脚本申请有效证书。"
fi

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
