#!/bin/bash

################################################################################
#
# New-API Docker 卸载脚本
# 版本: v4.0.0
#
# 功能说明：
#   1. 停止并删除所有 New-API 容器
#   2. 删除 Docker 数据卷（可选备份）
#   3. 删除配置文件和目录
#   4. 删除 Nginx 配置
#   5. 删除 SSL 证书（可选）
#   6. 清理共享网络（如无其他容器使用）
#
# 用法:
#   ./uninstall_newapi_docker.sh       # 交互式卸载
#   ./uninstall_newapi_docker.sh -h    # 显示帮助
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "New-API Docker 卸载脚本 v${COMMON_VERSION}"
            echo "用法: ./uninstall_newapi_docker.sh"
            exit 0
            ;;
    esac
done

# ==================== 全局配置 ====================
SERVICE_DIR="/opt/docker-services/new-api"
BACKUP_DIR="/backup/newapi-uninstall-$(date +%Y%m%d_%H%M%S)"
DOCKER_NETWORK="ai-services"
DELETE_SSL=""
DELETE_VOLUMES=""

# ==================== 环境检查 ====================
check_root
setup_logging "newapi-uninstall"

COMPOSE_CMD=$(detect_compose_cmd)
if [ -z "$COMPOSE_CMD" ]; then
    log_error "未检测到 docker-compose。"
    exit 1
fi

if [ ! -d "$SERVICE_DIR" ]; then
    log_error "未检测到 New-API 安装目录: $SERVICE_DIR"
    exit 1
fi

# ==================== 欢迎界面 ====================
clear 2>/dev/null || true
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}   New-API Docker 卸载程序 v${COMMON_VERSION}${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}⚠️  警告：此操作将删除以下内容${NC}"
echo ""
echo "  • 所有 New-API 容器 (new-api, newapi-postgres, newapi-redis)"
echo "  • 所有数据库数据 (PostgreSQL/MySQL)"
echo "  • 所有 Redis 缓存数据"
echo "  • 配置文件和日志"
echo "  • Nginx 配置文件"
echo "  • SSL 证书（可选）"
echo ""
echo -e "${GREEN}✓ 不会影响:${NC} Nginx 主程序 / 其他 Docker 服务 / 其他服务配置"
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -r -p "是否继续卸载 New-API？(yes/NO): " CONFIRM

if [[ ! "$CONFIRM" == "yes" ]]; then
    log_info "卸载已取消。"
    exit 0
fi

# ==================== 检测当前状态 ====================
log_step "[1/7] 检测当前服务状态..."

cd "$SERVICE_DIR"

NGINX_CONF=$(find /etc/nginx/conf.d/ -maxdepth 1 -name "*.conf" -exec grep -l "NEW-API-START" {} \; 2>/dev/null | head -1 || echo "")
DOMAIN=""
if [ -n "$NGINX_CONF" ]; then
    DOMAIN=$(grep "server_name" "$NGINX_CONF" 2>/dev/null | head -1 | awk '{print $2}' | sed 's/;//g' || echo "")
fi

if [ -z "$DOMAIN" ]; then
    DOMAIN="unknown"
    log_warning "未检测到域名配置"
else
    log_info "检测到域名: $DOMAIN"
fi

RUNNING_CONTAINERS=$($COMPOSE_CMD ps -q 2>/dev/null | wc -l || echo "0")
if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
    log_info "检测到 $RUNNING_CONTAINERS 个运行中的容器"
    $COMPOSE_CMD ps 2>/dev/null || true
fi

echo ""

# ==================== 备份数据 ====================
log_step "[2/7] 数据备份..."

read -r -p "是否备份数据库和配置？(Y/n): " -n 1 -r BACKUP_CHOICE
echo ""

if [[ ! "$BACKUP_CHOICE" =~ ^[Nn]$ ]]; then
    log_info "正在备份数据到: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    [ -f "$SERVICE_DIR/docker-compose.yml" ] && cp "$SERVICE_DIR/docker-compose.yml" "$BACKUP_DIR/" && log_success "已备份 docker-compose.yml"
    [ -f "$SERVICE_DIR/newapi_info.txt" ] && cp "$SERVICE_DIR/newapi_info.txt" "$BACKUP_DIR/" && log_success "已备份 newapi_info.txt"

    if $COMPOSE_CMD ps 2>/dev/null | grep -q "Up"; then
        log_info "正在导出数据库..."
        if $COMPOSE_CMD ps 2>/dev/null | grep -q "postgres"; then
            if $COMPOSE_CMD exec -T postgres pg_dump -U newapi newapi > "$BACKUP_DIR/database_backup.sql" 2>/dev/null; then
                log_success "PostgreSQL 数据库已备份"
            else
                log_warning "数据库备份失败"
            fi
        elif $COMPOSE_CMD ps 2>/dev/null | grep -q "mysql"; then
            DB_PASSWORD=$(grep "MYSQL_PASSWORD\|MYSQL_ROOT_PASSWORD" "$SERVICE_DIR/docker-compose.yml" 2>/dev/null | head -1 | sed 's/.*: *//' || echo "")
            if $COMPOSE_CMD exec -T mysql mysqldump -u newapi -p"$DB_PASSWORD" newapi > "$BACKUP_DIR/database_backup.sql" 2>/dev/null; then
                log_success "MySQL 数据库已备份"
            else
                log_warning "数据库备份失败"
            fi
        fi
    fi

    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        tar -czf "${BACKUP_DIR}.tar.gz" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")" 2>/dev/null
        rm -rf "$BACKUP_DIR"
        log_success "备份已打包: ${BACKUP_DIR}.tar.gz"
    fi
else
    log_info "跳过数据备份"
fi

echo ""

# ==================== 停止并删除容器 ====================
log_step "[3/7] 停止并删除容器..."

cd "$SERVICE_DIR"

if [ -f docker-compose.yml ]; then
    log_info "正在停止容器..."
    $COMPOSE_CMD down 2>/dev/null || true

    read -r -p "是否删除数据卷（包含数据库数据）？(y/N): " -n 1 -r DELETE_VOLUMES
    echo ""

    if [[ "$DELETE_VOLUMES" =~ ^[Yy]$ ]]; then
        log_info "正在删除数据卷..."
        $COMPOSE_CMD down -v 2>/dev/null || true
        log_success "容器和数据卷已删除"
    else
        log_success "容器已删除（数据卷保留）"
    fi
fi

echo ""

# ==================== 删除配置 ====================
log_step "[4/7] 删除配置文件..."

if [ -d "$SERVICE_DIR" ]; then
    rm -rf "$SERVICE_DIR"
    log_success "服务目录已删除"
fi

echo ""

# ==================== 删除 Nginx 配置 ====================
log_step "[5/7] 删除 Nginx 配置..."

NGINX_CONF=$(find /etc/nginx/conf.d/ -maxdepth 1 -name "*.conf" -exec grep -l "NEW-API-START" {} \; 2>/dev/null | head -1 || echo "")

if [ -n "$NGINX_CONF" ] && [ -f "$NGINX_CONF" ]; then
    rm -f "$NGINX_CONF"
    log_success "Nginx 配置已删除"
    if systemctl is-active --quiet nginx 2>/dev/null; then
        systemctl reload nginx || true
    fi
fi

echo ""

# ==================== 删除 SSL ====================
log_step "[6/7] 删除 SSL 证书..."

if [ "$DOMAIN" != "unknown" ]; then
    SSL_CERT_DIR="/etc/nginx/ssl/$DOMAIN"
    if [ -d "$SSL_CERT_DIR" ]; then
        read -r -p "是否删除 SSL 证书？($DOMAIN) (y/N): " -n 1 -r DELETE_SSL
        echo ""
        if [[ "$DELETE_SSL" =~ ^[Yy]$ ]]; then
            rm -rf "$SSL_CERT_DIR"
            if [ -f ~/.acme.sh/acme.sh ]; then
                ~/.acme.sh/acme.sh --remove -d "$DOMAIN" --ecc 2>/dev/null || true
            fi
            log_success "SSL 证书已删除"
        fi
    fi
fi

echo ""

# ==================== 清理网络 ====================
log_step "[7/7] 清理共享网络..."

if docker network ls 2>/dev/null | grep -q "$DOCKER_NETWORK"; then
    NETWORK_CONTAINERS=$(docker network inspect "$DOCKER_NETWORK" -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
    if [ -z "$NETWORK_CONTAINERS" ]; then
        read -r -p "是否删除共享网络 $DOCKER_NETWORK？(y/N): " -n 1 -r DELETE_NET
        echo ""
        if [[ "$DELETE_NET" =~ ^[Yy]$ ]]; then
            docker network rm "$DOCKER_NETWORK" 2>/dev/null || true
            log_success "共享网络已删除"
        fi
    else
        log_info "共享网络 $DOCKER_NETWORK 中还有其他容器，已保留"
    fi
fi

echo ""

# ==================== 完成 ====================
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}       New-API 卸载完成！${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${CYAN}保留:${NC} Docker 主程序 / Nginx 主程序 / 其他服务"
echo ""
log_success "日志已保存: $DEPLOY_LOG_FILE"
