#!/bin/bash
# shellcheck shell=bash
################################################################################
#
# 洪哥的 AI 工具箱 — 一键部署脚本
# 版本: v4.0.0
#
# 功能说明：
#   引导用户选择并安装 AI 工具集群，自动处理依赖关系
#
# 使用方法：
#   chmod +x install.sh
#   sudo ./install.sh              # 交互式部署（推荐）
#   ./install.sh -h                # 显示帮助
#   ./install.sh --version         # 显示版本
#
# 远程安装：
#   curl -fsSL https://.../install.sh | sudo bash
#
# 可用组件：
#   1. Nginx (HTTP/3)     - 高性能 Web 服务器 + 反向代理
#   2. Docker 容器环境    - Docker Engine + Compose 插件
#   3. CliproxyAPI        - 轻量 AI API 转发代理 (~50MB)
#   4. New-API            - AI 模型网关与资产管理系统
#   5. Pi 编程助手       - 终端 AI 编程助手
#   6. Science            - VLESS + XTLS-Vision + Reality
#
################################################################################

set -euo pipefail

# ==================== 路径解析 ====================
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$INSTALL_DIR/scripts"

# ==================== 加载公共库 ====================
if [ -f "$SCRIPTS_DIR/lib/common.sh" ]; then
    source "$SCRIPTS_DIR/lib/common.sh"
else
    echo -e "\033[0;31m[ERROR]\033[0m 未找到公共库，请确保脚本位于完整仓库中。" >&2
    exit 1
fi

# ==================== 版本 ====================
readonly VERSION="4.0.0"

# ==================== 帮助信息 ====================
show_help() {
    cat <<EOF
洪哥的 AI 工具箱 v${VERSION} — 一键部署脚本

用法:
  ./install.sh              # 交互式部署
  ./install.sh -h           # 显示此帮助
  ./install.sh --version    # 显示版本

部署流程:
  1. 检测当前已安装的服务
  2. 选择要安装的服务
  3. 配置访问模式（域名/IP/HTTP）
  4. 逐服务填写配置（如需要）
  5. 确认并开始安装

可用组件:
  Nginx (HTTP/3)           高性能 Web 服务器 + 反向代理
  Docker 容器环境          Docker Engine + Compose 插件
  CliproxyAPI              轻量 AI API 转发代理 (~50MB 内存)
  New-API                  AI 模型网关与资产管理系统 (需 ≥1GB 内存)
  Pi 编程助手              终端 AI 编程助手 (500MB 磁盘)
  Science                  VLESS + XTLS-Vision + Reality

注意:
  - 需要 root 权限
  - 域名模式需要 DNS 已解析
  - 安装日志保存在 /var/log/vps-deploy/
EOF
    exit 0
}

# ==================== 参数解析 ====================
for arg in "$@"; do
    case "$arg" in
        -h|--help)    show_help ;;
        --version)    echo "v${VERSION}"; exit 0 ;;
        -*)           echo "未知参数: $arg"; echo "使用 -h 查看帮助"; exit 1 ;;
    esac
done

# ==================== 全局状态 ====================

# Service IDs
readonly SVC_NGINX="nginx"
readonly SVC_DOCKER="docker"
readonly SVC_CLIPROXY="cliproxyapi"
readonly SVC_NEWAPI="newapi"
readonly SVC_PI="pi"
readonly SVC_SCIENCE="science"

# Service definitions (order = dependency order)
declare -A SVC_NAME SVC_DESC SVC_HINT SVC_SCRIPT SVC_DEPENDS
SVC_NAME[$SVC_NGINX]="Nginx (HTTP/3)"
SVC_DESC[$SVC_NGINX]="Nginx 官方主线仓库安装，支持 HTTP/3 (QUIC)、TCP BBR 优化"
SVC_HINT[$SVC_NGINX]="512MB 内存"
SVC_SCRIPT[$SVC_NGINX]="$SCRIPTS_DIR/nginx/install_nginx.sh"
SVC_DEPENDS[$SVC_NGINX]=""

SVC_NAME[$SVC_DOCKER]="Docker 容器环境"
SVC_DESC[$SVC_DOCKER]="Docker Engine + Docker Compose 插件"
SVC_HINT[$SVC_DOCKER]="无额外需求"
SVC_SCRIPT[$SVC_DOCKER]="$SCRIPTS_DIR/docker/install_docker.sh"
SVC_DEPENDS[$SVC_DOCKER]=""

SVC_NAME[$SVC_CLIPROXY]="CliproxyAPI"
SVC_DESC[$SVC_CLIPROXY]="轻量 AI API 转发代理 (~50MB)，支持 OpenAI/Claude/Gemini"
SVC_HINT[$SVC_CLIPROXY]="256MB 内存"
SVC_SCRIPT[$SVC_CLIPROXY]="$SCRIPTS_DIR/cliproxyapi/install_cliproxyapi_v2.sh"
SVC_DEPENDS[$SVC_CLIPROXY]="$SVC_NGINX"

SVC_NAME[$SVC_NEWAPI]="New-API"
SVC_DESC[$SVC_NEWAPI]="AI 模型网关与资产管理系统，支持多模型聚合、计费、用户管理"
SVC_HINT[$SVC_NEWAPI]="≥ 1GB 内存"
SVC_SCRIPT[$SVC_NEWAPI]="$SCRIPTS_DIR/new-api/install_newapi_docker.sh"
SVC_DEPENDS[$SVC_NEWAPI]="$SVC_NGINX $SVC_DOCKER"

SVC_NAME[$SVC_PI]="Pi 编程助手"
SVC_DESC[$SVC_PI]="极简终端 AI 编程助手，支持 Anthropic/OpenAI/Gemini/DeepSeek"
SVC_HINT[$SVC_PI]="500MB 磁盘"
SVC_SCRIPT[$SVC_PI]="$SCRIPTS_DIR/pi-coding-agent/install_pi.sh"
SVC_DEPENDS[$SVC_PI]=""

SVC_NAME[$SVC_SCIENCE]="Science"
SVC_DESC[$SVC_SCIENCE]="VLESS + XTLS-Vision + Reality，无需域名和 SSL"
SVC_HINT[$SVC_SCIENCE]="极低"
SVC_SCRIPT[$SVC_SCIENCE]="$SCRIPTS_DIR/science/install_science.sh"
SVC_DEPENDS[$SVC_SCIENCE]=""

# Ordered list for display
readonly ALL_SERVICES=(
    "$SVC_NGINX" "$SVC_DOCKER" "$SVC_CLIPROXY"
    "$SVC_NEWAPI" "$SVC_PI" "$SVC_SCIENCE"
)

# Runtime state
declare -A ALREADY_INSTALLED   # true if already present on system
declare -A TO_INSTALL          # true if user selected to install
INSTALL_ORDER=()               # resolved dependency order
INSTALL_RESULTS=()             # for summary

# User config
ACCESS_MODE=""
DOMAIN=""
ADMIN_PASSWORD=""              # cliproxyapi
DB_TYPE="postgresql"           # newapi
DEST_SNI="www.microsoft.com"   # science
REALITY_PORT="8443"            # science

# ==================== 服务检测 ====================

detect_installed_services() {
    echo ""
    echo -e "${CYAN}正在检测已安装的服务...${NC}"

    for svc in "${ALL_SERVICES[@]}"; do
        case "$svc" in
            "$SVC_NGINX")
                if command -v nginx &>/dev/null || [ -f /usr/sbin/nginx ]; then
                    ALREADY_INSTALLED[$svc]=true
                fi
                ;;
            "$SVC_DOCKER")
                if command -v docker &>/dev/null; then
                    ALREADY_INSTALLED[$svc]=true
                fi
                ;;
            "$SVC_CLIPROXY")
                if [ -f /usr/local/bin/cliproxyapi ] || [ -f /etc/systemd/system/cliproxyapi.service ]; then
                    ALREADY_INSTALLED[$svc]=true
                fi
                ;;
            "$SVC_NEWAPI")
                if [ -f /opt/docker-services/new-api/docker-compose.yml ]; then
                    ALREADY_INSTALLED[$svc]=true
                fi
                ;;
            "$SVC_PI")
                if command -v pi &>/dev/null; then
                    ALREADY_INSTALLED[$svc]=true
                fi
                ;;
            "$SVC_SCIENCE")
                if command -v xray &>/dev/null || [ -f /usr/local/bin/xray ]; then
                    ALREADY_INSTALLED[$svc]=true
                fi
                ;;
        esac
    done
}

# ==================== 显示服务面板 ====================

show_service_panel() {
    clear
    print_header "洪哥的 AI 工具箱"

    echo -e "${WHITE}欢迎使用洪哥的 AI 工具箱部署脚本！${NC}"
    echo ""
    echo "本工具将引导您在云服务器上一键部署 AI 工具集群。"
    echo ""

    echo -e "${CYAN}─────────────────── 服务概览 ──────────────────${NC}"
    echo ""

    for svc in "${ALL_SERVICES[@]}"; do
        local name="${SVC_NAME[$svc]}"
        local hint="${SVC_HINT[$svc]}"
        local desc="${SVC_DESC[$svc]}"
        local status=""
        local padding=""

        if [ "${ALREADY_INSTALLED[$svc]:-}" = "true" ]; then
            status="${GREEN}✓ 已安装${NC}"
        else
            status="${DIM}○ 未安装${NC}"
        fi

        # Alignment: name 22 chars, hint 14 chars
        printf "  %-22s %-20s %-40s %b\n" \
            "${BOLD}$name${NC}" \
            "${DIM}$hint${NC}" \
            "$desc" \
            "$status"
    done

    echo ""
    echo -e "${CYAN}───────────────────────────────────────────────${NC}"
    echo ""
}

# ==================== 选择服务 ====================

select_services() {
    echo -e "${WHITE}请选择要安装的服务：${NC}"
    echo ""

    local i=1
    declare -A idx_to_svc

    # Show only uninstalled services
    for svc in "${ALL_SERVICES[@]}"; do
        if [ "${ALREADY_INSTALLED[$svc]:-}" = "true" ]; then
            continue
        fi
        idx_to_svc[$i]="$svc"
        echo -e "  ${GREEN}$i)${NC} ${SVC_NAME[$svc]}  ${DIM}— ${SVC_HINT[$svc]}${NC}"
        ((i++))
    done

    if [ "$i" -eq 1 ]; then
        echo -e "${GREEN}所有服务已安装，无需部署！${NC}"
        echo ""
        exit 0
    fi

    echo ""
    echo "  输入数字选择（多个用空格分隔，如: 1 3 5）"
    echo "  输入 all 全选"
    echo "  输入 q 退出"
    echo ""

    while true; do
        read -r -p "请选择 [1-$((i-1)) / all / q]: " raw

        case "$raw" in
            [Qq])  echo ""; log_info "已取消部署。"; exit 0 ;;
            all|ALL|a|A)
                for idx in "${!idx_to_svc[@]}"; do
                    TO_INSTALL[${idx_to_svc[$idx]}]=true
                done
                break
                ;;
            *)
                local valid=true
                for num in $raw; do
                    if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -ge "$i" ]; then
                        echo -e "${YELLOW}无效选项: $num${NC}" >&2
                        valid=false
                        break
                    fi
                done
                if [ "$valid" = true ] && [ -n "${raw// /}" ]; then
                    for num in $raw; do
                        TO_INSTALL[${idx_to_svc[$num]}]=true
                    done
                    break
                fi
                ;;
        esac
    done

    echo ""
}

# ==================== 依赖解析 ====================

resolve_deps() {
    INSTALL_ORDER=()
    local -A seen

    resolve_one() {
        local svc="$1"
        if [ "${seen[$svc]:-}" = "1" ]; then
            return
        fi
        seen[$svc]=1

        # Resolve deps first
        for dep in ${SVC_DEPENDS[$svc]}; do
            if [ -n "$dep" ]; then
                resolve_one "$dep"
            fi
        done

        INSTALL_ORDER+=("$svc")
    }

    for svc in "${ALL_SERVICES[@]}"; do
        if [ "${TO_INSTALL[$svc]:-}" = "true" ]; then
            resolve_one "$svc"
        fi
    done
}

# ==================== 是否需要访问模式配置 ====================

needs_access_mode() {
    for svc in "${INSTALL_ORDER[@]}"; do
        case "$svc" in
            "$SVC_NGINX") return 0 ;;
        esac
    done
    return 1
}

# ==================== 全局配置：访问模式 ====================

configure_access_mode() {
    echo ""
    echo -e "${CYAN}>>> 配置访问方式${NC}"
    echo ""
    echo "  1) 使用域名（推荐） — 自动申请 Let's Encrypt 免费证书"
    echo "  2) 使用 IP 地址       — 自签名证书，无需域名"
    echo "  3) 仅使用 HTTP       — 无 SSL 证书，仅限内网/开发环境"
    echo ""

    while true; do
        read -r -p "请选择 [1/2/3]: " choice
        case "$choice" in
            1) ACCESS_MODE="domain"; break ;;
            2) ACCESS_MODE="ip"; break ;;
            3) ACCESS_MODE="http"; break ;;
            *) echo -e "${YELLOW}无效选择，请重新输入${NC}" ;;
        esac
    done

    case "$ACCESS_MODE" in
        domain)
            echo ""
            while true; do
                read -r -p "请输入域名 (例如 api.example.com): " DOMAIN
                if validate_domain "$DOMAIN"; then
                    break
                fi
            done
            ;;
        ip|http)
            DOMAIN="$(detect_server_ip)"
            if [ -z "$DOMAIN" ]; then
                echo ""
                read -r -p "无法自动获取 IP，请手动输入: " DOMAIN
                [ -z "$DOMAIN" ] && { log_error "IP 不能为空。"; exit 1; }
            fi

            if [ "$ACCESS_MODE" = "http" ]; then
                echo ""
                echo -e "${YELLOW}⚠️  HTTP 模式警告：数据传输不加密，API Key 可能泄露${NC}"
                echo -e "${YELLOW}   仅建议在内网或开发环境使用${NC}"
            fi

            echo ""
            echo -e "服务器 IP: ${GREEN}$DOMAIN${NC}"
            read -r -p "确认使用此 IP？(Y/n): " confirm_ip
            case "$confirm_ip" in
                [Nn]) read -r -p "请输入 IP 地址: " DOMAIN; [ -z "$DOMAIN" ] && { log_error "IP 不能为空。"; exit 1; } ;;
            esac
            ;;
    esac
}

# ==================== 服务级配置 ====================

configure_service() {
    local svc="$1"

    case "$svc" in
        "$SVC_CLIPROXY")
            echo ""
            echo -e "${CYAN}>>> CliproxyAPI 管理面板密码${NC}"
            echo "  留空将自动生成随机密码"
            echo ""
            read -r -p "管理密码 (留空=自动生成): " ADMIN_PASSWORD
            if [ -n "$ADMIN_PASSWORD" ]; then
                echo -e "${GREEN}已设置自定义密码${NC}"
            else
                echo -e "${DIM}将在安装时自动生成${NC}"
            fi
            ;;
        "$SVC_NEWAPI")
            echo ""
            echo -e "${CYAN}>>> New-API 数据库类型${NC}"
            echo "  1) PostgreSQL（推荐）"
            echo "  2) MySQL"
            echo ""
            while true; do
                read -r -p "请选择 [1/2]: " db_choice
                case "$db_choice" in
                    1) DB_TYPE="postgresql"; break ;;
                    2) DB_TYPE="mysql"; break ;;
                    *) echo -e "${YELLOW}无效选择${NC}" ;;
                esac
            done
            ;;
        "$SVC_SCIENCE")
            echo ""
            echo -e "${CYAN}>>> Science 配置${NC}"
            echo ""
            read -r -p "伪装目标 SNI [www.microsoft.com]: " input_sni
            DEST_SNI="${input_sni:-www.microsoft.com}"
            read -r -p "监听端口 [8443]: " input_port
            REALITY_PORT="${input_port:-8443}"
            echo ""
            echo -e "  SNI: ${GREEN}$DEST_SNI${NC}  端口: ${GREEN}$REALITY_PORT${NC}"
            ;;
    esac
}

collect_service_configs() {
    for svc in "${INSTALL_ORDER[@]}"; do
        case "$svc" in
            "$SVC_CLIPROXY"|"$SVC_NEWAPI"|"$SVC_SCIENCE")
                configure_service "$svc"
                ;;
        esac
    done
}

# ==================== 确认总览 ====================

show_review() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            📋 配置总览               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    if needs_access_mode; then
        echo -e "${BOLD}全局配置:${NC}"
        case "$ACCESS_MODE" in
            domain) echo -e "  访问模式: ${GREEN}域名（Let's Encrypt）${NC}" ;;
            ip)     echo -e "  访问模式: ${GREEN}IP（自签名证书）${NC}" ;;
            http)   echo -e "  访问模式: ${GREEN}HTTP（无 SSL）${NC}" ;;
        esac
        echo -e "  域名/IP:  ${GREEN}$DOMAIN${NC}"
        echo ""
    fi

    echo -e "${BOLD}待安装服务 (${#INSTALL_ORDER[@]} 个):${NC}"
    echo ""

    for svc in "${INSTALL_ORDER[@]}"; do
        local line="  ✓ ${SVC_NAME[$svc]}"
        case "$svc" in
            "$SVC_CLIPROXY")
                if [ -n "$ADMIN_PASSWORD" ]; then
                    line="$line  (密码: 已设置)"
                else
                    line="$line  (密码: 自动生成)"
                fi
                ;;
            "$SVC_NEWAPI")
                local db_label="PostgreSQL"
                [ "$DB_TYPE" = "mysql" ] && db_label="MySQL"
                line="$line  (数据库: $db_label)"
                ;;
            "$SVC_SCIENCE")
                line="$line  (SNI: $DEST_SNI, 端口: $REALITY_PORT)"
                ;;
        esac
        echo -e "${GREEN}$line${NC}"
    done

    echo ""
    echo -e "${YELLOW}按 Enter 确认并开始安装 | 输入 n 取消${NC}"
    echo ""

    read -r -p "确认? [Y/n]: " confirm
    case "$confirm" in
        [Nn]) echo ""; log_info "部署已取消。"; exit 0 ;;
    esac
}

# ==================== 安装执行 ====================

run_install() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         🚀 正在安装服务...           ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    local total=${#INSTALL_ORDER[@]}
    local current=0

    for svc in "${INSTALL_ORDER[@]}"; do
        ((current++))
        local script="${SVC_SCRIPT[$svc]}"
        local name="${SVC_NAME[$svc]}"

        print_section "[$current/$total] 安装 $name"

        if [ ! -f "$script" ]; then
            log_error "安装脚本不存在: $script"
            INSTALL_RESULTS+=("✗ $name — 脚本缺失")
            continue
        fi

        chmod +x "$script"

        # Build env vars
        local -a extra_env=()
        extra_env+=("HONGAIBOX_UNATTENDED=1")

        if [ -n "$ACCESS_MODE" ]; then
            extra_env+=("HONGAIBOX_ACCESS_MODE=$ACCESS_MODE")
        fi
        if [ -n "$DOMAIN" ]; then
            extra_env+=("HONGAIBOX_DOMAIN=$DOMAIN")
        fi

        case "$svc" in
            "$SVC_CLIPROXY")
                [ -n "$ADMIN_PASSWORD" ] && extra_env+=("HONGAIBOX_ADMIN_PASSWORD=$ADMIN_PASSWORD")
                ;;
            "$SVC_NEWAPI")
                extra_env+=("HONGAIBOX_DB_TYPE=$DB_TYPE")
                ;;
            "$SVC_PI")
                extra_env+=("HONGAIBOX_NO_PROMPT=1")
                ;;
            "$SVC_SCIENCE")
                extra_env+=("HONGAIBOX_DEST_SNI=$DEST_SNI")
                extra_env+=("HONGAIBOX_REALITY_PORT=$REALITY_PORT")
                ;;
        esac

        # Skip if already installed (e.g. dependency that was already present)
        if [ "${ALREADY_INSTALLED[$svc]:-}" = "true" ]; then
            log_info "$name 已安装，跳过"
            INSTALL_RESULTS+=("✓ $name (已安装)")
            echo ""
            continue
        fi

        # Execute script directly (not via 'bash' to preserve $0 for scripts
        # that use BASH_SOURCE==$0 guards, e.g. install_docker.sh)
        if env "${extra_env[@]}" "$script"; then
            log_success "$name 安装成功"
            INSTALL_RESULTS+=("✓ $name")
            ALREADY_INSTALLED[$svc]=true
        else
            log_error "$name 安装失败"
            INSTALL_RESULTS+=("✗ $name — 失败")
        fi

        echo ""
    done
}

# ==================== 总结 ====================

print_summary() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         部署完成总结                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    for result in "${INSTALL_RESULTS[@]}"; do
        if [[ "$result" == ✓* ]]; then
            echo -e "  ${GREEN}$result${NC}"
        else
            echo -e "  ${RED}$result${NC}"
        fi
    done

    echo ""
    print_divider
    echo ""
    echo -e "${WHITE}常用管理命令:${NC}"
    echo ""

    for svc in "${INSTALL_ORDER[@]}"; do
        case "$svc" in
            "$SVC_NGINX")
                echo "  Nginx:"
                echo "    systemctl status nginx  |  nginx -t  |  systemctl reload nginx"
                echo ""
                ;;
            "$SVC_DOCKER")
                echo "  Docker:"
                echo "    docker info  |  docker compose version"
                echo ""
                ;;
            "$SVC_NEWAPI")
                echo "  New-API:"
                echo "    cd /opt/docker-services/new-api && docker compose ps"
                echo "    docker compose logs -f new-api"
                echo ""
                ;;
            "$SVC_CLIPROXY")
                echo "  CliproxyAPI:"
                echo "    systemctl status cliproxyapi"
                echo "    journalctl -u cliproxyapi -f"
                echo ""
                ;;
            "$SVC_PI")
                echo "  Pi:"
                echo "    pi --help  |  pi -p \"你的问题\""
                echo ""
                ;;
            "$SVC_SCIENCE")
                echo "  Science:"
                echo "    systemctl status xray"
                echo "    journalctl -u xray -f"
                echo ""
                ;;
        esac
    done

    print_divider
    echo ""
    echo -e "${CYAN}感谢使用洪哥的 AI 工具箱 v${VERSION}！${NC}"
    echo -e "${DIM}日志文件: $DEPLOY_LOG_FILE${NC}"
    echo ""
}

# ==================== 主流程 ====================

main() {
    check_root
    setup_logging "hongaibox"

    # ── Step 1: 检测 + 展示 ──
    detect_installed_services
    show_service_panel

    # ── Step 2: 选择服务 ──
    select_services

    # ── Step 3: 依赖解析 ──
    resolve_deps

    # ── Step 4: 全局配置 ──
    if needs_access_mode; then
        configure_access_mode
    fi

    # ── Step 5: 服务级配置 ──
    collect_service_configs

    # ── Step 6: 确认 ──
    show_review

    # ── Step 7: 安装 ──
    run_install

    # ── Step 8: 总结 ──
    print_summary
}

# ==================== 执行 ====================
main "$@"
