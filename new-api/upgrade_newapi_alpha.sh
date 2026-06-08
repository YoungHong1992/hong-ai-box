#!/bin/bash

################################################################################
#
# New-API Docker Alpha 版本升级脚本
# 版本: v3.5.0
#
# 功能说明：
#   1. 自动从 GitHub API 获取最新的 alpha 版本号
#   2. 备份当前配置
#   3. 拉取指定 alpha 版本镜像
#   4. 更新 docker-compose.yml 中的镜像标签
#   5. 重建服务容器（数据自动保留）
#
# 用法:
#   ./upgrade_newapi_alpha.sh        # 升级
#   ./upgrade_newapi_alpha.sh -h     # 显示帮助
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "New-API Alpha 升级脚本 v${COMMON_VERSION}"
            echo "用法: ./upgrade_newapi_alpha.sh"
            exit 0
            ;;
    esac
done

# ==================== 全局配置 ====================
DOCKER_ROOT="/opt/docker-services"
SERVICE_DIR="$DOCKER_ROOT/new-api"
COMPOSE_FILE="$SERVICE_DIR/docker-compose.yml"
BACKUP_DIR="$SERVICE_DIR/backups"
GITHUB_API="https://api.github.com/repos/QuantumNous/new-api/releases"
DOCKER_IMAGE="calciumion/new-api"

# ==================== 环境检查 ====================
check_root
setup_logging "newapi-alpha-upgrade"

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

# ==================== 欢迎 ====================
clear
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}   New-API Alpha 版本升级程序 v${COMMON_VERSION}${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ==================== 获取当前版本 ====================
log_step "[1/6] 检测当前配置..."

cd "$SERVICE_DIR"

CURRENT_IMAGE_TAG=$(grep -E "^\s+image:\s+calciumion/new-api" "$COMPOSE_FILE" | sed 's/.*image:\s*//' | tr -d '[:space:]' || echo "${DOCKER_IMAGE}:latest")
log_info "当前镜像: ${YELLOW}$CURRENT_IMAGE_TAG${NC}"

CURRENT_IMAGE_ID=$(docker images --format "{{.ID}}" "$CURRENT_IMAGE_TAG" 2>/dev/null | head -1 || echo "")
if [ -n "$CURRENT_IMAGE_ID" ]; then
    CURRENT_CREATED=$(docker images --format "{{.CreatedAt}}" "$CURRENT_IMAGE_TAG" 2>/dev/null | head -1 || echo "")
    log_info "镜像 ID: ${CURRENT_IMAGE_ID:0:12}"
    [ -n "$CURRENT_CREATED" ] && log_info "创建时间: $CURRENT_CREATED"
fi

echo ""
echo -e "${YELLOW}⚠️  Alpha 版本包含最新功能，但可能不稳定。${NC}"
echo ""

echo -e "${CYAN}请选择升级方式:${NC}"
echo "  1) 自动升级到最新 Alpha 版本"
echo "  2) 查看可用的 Alpha 版本列表"
echo "  3) 手动输入版本号"
echo "  4) 回滚到稳定版 (latest)"
read -r -p "请选择 [1-4]: " -n 1 -r CHOICE
echo ""

# ==================== 版本选择 ====================
case $CHOICE in
    1)
        log_step "[2/6] 获取最新 Alpha 版本..."
        LATEST_ALPHA=$(curl -s --connect-timeout 15 "$GITHUB_API" | grep -oP '"tag_name":\s*"v[0-9.]+-alpha\.[0-9]+"' | head -1 | grep -oP 'v[0-9.]+-alpha\.[0-9]+' || echo "")
        if [ -z "$LATEST_ALPHA" ]; then
            log_error "无法获取最新 Alpha 版本信息"
            exit 1
        fi
        TARGET_VERSION="$LATEST_ALPHA"
        log_success "最新 Alpha 版本: ${GREEN}$TARGET_VERSION${NC}"
        ;;
    2)
        log_step "[2/6] 获取可用版本列表..."
        echo ""
        echo -e "${CYAN}===== 最近发布的 Alpha 版本 =====${NC}"
        curl -s --connect-timeout 15 "$GITHUB_API" | grep -oP '"tag_name":\s*"v[0-9.]+-(alpha|beta)\.[0-9]+"' | head -10 | while read -r line; do
            VERSION=$(echo "$line" | grep -oP 'v[0-9.]+-(alpha|beta)\.[0-9]+' || echo "")
            echo -e "  - ${GREEN}$VERSION${NC}"
        done
        echo ""
        read -r -p "请输入要安装的版本号 (例如 v0.10.6-alpha.2): " TARGET_VERSION
        [ -z "$TARGET_VERSION" ] && { log_error "版本号不能为空"; exit 1; }
        ;;
    3)
        log_step "[2/6] 手动输入版本号..."
        read -r -p "请输入版本号 (例如 v0.10.6-alpha.2): " TARGET_VERSION
        [ -z "$TARGET_VERSION" ] && { log_error "版本号不能为空"; exit 1; }
        ;;
    4)
        log_step "[2/6] 准备回滚到稳定版..."
        TARGET_VERSION="latest"
        log_warning "将回滚到稳定版 (latest)"
        ;;
    *)
        log_error "无效选择"
        exit 1
        ;;
esac

TARGET_IMAGE="${DOCKER_IMAGE}:${TARGET_VERSION}"

echo ""
if ! confirm "是否继续升级到 $TARGET_IMAGE ?"; then
    log_info "升级已取消。"
    exit 0
fi

# ==================== 备份 ====================
log_step "[3/6] 备份当前配置..."

mkdir -p "$BACKUP_DIR"

VERSION_BACKUP="$BACKUP_DIR/docker-compose_before_${TARGET_VERSION//\//_}_$(date +%Y%m%d_%H%M%S).yml"
cp "$COMPOSE_FILE" "$VERSION_BACKUP"
log_success "版本备份: $VERSION_BACKUP"

# ==================== 更新 compose 文件 ====================
log_step "[4/6] 更新 docker-compose.yml..."

sed -i "s|image:.*calciumion/new-api.*|image: ${TARGET_IMAGE}|g" "$COMPOSE_FILE"
log_success "镜像标签已更新为: ${GREEN}$TARGET_IMAGE${NC}"

# ==================== 拉取镜像 ====================
log_step "[5/6] 拉取新镜像..."

log_info "正在拉取 ${TARGET_IMAGE}..."

if docker pull "$TARGET_IMAGE" 2>&1; then
    log_success "镜像拉取完成"
    NEW_IMAGE_ID=$(docker images --format "{{.ID}}" "$TARGET_IMAGE" 2>/dev/null | head -1 || echo "")
    NEW_CREATED=$(docker images --format "{{.CreatedAt}}" "$TARGET_IMAGE" 2>/dev/null | head -1 || echo "")
    log_info "新镜像 ID: ${GREEN}${NEW_IMAGE_ID:0:12}${NC}"
    [ -n "$NEW_CREATED" ] && log_info "创建时间: $NEW_CREATED"
else
    log_error "镜像拉取失败"
    cp "$VERSION_BACKUP" "$COMPOSE_FILE"
    log_warning "配置文件已回滚"
    exit 1
fi

# ==================== 重建服务 ====================
log_step "[6/6] 重建服务容器..."

log_info "正在使用新镜像重建容器..."

if $COMPOSE_CMD down && $COMPOSE_CMD up -d; then
    log_success "容器重建成功"

    log_info "等待服务启动..."
    wait_for_healthy "$COMPOSE_CMD" "$SERVICE_DIR" 60 5 "new-api"

    if $COMPOSE_CMD ps 2>/dev/null | grep -q "Up"; then
        log_success "服务运行正常"
    else
        log_error "服务启动失败，正在回滚..."
        cp "$VERSION_BACKUP" "$COMPOSE_FILE"
        $COMPOSE_CMD down 2>/dev/null || true
        $COMPOSE_CMD up -d
        log_warning "已回滚到旧版本"
        exit 1
    fi
else
    log_error "容器重建失败"
    cp "$VERSION_BACKUP" "$COMPOSE_FILE"
    log_warning "配置文件已回滚"
    exit 1
fi

# ==================== 清理 ====================
REMOVED_IMAGES=$(docker image prune -f 2>&1 | grep "Total reclaimed space" || echo "")
[ -n "$REMOVED_IMAGES" ] && log_success "清理完成" && echo "$REMOVED_IMAGES"

# ==================== 完成 ====================
clear
echo -e "${GREEN}"
echo "================================================"
echo "       New-API Alpha 升级完成！(v${COMMON_VERSION})"
echo "================================================"
echo -e "${NC}"
echo -e "原版本: ${YELLOW}$CURRENT_IMAGE_TAG${NC}"
echo -e "新版本: ${GREEN}$TARGET_IMAGE${NC}"
echo ""
$COMPOSE_CMD ps 2>/dev/null || true
echo ""
echo -e "回滚方法: cp $VERSION_BACKUP $COMPOSE_FILE && cd $SERVICE_DIR && $COMPOSE_CMD down && $COMPOSE_CMD up -d"
echo ""
log_success "日志已保存: $DEPLOY_LOG_FILE"
