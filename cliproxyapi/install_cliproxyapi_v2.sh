#!/bin/bash

################################################################################
#
# CliproxyAPI 智能安装/升级脚本
# 版本: v3.5.0
#
# 功能说明：
#   1. 自动检测是否已安装（智能判断全新安装 or 升级）
#   2. 全新安装：完整的交互式配置流程
#   3. 升级模式：保留所有配置，仅更新二进制文件
#   4. 支持域名模式 / IP 模式 / HTTP 模式
#   5. 配置 Nginx 反向代理（HTTPS + WebSocket）
#   6. 配置 Systemd 服务自启动
#   7. 支持回滚机制
#
# 用法:
#   ./install_cliproxyapi_v2.sh        # 交互式安装/升级
#   ./install_cliproxyapi_v2.sh -h     # 显示帮助
#
# 前置条件：
#   - 必须先运行 install_nginx.sh
#   - 域名模式：域名需要解析到本服务器
#   - IP/HTTP 模式：无需域名
#
################################################################################

set -euo pipefail

# ==================== 加载公共库 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# ==================== 帮助 ====================
show_help() {
    cat <<'EOF'
CliproxyAPI 智能安装/升级脚本

用法:
  ./install_cliproxyapi_v2.sh       # 交互式安装/升级
  ./install_cliproxyapi_v2.sh -h    # 显示此帮助

功能:
  - 自动检测全新安装 or 升级
  - 支持域名/IP/HTTP 三种访问模式
  - 自动申请 SSL 证书或生成自签名证书
  - 配置 Nginx 反向代理 + Systemd 服务
  - 升级时保留所有配置，仅更新二进制

前置条件:
  - 已安装 Nginx (install_nginx.sh)
  - 域名模式需 DNS 已解析
EOF
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        -h|--help) show_help ;;
    esac
done

# ==================== 全局配置 ====================
CLIPROXY_PORT=8317
CONF_D="/etc/nginx/conf.d"
SSL_DIR="/etc/nginx/ssl"
INSTALL_DIR="/opt/cliproxyapi"
CONFIG_DIR="/etc/cliproxyapi"
DATA_DIR="/var/lib/cliproxyapi"
LOG_DIR="/var/log/cliproxyapi"
GITHUB_REPO="router-for-me/CLIProxyAPI"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# ==================== 环境检查 ====================
check_root
setup_logging "cliproxyapi-install"

ensure_commands curl wget tar

if ! command -v nginx &> /dev/null; then
    log_error "未检测到 Nginx，请先运行 install_nginx.sh"
    exit 1
fi

# 端口检查（仅在全新安装时严格检查）
if [ ! -f "$INSTALL_DIR/version.txt" ]; then
    ensure_port_available "$CLIPROXY_PORT" "CliproxyAPI"
fi

# ==================== 检测安装状态 ====================
IS_UPGRADE=false
CURRENT_VERSION="none"

if [ -f "$INSTALL_DIR/version.txt" ]; then
    IS_UPGRADE=true
    CURRENT_VERSION=$(cat "$INSTALL_DIR/version.txt" 2>/dev/null || echo "unknown")
fi

# ==================== 欢迎横幅 ====================
clear
if [ "$IS_UPGRADE" = true ]; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}   CliproxyAPI 升级程序 v${COMMON_VERSION}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_info "检测到已安装版本: v${CURRENT_VERSION}"
    log_warning "即将进入升级模式（保留所有配置）"
    echo ""
    read -r -p "按回车键继续，或 Ctrl+C 取消..." _
else
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}   CliproxyAPI 安装程序 v${COMMON_VERSION}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
fi

# ==================== 交互输入（仅全新安装） ====================
USE_DOMAIN=true
USE_HTTP_ONLY=false
ADMIN_SECRET=""
API_KEY_1=""
API_KEY_2=""

if [ "$IS_UPGRADE" = false ]; then
    MODE=$(select_access_mode)

    case "$MODE" in
        domain) USE_DOMAIN=true; USE_HTTP_ONLY=false ;;
        ip)     USE_DOMAIN=false; USE_HTTP_ONLY=false ;;
        http)   USE_DOMAIN=false; USE_HTTP_ONLY=true ;;
    esac

    DOMAIN=$(get_domain_for_mode "$MODE")

    echo ""
    read -r -p "请输入管理面板密码: " ADMIN_SECRET
    if [ -z "$ADMIN_SECRET" ]; then
        log_error "管理面板密码不能为空。"
        exit 1
    fi

    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ "$USE_HTTP_ONLY" = true ]; then
        echo -e "${YELLOW}⚠️  HTTP 模式：无 SSL 加密${NC}"
    elif [ "$USE_DOMAIN" = true ]; then
        echo -e "${YELLOW}⚠️  重要提示：请确保域名已解析${NC}"
    else
        echo -e "${YELLOW}⚠️  IP 模式：将使用自签名证书${NC}"
    fi
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "访问地址: ${GREEN}$DOMAIN${NC}"
    echo -e "服务器IP: ${GREEN}$(detect_server_ip)${NC}"
    echo ""
    read -r -p "按回车键继续安装，Ctrl+C 取消..." _
else
    # 升级模式：从现有配置读取域名
    DOMAIN=""
    EXISTING_CONF=""
    for conf_file in "$CONF_D"/*.conf; do
        if [ -f "$conf_file" ] && grep -q "CLI-PROXY-API-START" "$conf_file" 2>/dev/null; then
            EXISTING_CONF="$conf_file"
            break
        fi
    done

    if [ -n "$EXISTING_CONF" ]; then
        DOMAIN=$(grep "server_name" "$EXISTING_CONF" | head -1 | awk '{print $2}' | sed 's/;//g' || echo "")
        log_info "检测到现有域名: $DOMAIN"
    else
        log_warning "未检测到现有 Nginx 配置，升级后可能需要手动配置"
    fi

    if [ -f "$CONFIG_DIR/config.yaml" ]; then
        ADMIN_SECRET=$(grep "secret-key:" "$CONFIG_DIR/config.yaml" | awk '{print $2}' | tr -d '"' || echo "")
    fi
fi

# ==================== 检测系统架构 ====================
echo ""
log_step "[1/7] 检测系统架构..."

ARCH=$(detect_arch)
if [ "$ARCH" = "unknown" ]; then
    log_error "不支持的系统架构: $(uname -m)"
    exit 1
fi
log_success "架构: $ARCH"

# ==================== 获取最新版本 ====================
log_step "[2/7] 获取最新版本信息..."

RELEASE_INFO=$(curl -s --connect-timeout 15 "$GITHUB_API")

if [ -z "$RELEASE_INFO" ]; then
    log_error "无法获取版本信息，请检查网络连接。"
    exit 1
fi

LATEST_VERSION=$(echo "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4 | sed 's/^v//')

if [ -z "$LATEST_VERSION" ]; then
    log_error "无法解析版本号。"
    exit 1
fi

log_success "最新版本: v$LATEST_VERSION"

if [ "$IS_UPGRADE" = true ] && [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    log_success "已是最新版本 (v$LATEST_VERSION)，无需升级。"
    exit 0
fi

# ==================== 备份（仅升级模式） ====================
BACKUP_DIR=""
SERVICE_WAS_RUNNING=false

if [ "$IS_UPGRADE" = true ]; then
    log_step "[3/7] 备份现有配置..."

    BACKUP_DIR="${INSTALL_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    [ -f "$CONFIG_DIR/config.yaml" ] && cp -a "$CONFIG_DIR/config.yaml" "$BACKUP_DIR/config.yaml" && log_success "✓ 已备份配置文件"
    [ -d "$DATA_DIR" ] && cp -a "$DATA_DIR" "$BACKUP_DIR/data" && log_success "✓ 已备份数据目录"
    [ -f "$INSTALL_DIR/cli-proxy-api" ] && cp -a "$INSTALL_DIR/cli-proxy-api" "$BACKUP_DIR/cli-proxy-api.bak" && log_success "✓ 已备份可执行文件"

    log_success "备份完成: $BACKUP_DIR"

    if systemctl is-active --quiet cliproxyapi 2>/dev/null; then
        SERVICE_WAS_RUNNING=true
        systemctl stop cliproxyapi
        log_success "服务已停止"
    fi
    sleep 2
fi

# ==================== 下载并安装 ====================
STEP_NUM=$([ "$IS_UPGRADE" = true ] && echo "4" || echo "3")
log_step "[${STEP_NUM}/7] 下载并安装 CliproxyAPI..."

EXPECTED_FILENAME="CLIProxyAPI_${LATEST_VERSION}_${ARCH}.tar.gz"
DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -o "\"browser_download_url\": *\"[^\"]*${EXPECTED_FILENAME}[^\"]*\"" | cut -d'"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
    log_error "无法找到架构 ${ARCH} 的下载地址。"
    [ "$IS_UPGRADE" = true ] && exit 1 || exit 1
fi

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

log_info "下载: $EXPECTED_FILENAME"
if ! curl -L --connect-timeout 120 -o "cli-proxy-api.tar.gz" "$DOWNLOAD_URL"; then
    log_error "下载失败，请检查网络连接。"
    rm -rf "$TMP_DIR"
    exit 1
fi

log_success "下载完成"
tar -xzf "cli-proxy-api.tar.gz"

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR/storage" "$DATA_DIR/auth" "$LOG_DIR"

BINARY_FILE=$(find . -name "cli-proxy-api" -type f | head -1)
if [ -z "$BINARY_FILE" ]; then
    log_error "解压后未找到可执行文件。"
    rm -rf "$TMP_DIR"
    exit 1
fi

mv "$BINARY_FILE" "$INSTALL_DIR/cli-proxy-api"
chmod +x "$INSTALL_DIR/cli-proxy-api"
echo "$LATEST_VERSION" > "$INSTALL_DIR/version.txt"

log_success "安装完成: $INSTALL_DIR/cli-proxy-api"
cd / && rm -rf "$TMP_DIR"

# ==================== 配置文件处理 ====================
STEP_NUM=$([ "$IS_UPGRADE" = true ] && echo "5" || echo "4")
log_step "[${STEP_NUM}/7] 配置文件处理..."

if [ "$IS_UPGRADE" = true ]; then
    if [ -f "$BACKUP_DIR/config.yaml" ]; then
        cp -a "$BACKUP_DIR/config.yaml" "$CONFIG_DIR/config.yaml"
        log_success "配置文件已恢复（保留所有设置）"
    else
        log_warning "备份配置不存在，保持现有配置"
    fi
else
    # 使用安全的密钥生成
    API_KEY_1=$(generate_api_key "sk-")
    API_KEY_2=$(generate_api_key "sk-")

    cat > "$CONFIG_DIR/config.yaml" <<YAML_EOF
# CliproxyAPI Configuration File
# Auto-generated by install script v${COMMON_VERSION}

# ==================== Server Configuration ====================
host: "127.0.0.1"
port: $CLIPROXY_PORT

# ==================== Authentication ====================
auth-dir: "$DATA_DIR/auth"

# API keys for client authentication
api-keys:
  - "$API_KEY_1"
  - "$API_KEY_2"

# ==================== Management Panel ====================
remote-management:
  allow-remote: true
  secret-key: "$ADMIN_SECRET"
  disable-control-panel: false
  panel-github-repository: "https://github.com/router-for-me/Cli-Proxy-API-Management-Center"

# ==================== Logging ====================
debug: false
logging-to-file: true
logs-max-total-size-mb: 100

# ==================== Performance ====================
commercial-mode: false
usage-statistics-enabled: false

# ==================== Request Handling ====================
proxy-url: ""
force-model-prefix: false
request-retry: 3
max-retry-interval: 30

quota-exceeded:
  switch-project: true
  switch-preview-model: true

routing:
  strategy: "round-robin"

ws-auth: false

# ==================== TLS ====================
# TLS is handled by Nginx, keep disabled
tls:
  enable: false
  cert: ""
  key: ""
YAML_EOF

    log_success "配置文件: $CONFIG_DIR/config.yaml"
    log_info "API 密钥 1: $API_KEY_1"
    log_info "API 密钥 2: $API_KEY_2"
fi

# ==================== SSL 证书处理 ====================
if [ "$IS_UPGRADE" = false ] && [ -n "$DOMAIN" ]; then
    STEP_NUM=$([ "$IS_UPGRADE" = true ] && echo "6" || echo "5")
    log_step "[${STEP_NUM}/7] 配置 SSL 证书..."

    DOMAIN_SSL_DIR="$SSL_DIR/$DOMAIN"

    if [ "$USE_HTTP_ONLY" = true ]; then
        SSL_TYPE="无 (HTTP 模式)"
        log_info "HTTP 模式，跳过 SSL 证书配置"
    elif [ "$USE_DOMAIN" = true ]; then
        SSL_TYPE=$(apply_ssl_certificate "$DOMAIN" "$DOMAIN_SSL_DIR" "domain")
    else
        SSL_TYPE=$(apply_ssl_certificate "$DOMAIN" "$DOMAIN_SSL_DIR" "ip")
    fi
fi

# ==================== Nginx 配置（仅全新安装） ====================
if [ "$IS_UPGRADE" = false ] && [ -n "$DOMAIN" ]; then
    STEP_NUM=$([ "$IS_UPGRADE" = true ] && echo "7" || echo "6")
    log_step "[${STEP_NUM}/7] 配置 Nginx 反向代理..."

    NGINX_SUPPORTS_HTTP3=false
    if detect_nginx_http3; then
        NGINX_SUPPORTS_HTTP3=true
        log_info "检测到 HTTP/3 支持"
    fi

    DOMAIN_SSL_DIR="$SSL_DIR/$DOMAIN"
    mkdir -p "$DOMAIN_SSL_DIR"

    # 公共 location 块（所有模式共用）
    read -r -d '' LOCATION_BLOCKS <<'LOC_EOF' || true
    #CLI-PROXY-API-START

    # WebSocket
    location /v1/ws {
        proxy_pass http://127.0.0.1:CLIPROXY_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    # OpenAI SSE - Chat Completions
    location /v1/chat/completions {
        proxy_pass http://127.0.0.1:CLIPROXY_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_set_header Accept-Encoding "";
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache off;
        add_header X-Accel-Buffering no always;
        gzip off;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
        chunked_transfer_encoding on;
    }

    # 其他 v1 API
    location /v1/ {
        proxy_pass http://127.0.0.1:CLIPROXY_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }

    # v0 管理接口
    location /v0/ {
        proxy_pass http://127.0.0.1:CLIPROXY_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60;
    }

    # 默认
    location / {
        proxy_pass http://127.0.0.1:CLIPROXY_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }

    #CLI-PROXY-API-END
LOC_EOF

    # 生成 Nginx 配置
    CONF_FILE="$CONF_D/${DOMAIN}.conf"

    if [ "$USE_HTTP_ONLY" = true ]; then
        # HTTP 模式
        cat > "$CONF_FILE" <<NGX_HTTP
server {
    listen 80;
    server_name $DOMAIN;

    client_max_body_size 100m;
    tcp_nodelay on;

    access_log /var/log/nginx/cliproxyapi_access.log;
    error_log /var/log/nginx/cliproxyapi_error.log warn;

$LOCATION_BLOCKS
}
NGX_HTTP
    elif [ "$NGINX_SUPPORTS_HTTP3" = true ]; then
        # HTTP/3 模式
        cat > "$CONF_FILE" <<NGX_H3
server {
    listen 80;
    listen 443 ssl;
    listen 443 quic;
    http2 on;

    server_name $DOMAIN;
    client_max_body_size 100m;
    tcp_nodelay on;

    location /.well-known/acme-challenge/ {
        root /var/www/acme;
    }

    #SSL-START
    #HTTP_TO_HTTPS_START
    set \$isRedcert 1;
    if (\$server_port != 443) { set \$isRedcert 2; }
    if ( \$uri ~ /\.well-known/ ) { set \$isRedcert 1; }
    if (\$isRedcert != 1) { rewrite ^(.*)\$ https://\$host\$1 permanent; }
    #HTTP_TO_HTTPS_END
    ssl_certificate $DOMAIN_SSL_DIR/fullchain.pem;
    ssl_certificate_key $DOMAIN_SSL_DIR/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_tickets on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header Alt-Svc 'h3=":443"; ma=86400';
    error_page 497 https://\$host\$request_uri;
    #SSL-END

    access_log /var/log/nginx/cliproxyapi_access.log;
    error_log /var/log/nginx/cliproxyapi_error.log warn;

$LOCATION_BLOCKS
}
NGX_H3
    else
        # HTTP/2 模式
        cat > "$CONF_FILE" <<NGX_H2
server {
    listen 80;
    listen 443 ssl;
    http2 on;

    server_name $DOMAIN;
    client_max_body_size 100m;
    tcp_nodelay on;

    location /.well-known/acme-challenge/ {
        root /var/www/acme;
    }

    #SSL-START
    #HTTP_TO_HTTPS_START
    set \$isRedcert 1;
    if (\$server_port != 443) { set \$isRedcert 2; }
    if ( \$uri ~ /\.well-known/ ) { set \$isRedcert 1; }
    if (\$isRedcert != 1) { rewrite ^(.*)\$ https://\$host\$1 permanent; }
    #HTTP_TO_HTTPS_END
    ssl_certificate $DOMAIN_SSL_DIR/fullchain.pem;
    ssl_certificate_key $DOMAIN_SSL_DIR/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_tickets on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    add_header Strict-Transport-Security "max-age=31536000" always;
    error_page 497 https://\$host\$request_uri;
    #SSL-END

    access_log /var/log/nginx/cliproxyapi_access.log;
    error_log /var/log/nginx/cliproxyapi_error.log warn;

$LOCATION_BLOCKS
}
NGX_H2
    fi

    # 替换占位符
    sed -i "s|CLIPROXY_PORT_PLACEHOLDER|$CLIPROXY_PORT|g" "$CONF_FILE"

    log_success "Nginx 配置已生成: $CONF_FILE"

    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx
        log_success "Nginx 已重载"
    else
        log_error "Nginx 配置测试失败"
        nginx -t
    fi
fi

# ==================== Systemd 服务 ====================
log_step "[7/7] 配置 Systemd 服务..."

cat > /etc/systemd/system/cliproxyapi.service <<SVC_EOF
[Unit]
Description=CLIProxyAPI Service
Documentation=https://help.router-for.me/cn/
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/cli-proxy-api -config $CONFIG_DIR/config.yaml
Restart=always
RestartSec=10s

Environment="HOME=/root"

NoNewPrivileges=true
PrivateTmp=true

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC_EOF

systemctl daemon-reload
systemctl enable cliproxyapi >/dev/null 2>&1

if [ "$IS_UPGRADE" = true ] && [ "$SERVICE_WAS_RUNNING" = true ]; then
    systemctl start cliproxyapi
elif [ "$IS_UPGRADE" = false ]; then
    systemctl start cliproxyapi
fi

sleep 2

if systemctl is-active --quiet cliproxyapi; then
    log_success "服务已启动"
else
    log_warning "服务启动失败，请检查: journalctl -u cliproxyapi -n 50"
fi

# ==================== 完成信息 ====================
SERVER_IP=$(detect_server_ip)

clear
echo -e "${GREEN}"
if [ "$IS_UPGRADE" = true ]; then
    cat <<EOF
================================================
       CliproxyAPI 升级成功！(v${COMMON_VERSION})
================================================
EOF
    echo -e "${NC}"
    echo -e "旧版本:     ${YELLOW}v${CURRENT_VERSION}${NC}"
    echo -e "新版本:     ${GREEN}v${LATEST_VERSION}${NC}"
    echo ""
    echo -e "${CYAN}[配置保留]${NC}"
    echo -e "配置文件:   已保留"
    echo -e "数据目录:   已保留"
    echo -e "备份位置:   $BACKUP_DIR"
else
    if [ "$USE_HTTP_ONLY" = true ]; then
        PROTOCOL="http"
        ACCESS_MODE_TEXT="HTTP 模式"
    elif [ "$USE_DOMAIN" = true ]; then
        PROTOCOL="https"
        ACCESS_MODE_TEXT="域名模式"
    else
        PROTOCOL="https"
        ACCESS_MODE_TEXT="IP 模式"
    fi

    cat <<EOF
================================================
       CliproxyAPI 安装成功！(v${COMMON_VERSION})
================================================
访问模式:  $ACCESS_MODE_TEXT
服务器 IP: $SERVER_IP
访问地址:  $DOMAIN

[访问地址]
$( [ "$USE_HTTP_ONLY" = true ] && echo "HTTP:      http://$DOMAIN" || echo "HTTPS:     https://$DOMAIN" )
管理界面:  ${PROTOCOL}://$DOMAIN/management.html
$( [ "$USE_HTTP_ONLY" = true ] && echo "
⚠️  HTTP 模式注意事项:
- 数据传输不加密，API Key 可能泄露
- 仅建议在内网或开发环境使用" )
$( [ "$USE_HTTP_ONLY" = false ] && [ "$USE_DOMAIN" = false ] && echo "
⚠️  IP 模式注意事项:
- 浏览器会提示证书不安全，请点击「高级」→「继续访问」
- API 客户端需要关闭 SSL 验证或信任自签名证书" )

[API 密钥]
密钥 1:    $API_KEY_1
密钥 2:    $API_KEY_2

[管理面板]
访问地址:  ${PROTOCOL}://$DOMAIN/management.html
登录密码:  $ADMIN_SECRET

[配置信息]
版本:      v$LATEST_VERSION
配置文件:  $CONFIG_DIR/config.yaml
数据目录:  $DATA_DIR
日志文件:  $LOG_DIR/cliproxyapi.log

[SSL 证书]
类型:      ${SSL_TYPE:-已存在}
EOF
fi

echo ""
echo -e "${CYAN}[服务管理]${NC}"
echo "查看状态:  systemctl status cliproxyapi"
echo "启动服务:  systemctl start cliproxyapi"
echo "停止服务:  systemctl stop cliproxyapi"
echo "重启服务:  systemctl restart cliproxyapi"
echo "查看日志:  journalctl -u cliproxyapi -f"
echo ""
echo -e "${GREEN}安装完成！${NC}"
echo "================================================"
echo ""
log_success "日志已保存: $DEPLOY_LOG_FILE"
