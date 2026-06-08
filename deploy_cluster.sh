#!/bin/bash

################################################################################
#
# VPS 集群全流程部署引导脚本
# 版本: v3.5.0
#
# 功能说明：
#   按顺序引导用户选择并安装 VPS 集群各组件，自动处理依赖关系
#
# 使用方法：
#   chmod +x deploy_cluster.sh
#   ./deploy_cluster.sh             # 引导式部署
#   ./deploy_cluster.sh -h          # 显示帮助
#   ./deploy_cluster.sh --version   # 显示版本
#
# 依赖关系：
#   nginx     → 必选（所有服务的基础）
#   docker    → 推荐（Docker 容器服务的前置依赖）
#   其余服务  → 可选（独立服务）
#
################################################################################

set -euo pipefail

# ==================== 加载公共库 ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ==================== 帮助信息 ====================
show_help() {
    cat <<EOF
VPS 集群全流程部署引导工具 v${COMMON_VERSION}

用法:
  ./deploy_cluster.sh             # 引导式部署
  ./deploy_cluster.sh -h          # 显示此帮助
  ./deploy_cluster.sh --version   # 显示版本

部署顺序:
  1. Nginx (HTTP/3)    - 基础设施【必选】
  2. Docker            - 容器环境【推荐】
  3. CliproxyAPI       - 轻量 AI API 转发【可选】
  4. New-API           - AI 模型网关【可选】
  5. Pi 编程助手       - 终端 AI 工具【可选】

单独部署:
  cd nginx && ./install_nginx.sh
  cd docker && ./install_docker.sh
  cd new-api && ./install_newapi_docker.sh
  cd cliproxyapi && ./install_cliproxyapi_v2.sh
  cd pi-coding-agent && ./install_pi.sh
  cd science && ./setup.sh          # 网络工具（独立，需手动执行）

注意:
  - 需要 root 权限
  - Nginx 必须先安装
  - 域名模式需要 DNS 已解析
EOF
    exit 0
}

# ==================== 参数解析 ====================
for arg in "$@"; do
    case "$arg" in
        -h|--help)    show_help ;;
        --version)    echo "v${COMMON_VERSION}"; exit 0 ;;
        -*)           echo "未知参数: $arg"; echo "使用 -h 查看帮助"; exit 1 ;;
    esac
done

# ==================== 全局状态 ====================
INSTALLED_SERVICES=()
NGINX_INSTALLED=false
DOCKER_INSTALLED=false
NEWAPI_INSTALLED=false
CLIPROXYAPI_INSTALLED=false

# ==================== 引入 Docker 安装函数 ====================
DOCKER_INSTALLER="$SCRIPT_DIR/docker/install_docker.sh"
if [ -f "$DOCKER_INSTALLER" ]; then
    source "$DOCKER_INSTALLER"
else
    log_warning "未找到 Docker 安装脚本，Docker 相关功能将不可用。"
    ensure_docker() { log_error "Docker 安装脚本缺失"; return 1; }
fi

# ==================== 服务安装函数 ====================

install_nginx() {
    print_section "安装 Nginx (HTTP/3)"

    echo -e "${WHITE}功能说明:${NC}"
    echo "  • Nginx 来自 nginx.org 官方主线仓库，支持 HTTP/3 (QUIC)"
    echo "  • 自动开启 TCP BBR，优化系统内核参数"
    echo "  • 构建模块化配置结构 (conf.d/)，方便后续服务扩展"
    echo ""
    echo -e "${YELLOW}⚠️  这是所有后续服务的基础组件，必须安装！${NC}"
    echo ""

    if confirm "是否开始安装 Nginx？" "y"; then
        echo ""
        cd "$SCRIPT_DIR/nginx"
        chmod +x install_nginx.sh
        ./install_nginx.sh

        if [ $? -eq 0 ]; then
            NGINX_INSTALLED=true
            INSTALLED_SERVICES+=("Nginx (HTTP/3)")
            log_success "Nginx 安装成功！"
            echo ""
        else
            log_error "Nginx 安装失败，请检查错误信息。"
            exit 1
        fi
    else
        log_error "Nginx 是必选组件，无法跳过。"
        exit 1
    fi

    wait_key
}

install_docker() {
    print_section "安装 Docker 容器环境"

    echo -e "${WHITE}功能说明:${NC}"
    echo "  • Docker 是 New-API 等容器服务的运行环境"
    echo "  • 包含 Docker Engine 和 Docker Compose 插件"
    echo "  • 自动修复 apt 源问题，支持多种 Linux 发行版"
    echo ""

    if confirm "是否安装 Docker？" "y"; then
        echo ""

        if ensure_docker; then
            DOCKER_INSTALLED=true
            INSTALLED_SERVICES+=("Docker")
            log_success "Docker 环境就绪！"
            echo ""
        else
            log_warning "Docker 安装失败，后续 Docker 服务将无法安装。"
        fi
    else
        log_info "跳过 Docker 安装（后续 Docker 服务将无法安装）"
    fi

    wait_key
}

install_cliproxyapi() {
    print_section "安装 CliproxyAPI (AI API 转发服务)"

    echo -e "${WHITE}功能说明:${NC}"
    echo "  • 轻量级 AI API 转发代理，资源占用极低 (~50MB)"
    echo "  • 支持 OpenAI、Claude、Gemini 等主流 AI 模型 API"
    echo "  • 支持域名 / IP / HTTP 三种访问模式"
    echo "  • 适合低配 VPS（内存 < 1GB）"
    echo ""

    if confirm "是否安装 CliproxyAPI？"; then
        echo ""
        cd "$SCRIPT_DIR/cliproxyapi"
        chmod +x install_cliproxyapi_v2.sh
        ./install_cliproxyapi_v2.sh

        if [ $? -eq 0 ]; then
            CLIPROXYAPI_INSTALLED=true
            INSTALLED_SERVICES+=("CliproxyAPI")
            log_success "CliproxyAPI 安装成功！"
            echo ""
        else
            log_warning "CliproxyAPI 安装未完成"
        fi
    else
        log_info "跳过 CliproxyAPI 安装"
    fi

    wait_key
}

install_newapi() {
    print_section "安装 New-API (AI 模型网关)"

    echo -e "${WHITE}功能说明:${NC}"
    echo "  • 新一代大模型网关与 AI 资产管理系统"
    echo "  • 支持 OpenAI、Claude、Gemini、Azure 等多种模型聚合"
    echo "  • 提供用户管理、令牌分组、计费系统、数据看板"
    echo "  • 支持域名 / IP / HTTP 三种访问模式"
    echo ""
    echo -e "${YELLOW}资源需求: 推荐 ≥ 1GB 内存${NC}"
    echo ""

    if confirm "是否安装 New-API？"; then
        echo ""

        # 自动安装 Docker（如未安装）
        if ! command -v docker &> /dev/null; then
            log_info "未检测到 Docker，尝试自动安装..."
            if ensure_docker; then
                DOCKER_INSTALLED=true
                INSTALLED_SERVICES+=("Docker")
            else
                log_error "Docker 安装失败，无法继续安装 New-API"
                wait_key
                return
            fi
        fi

        cd "$SCRIPT_DIR/new-api"
        chmod +x install_newapi_docker.sh
        ./install_newapi_docker.sh

        if [ $? -eq 0 ]; then
            NEWAPI_INSTALLED=true
            INSTALLED_SERVICES+=("New-API")
            log_success "New-API 安装成功！"
            echo ""
            echo -e "${DIM}配置信息已保存到: /opt/docker-services/new-api/newapi_info.txt${NC}"
        else
            log_warning "New-API 安装未完成"
        fi
    else
        log_info "跳过 New-API 安装"
    fi

    wait_key
}

install_pi() {
    print_section "安装 Pi 终端编程助手"

    echo -e "${WHITE}功能说明:${NC}"
    echo "  • Pi 是一款极简终端 AI 编程助手"
    echo "  • 支持 Anthropic、OpenAI、Gemini、DeepSeek 等 AI 提供商"
    echo "  • 通过 API Key 连接远程 AI 服务，无需本地 GPU"
    echo ""

    if confirm "是否安装 Pi 编程助手？"; then
        echo ""
        cd "$SCRIPT_DIR/pi-coding-agent"
        chmod +x install_pi.sh
        ./install_pi.sh --no-prompt

        if [ $? -eq 0 ]; then
            INSTALLED_SERVICES+=("Pi 编程助手")
            log_success "Pi 安装成功！"
            echo ""
        else
            log_warning "Pi 安装未完成"
        fi
    else
        log_info "跳过 Pi 安装"
    fi

    wait_key
}

# ==================== 总结 ====================

print_summary() {
    print_header "部署完成总结"

    if [ ${#INSTALLED_SERVICES[@]} -eq 0 ]; then
        echo -e "${YELLOW}本次未安装任何服务。${NC}"
    else
        echo -e "${GREEN}本次已安装以下服务:${NC}"
        echo ""
        for service in "${INSTALLED_SERVICES[@]}"; do
            echo -e "  ${GREEN}✓${NC} $service"
        done
    fi

    echo ""
    print_divider
    echo ""
    echo -e "${WHITE}常用管理命令:${NC}"
    echo ""
    echo "  Nginx:"
    echo "    systemctl status nginx  |  nginx -t  |  systemctl reload nginx"
    echo ""

    if [ "$NEWAPI_INSTALLED" = true ]; then
        echo "  New-API:"
        echo "    cd /opt/docker-services/new-api && docker compose ps"
        echo "    docker compose logs -f new-api"
        echo ""
    fi

    if [ "$CLIPROXYAPI_INSTALLED" = true ]; then
        echo "  CliproxyAPI:"
        echo "    systemctl status cliproxyapi"
        echo "    journalctl -u cliproxyapi -f"
        echo ""
    fi

    echo "  Pi 编程助手:"
    echo "    pi --help  |  pi -p \"你的问题\""
    echo ""

    print_divider
    echo ""
    echo -e "${CYAN}感谢使用 VPS 集群部署工具 v${COMMON_VERSION}！${NC}"
    echo -e "${DIM}日志文件: $DEPLOY_LOG_FILE${NC}"
    echo ""
}

# ==================== 主流程 ====================

main() {
    check_root
    setup_logging "deploy-cluster"

    print_header "VPS 集群部署引导工具"

    echo -e "${WHITE}欢迎使用 VPS 集群全流程部署引导工具！${NC}"
    echo ""
    echo "本工具将引导您按顺序部署 VPS 集群的各个组件。"
    echo ""
    echo -e "${CYAN}可用组件:${NC}"
    echo "  1. Nginx (HTTP/3)          - 基础设施【必选】"
    echo "  2. Docker 容器环境        - 容器服务前置依赖【推荐】"
    echo "  3. CliproxyAPI            - 轻量 AI API 转发【可选】"
    echo "  4. New-API                - AI 模型网关【可选】"
    echo "  5. Pi 编程助手            - 终端 AI 工具【可选】"
    echo ""
    echo -e "${YELLOW}依赖关系:${NC}"
    echo "  • Nginx 是所有服务的基础，必须首先安装"
    echo "  • Docker 是 New-API 的前置依赖"
    echo "  • CliproxyAPI 和 Pi 可独立安装"
    echo ""

    if ! confirm "是否开始部署？" "y"; then
        echo ""
        log_info "已取消部署。"
        exit 0
    fi

    # 步骤 1: Nginx（必选）
    install_nginx

    # 步骤 2: Docker（推荐）
    install_docker

    # 步骤 3: 可选服务
    print_header "可选服务安装"
    echo -e "${WHITE}接下来，请选择要安装的可选服务。${NC}"
    echo ""
    echo "  • CliproxyAPI（轻量 AI API 转发，适合低配 VPS）"
    echo "  • New-API（完整 AI 网关，功能丰富）"
    echo "  • Pi 编程助手（终端 AI 工具）"
    echo ""
    wait_key

    install_cliproxyapi
    install_newapi
    install_pi

    # 总结
    print_summary
}

# ==================== 执行 ====================
main "$@"
