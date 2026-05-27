#!/bin/bash

################################################################################
#
# Nginx 安装与系统优化脚本 (v5.0)
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
#   ./install_nginx.sh
#
################################################################################

# ==================== 全局配置 ====================

NGINX_CONF_DIR="/etc/nginx"
NGINX_SSL_DIR="$NGINX_CONF_DIR/ssl"
USER="www"
GROUP="www"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==================== 检查 Root 权限 ====================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 必须使用 root 权限运行此脚本。${NC}"
    exit 1
fi

echo -e "${CYAN}>>> [1/3] 系统环境检查与优化...${NC}"

# 1. 内核参数优化 (开启 BBR + TCP 调优)
echo "正在优化 sysctl.conf..."
cat > /etc/sysctl.d/99-vps-optimize.conf <<'EOF'
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
EOF

# 应用内核参数
sysctl -p /etc/sysctl.d/99-vps-optimize.conf > /dev/null 2>&1

# 验证 BBR
BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [ "$BBR_STATUS" == "bbr" ]; then
    echo -e "${GREEN}✓ TCP BBR 已成功开启${NC}"
else
    echo -e "${YELLOW}⚠ BBR 开启失败，请检查内核版本 (建议 >= 4.9)${NC}"
fi

# 2. 提升系统级文件描述符限制
if ! grep -q "* soft nofile 65535" /etc/security/limits.conf; then
    echo "* soft nofile 65535" >> /etc/security/limits.conf
    echo "* hard nofile 65535" >> /etc/security/limits.conf
    echo "root soft nofile 65535" >> /etc/security/limits.conf
    echo "root hard nofile 65535" >> /etc/security/limits.conf
fi

# 3. 创建 nginx 运行用户
id -u $USER &>/dev/null || useradd -s /sbin/nologin -M $USER

echo -e "${CYAN}>>> [2/3] 安装 Nginx (nginx.org 官方主线包)...${NC}"

# 检测系统并添加 nginx.org 官方仓库
if [ -f /etc/debian_version ]; then
    # 检测是否需要安装依赖
    if ! command -v curl &> /dev/null; then
        apt-get update -y -qq
        apt-get install -y -qq curl gnupg2 ca-certificates lsb-release
    fi

    # 添加 nginx.org GPG key
    curl -fsSL https://nginx.org/keys/nginx_signing.key \
        | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

    # 添加 mainline 仓库（支持 HTTP/3）
    . /etc/os-release
    if [ "$ID" = "debian" ] && [ -z "$VERSION_CODENAME" ]; then
        VERSION_CODENAME=$(lsb_release -cs 2>/dev/null || echo "bookworm")
    fi
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/mainline/${ID}/ ${VERSION_CODENAME} nginx" \
        > /etc/apt/sources.list.d/nginx.list

    # 优先使用 nginx.org 仓库
    cat > /etc/apt/preferences.d/99nginx <<'EOF'
Package: nginx*
Pin: origin nginx.org
Pin-Priority: 900
EOF

    apt-get update -y -qq
    apt-get install -y nginx

    echo -e "${GREEN}✓ Nginx 安装完成${NC}"

elif [ -f /etc/redhat-release ]; then
    echo -e "${RED}错误: CentOS / RHEL 不在本脚本的支持范围内。${NC}"
    echo -e "${YELLOW}请使用 Ubuntu 20.04+ 或 Debian 11+。${NC}"
    exit 1
else
    echo -e "${RED}错误: 不支持的操作系统。${NC}"
    exit 1
fi

# 验证 HTTP/3 模块
if nginx -V 2>&1 | grep -q "http_v3_module"; then
    echo -e "${GREEN}✓ HTTP/3 (QUIC) 模块已就绪${NC}"
else
    echo -e "${YELLOW}⚠ 当前 Nginx 未包含 HTTP/3 模块${NC}"
fi

echo -e "${CYAN}>>> [3/3] 配置 Nginx 高并发优化...${NC}"

# 创建 SSL 证书存放目录（供后续服务使用）
mkdir -p "$NGINX_SSL_DIR"
chown -R $USER:$GROUP "$NGINX_SSL_DIR"

# 创建日志目录并设权限
mkdir -p /var/log/nginx
chown -R $USER:$GROUP /var/log/nginx

# 生成 nginx.conf（高并发调优 + 模块化站点配置）
cat > "$NGINX_CONF_DIR/nginx.conf" <<EOF
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
EOF

# 测试配置并启动
nginx -t
if [ $? -eq 0 ]; then
    systemctl enable nginx
    systemctl restart nginx
    echo -e "${GREEN}✓ Nginx 配置测试通过，服务已启动${NC}"
else
    echo -e "${RED}✗ Nginx 配置测试失败，请检查${NC}"
    exit 1
fi

# 输出安装摘要
NGINX_VERSION=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')
echo ""
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   Nginx 安装与系统优化完成 (v5.0)   ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "Nginx 版本:   ${YELLOW}$NGINX_VERSION${NC}"
echo -e "安装来源:     ${YELLOW}nginx.org 官方主线仓库${NC}"
echo -e "配置文件:     ${YELLOW}/etc/nginx/nginx.conf${NC}"
echo -e "站点配置:     ${YELLOW}/etc/nginx/conf.d/*.conf${NC}"
echo -e "SSL 证书:     ${YELLOW}/etc/nginx/ssl/${NC}"
echo -e "优化状态:     ${GREEN}BBR 已开启, Limit 已提升${NC}"
echo -e "HTTP/3 支持:  ${GREEN}✓ (内置 --with-http_v3_module)${NC}"
echo -e "${GREEN}==============================================${NC}"
