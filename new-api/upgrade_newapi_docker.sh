#!/bin/bash

################################################################################
#
# New-API Docker 升级脚本
# 版本: v3.5.0
#
# 功能说明：
#   1. 检测当前 New-API Docker 服务
#   2. 备份当前配置
#   3. 强制拉取最新镜像（不使用缓存）
#   4. 重建服务容器（数据自动保留）
#   5. 清理旧镜像
#
# 用法:
#   ./upgrade_newapi_docker.sh       # 升级
#   ./upgrade_newapi_docker.sh -h    # 显示帮助
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "New-API Docker 升级脚本 v${COMMON_VERSION}"
            echo "用法: ./upgrade_newapi_docker.sh"
            exit 0
            ;;
    esac
done

# ==================== 全局配置 ====================
DOCKER_ROOT="/opt/docker-services"
SERVICE_DIR="$DOCKER_ROOT/new-api"
COMPOSE_FILE="$SERVICE_DIR/docker-compose.yml"

# ==================== 环境检查 ====================
check_root
setup_logging "newapi-upgrade"

if [ ! -d "$SERVICE_DIR" ]; then
    log_error "未检测到 New-API 安装目录: $SERVICE_DIR"
    exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "未检测到 docker-compose.yml 文件"
    exit 1
fi

COMPOSE_CMD=$(detect_compose_cmd)
if [ -z "$COMPOSE_CMD" ]; then
    log_error "未检测到 docker-compose。"
    exit 1
fi

# ==================== 检测当前状态 ====================
clear
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}   New-API Docker 升级程序 v${COMMON_VERSION}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_step "[1/5] 检测当前服务状态..."

cd "$SERVICE_DIR"

IMAGE_NAME=$(grep -E "^\s+image:\s*calciumion/new-api" "$COMPOSE_FILE" | awk '{print $2}' | tr -d '[:space:]' || echo "")
[ -z "$IMAGE_NAME" ] && IMAGE_NAME="calciumion/new-api:latest"

CURRENT_IMAGE=$(docker images --format "{{.ID}}" "$IMAGE_NAME" 2>/dev/null | head -1 || echo "")
if [ -z "$CURRENT_IMAGE" ]; then
    log_warning "无法获取当前镜像版本"
else
    IMAGE_CREATED=$(docker images --format "{{.CreatedAt}}" "$IMAGE_NAME" 2>/dev/null | head -1 || echo "")
    log_info "当前镜像 ID: ${CURRENT_IMAGE:0:12}"
    [ -n "$IMAGE_CREATED" ] && log_info "镜像创建时间: $IMAGE_CREATED"
fi

if $COMPOSE_CMD ps 2>/dev/null | grep -q "Up"; then
    log_info "服务状态: 运行中"
else
    log_warning "服务状态: 已停止"
fi

echo ""
if ! confirm "是否继续升级？"; then
    log_info "升级已取消。"
    exit 0
fi

# ==================== 备份 ====================
log_step "[2/5] 备份当前配置..."

BACKUP_DIR="$SERVICE_DIR/backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/docker-compose_$(date +%Y%m%d_%H%M%S).yml"
cp "$COMPOSE_FILE" "$BACKUP_FILE"
log_success "配置已备份: $BACKUP_FILE"

# ==================== 拉取镜像 ====================
log_step "[3/5] 拉取最新镜像..."

log_info "正在检查更新..."

if docker pull "$IMAGE_NAME" 2>&1 | tee /tmp/pull_output.log; then
    log_success "镜像拉取完成"

    NEW_IMAGE=$(docker images --format "{{.ID}}" "$IMAGE_NAME" 2>/dev/null | head -1 || echo "")

    if [ "$CURRENT_IMAGE" = "$NEW_IMAGE" ]; then
        log_info "已是最新版本，无需升级"
        echo ""
        if confirm "是否重启服务？"; then
            $COMPOSE_CMD restart new-api
            log_success "服务已重启"
        fi
        exit 0
    else
        log_success "检测到新版本"
        log_info "旧镜像 ID: ${YELLOW}${CURRENT_IMAGE:0:12}${NC}"
        log_info "新镜像 ID: ${GREEN}${NEW_IMAGE:0:12}${NC}"
    fi
else
    log_error "镜像拉取失败，请检查网络连接"
    exit 1
fi

# ==================== 重建服务 ====================
log_step "[4/5] 重启服务..."

log_info "正在使用新镜像重建容器..."

if $COMPOSE_CMD down && $COMPOSE_CMD up -d; then
    log_success "容器重建成功"

    log_info "等待服务启动..."
    wait_for_healthy "$COMPOSE_CMD" "$SERVICE_DIR" 60 5 "new-api"

    if $COMPOSE_CMD ps 2>/dev/null | grep -q "Up"; then
        log_success "服务运行正常"
    else
        log_error "服务启动失败，正在回滚..."
        cp "$BACKUP_FILE" "$COMPOSE_FILE"
        $COMPOSE_CMD up -d
        log_warning "已回滚到旧版本"
        exit 1
    fi
else
    log_error "容器重建失败"
    exit 1
fi

# ==================== 清理 ====================
log_step "[5/5] 清理旧镜像..."

REMOVED_IMAGES=$(docker image prune -f 2>&1 | grep "Total reclaimed space" || echo "")
if [ -n "$REMOVED_IMAGES" ]; then
    log_success "清理完成"
    echo "$REMOVED_IMAGES"
else
    log_info "没有需要清理的镜像"
fi

# ==================== 完成 ====================
clear
echo -e "${GREEN}"
echo "================================================"
echo "       New-API 升级完成！(v${COMMON_VERSION})"
echo "================================================"
echo -e "${NC}"
echo -e "旧镜像: ${YELLOW}${CURRENT_IMAGE:0:12}${NC}"
echo -e "新镜像: ${GREEN}${NEW_IMAGE:0:12}${NC}"
echo ""
$COMPOSE_CMD ps
echo ""
echo -e "${CYAN}配置保留:${NC} ✓ 环境变量 / 数据库 / Redis / 备份: $BACKUP_FILE"
echo ""
log_success "日志已保存: $DEPLOY_LOG_FILE"
