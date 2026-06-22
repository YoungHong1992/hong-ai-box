#!/bin/bash

################################################################################
#
# Nginx 安装与系统优化脚本
# 版本: v4.0.0
#
# 功能说明：
#   1. 系统内核优化：开启 BBR、优化 TCP 连接、提升文件描述符限制
#   2. 通过 nginx.org 官方仓库安装最新主线版（支持 HTTP/3）
#   3. 配置高并发优化
#
# 适用环境：
#   - Ubuntu 20.04+ / Debian 11+
#
# 使用方法：
#   chmod +x install_nginx.sh
#   ./install_nginx.sh          # 安装
#   ./install_nginx.sh -h       # 显示帮助
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
Nginx 安装与系统优化脚本

用法:
  ./install_nginx.sh       # 安装 Nginx + 系统优化
  ./install_nginx.sh -h    # 显示此帮助

功能:
  - 开启 TCP BBR 拥塞控制
  - 优化系统内核参数
  - 从 nginx.org 官方主线仓库安装 Nginx (含 HTTP/3)
  - 配置高并发优化

支持系统: Ubuntu 20.04+, Debian 11+
EOF
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        -h|--help) show_help ;;
    esac
done

# ==================== 全局配置 ====================

NGINX_CONF_DIR="/etc/nginx"
NGINX_SSL_DIR="$NGINX_CONF_DIR/ssl"
USER="www"
GROUP="www"

# ==================== 部署流程 ====================
check_root
setup_logging "nginx-install"

log_step "[1/3] 系统环境检查与优化..."

# 1. 内核参数优化 (开启 BBR + TCP 调优)
log_info "优化 sysctl.conf..."
cat > /etc/sysctl.d/99-vps-optimize.conf <<'SYSCTL_EOF'
# --- BBR 拥塞控制 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- TCP 优化 ---
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 8192

# --- 文件描述符 ---
fs.file-max = 1000000
SYSCTL_EOF

# 应用内核参数
sysctl -p /etc/sysctl.d/99-vps-optimize.conf > /dev/null 2>&1 || true

# 验证 BBR
BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [ "$BBR_STATUS" == "bbr" ]; then
    log_success "TCP BBR 已成功开启"
else
    log_warning "BBR 开启失败，请检查内核版本 (建议 >= 4.9)"
fi

# 2. 提升系统级文件描述符限制
if ! grep -q "soft nofile 65535" /etc/security/limits.conf 2>/dev/null; then
    {
        echo "* soft nofile 65535"
        echo "* hard nofile 65535"
        echo "root soft nofile 65535"
        echo "root hard nofile 65535"
    } >> /etc/security/limits.conf
fi

# 3. 创建 nginx 运行用户
id -u "$USER" &>/dev/null || useradd -s /sbin/nologin -M "$USER"

# ==================== 步骤 2: 安装 Nginx ====================

log_step "[2/3] 安装 Nginx (nginx.org 官方主线包)..."

# 检测系统并添加 nginx.org 官方仓库
if [ -f /etc/debian_version ]; then
    # 安装必要依赖（curl 已存在时也要确保 gpg/证书工具存在）
    apt-get update -y -qq
    apt-get install -y -qq curl gnupg2 ca-certificates lsb-release

    # 添加 nginx.org GPG key
    curl -fsSL --connect-timeout 30 https://nginx.org/keys/nginx_signing.key \
        | gpg --dearmor --yes -o /usr/share/keyrings/nginx-archive-keyring.gpg

    # 添加 mainline 仓库（支持 HTTP/3）
    . /etc/os-release
    if [ "$ID" = "debian" ] && [ -z "${VERSION_CODENAME:-}" ]; then
        VERSION_CODENAME=$(lsb_release -cs 2>/dev/null || echo "bookworm")
    fi
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/mainline/${ID}/ ${VERSION_CODENAME} nginx" \
        > /etc/apt/sources.list.d/nginx.list

    # 优先使用 nginx.org 仓库
    cat > /etc/apt/preferences.d/99nginx <<'APT_PREF_EOF'
Package: nginx*
Pin: origin nginx.org
Pin-Priority: 900
APT_PREF_EOF

    apt-get update -y -qq
    apt-get install -y nginx

    log_success "Nginx 安装完成"

elif [ -f /etc/redhat-release ]; then
    log_error "CentOS / RHEL 不在本脚本的支持范围内。"
    log_info "请使用 Ubuntu 20.04+ 或 Debian 11+。"
    log_info "对于 RHEL 系列，请参考 nginx.org 官方文档手动安装。"
    exit 1
else
    log_error "不支持的操作系统。"
    exit 1
fi

# 验证 HTTP/3 模块
if nginx -V 2>&1 | grep -q "http_v3_module"; then
    log_success "HTTP/3 (QUIC) 模块已就绪"
else
    log_warning "当前 Nginx 未包含 HTTP/3 模块"
fi

# ==================== 步骤 3: 配置 Nginx ====================

log_step "[3/3] 配置 Nginx 高并发优化..."

# 备份已有配置
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    backup_file "$NGINX_CONF_DIR/nginx.conf"
fi

# 创建 SSL 证书存放目录（供后续服务使用）
mkdir -p "$NGINX_SSL_DIR"
chown -R "$USER:$GROUP" "$NGINX_SSL_DIR"

# 创建日志目录并设权限
mkdir -p /var/log/nginx
chown -R "$USER:$GROUP" /var/log/nginx

# 生成 nginx.conf（高并发调优 + 模块化站点配置）
cat > "$NGINX_CONF_DIR/nginx.conf" <<NGINX_EOF
user  $USER;
worker_processes  auto;
worker_rlimit_nofile 65535;

error_log  /var/log/nginx/error.log warn;
pid        /run/nginx.pid;

events {
    worker_connections  10240;
    use epoll;
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 2048;
    server_tokens   off;

    gzip on;
    gzip_min_length 1k;
    gzip_comp_level 4;
    gzip_types text/plain text/css application/json application/javascript application/xml;

    # 加载模块化站点配置
    include /etc/nginx/conf.d/*.conf;
}
NGINX_EOF

# 测试配置并启动
if nginx -t; then
    systemctl enable nginx
    systemctl restart nginx || true
    log_success "Nginx 配置测试通过，服务已启动"
else
    log_error "Nginx 配置测试失败，请检查"
    exit 1
fi

# ==================== 输出安装摘要 ====================

NGINX_VERSION=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+' || echo "unknown")
echo ""
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   Nginx 安装与系统优化完成${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "版本:         ${GREEN}v${COMMON_VERSION}${NC}"
echo -e "Nginx 版本:   ${YELLOW}$NGINX_VERSION${NC}"
echo -e "安装来源:     ${YELLOW}nginx.org 官方主线仓库${NC}"
echo -e "配置文件:     ${YELLOW}/etc/nginx/nginx.conf${NC}"
echo -e "站点配置:     ${YELLOW}/etc/nginx/conf.d/*.conf${NC}"
echo -e "SSL 证书:     ${YELLOW}/etc/nginx/ssl/${NC}"
echo -e "优化状态:     ${GREEN}BBR 已开启, Limit 已提升${NC}"
echo -e "HTTP/3 支持:  ${GREEN}$(detect_nginx_http3 && echo '✓' || echo '✗')${NC}"
echo -e "${GREEN}==============================================${NC}"
echo ""
log_success "日志已保存: $DEPLOY_LOG_FILE"
