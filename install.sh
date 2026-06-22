#!/bin/bash
# shellcheck shell=bash
# shellcheck disable=SC2034
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
#
################################################################################

set -euo pipefail

# ==================== 版本与仓库信息 ====================
readonly VERSION="4.0.0"
readonly HONGAIBOX_REPO="YoungHong1992/hong-ai-box"

show_bootstrap_help() {
    cat <<EOF
洪哥的 AI 工具箱 v${VERSION} — 一键部署脚本

用法:
  ./install.sh              # 交互式部署
  ./install.sh -h           # 显示此帮助
  ./install.sh --version    # 显示版本

远程安装:
  curl -fsSL https://raw.githubusercontent.com/${HONGAIBOX_REPO}/main/install.sh | sudo bash
EOF
}

# --version/--help 不依赖完整仓库，允许单文件下载后直接查询。
for arg in "$@"; do
    case "$arg" in
        -h|--help) show_bootstrap_help; exit 0 ;;
        --version) echo "v${VERSION}"; exit 0 ;;
    esac
done

# ==================== 路径解析 / 单文件自举 ====================
resolve_install_dir() {
    local source_path="${BASH_SOURCE[0]:-$0}"
    cd "$(dirname "$source_path")" 2>/dev/null && pwd || pwd
}

INSTALL_DIR="$(resolve_install_dir)"

bootstrap_full_repo() {
    local ref="${HONGAIBOX_REF:-main}"
    local tmp_dir archive_url archive_file root_dir status

    echo "[INFO] 未检测到完整仓库，正在下载 hong-ai-box (${ref})..." >&2

    if ! command -v tar &>/dev/null; then
        echo "[ERROR] 缺少 tar，无法解压完整安装包。" >&2
        exit 1
    fi

    tmp_dir="$(mktemp -d)"
    archive_file="$tmp_dir/hong-ai-box.tar.gz"

    if [[ "$ref" == v* ]]; then
        archive_url="https://github.com/${HONGAIBOX_REPO}/archive/refs/tags/${ref}.tar.gz"
    else
        archive_url="https://github.com/${HONGAIBOX_REPO}/archive/refs/heads/${ref}.tar.gz"
    fi

    if command -v curl &>/dev/null; then
        curl -fsSL "$archive_url" -o "$archive_file"
    elif command -v wget &>/dev/null; then
        wget -qO "$archive_file" "$archive_url"
    else
        echo "[ERROR] 缺少 curl/wget，无法下载完整安装包。" >&2
        rm -rf "$tmp_dir"
        exit 1
    fi

    tar -xzf "$archive_file" -C "$tmp_dir"
    root_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"

    if [ -z "$root_dir" ] \
        || [ ! -f "$root_dir/install.sh" ] \
        || [ ! -f "$root_dir/nginx/install.sh" ] \
        || [ ! -f "$root_dir/docker/install.sh" ] \
        || [ ! -f "$root_dir/cliproxyapi/install.sh" ] \
        || [ ! -f "$root_dir/new-api/install.sh" ] \
        || [ ! -f "$root_dir/pi-coding-agent/install.sh" ]; then
        echo "[ERROR] 下载的安装包不完整。" >&2
        rm -rf "$tmp_dir"
        exit 1
    fi

    chmod +x "$root_dir/install.sh"

    set +e
    if [ -r /dev/tty ]; then
        bash "$root_dir/install.sh" "$@" < /dev/tty
    else
        bash "$root_dir/install.sh" "$@"
    fi
    status=$?
    set -e

    rm -rf "$tmp_dir"
    exit "$status"
}

# ==================== 完整仓库检测 ====================
if [ ! -f "$INSTALL_DIR/nginx/install.sh" ] \
    || [ ! -f "$INSTALL_DIR/docker/install.sh" ] \
    || [ ! -f "$INSTALL_DIR/cliproxyapi/install.sh" ] \
    || [ ! -f "$INSTALL_DIR/new-api/install.sh" ] \
    || [ ! -f "$INSTALL_DIR/pi-coding-agent/install.sh" ]; then
    bootstrap_full_repo "$@"
fi

# ==================== 自包含公共函数 ====================
# 本脚本可独立运行，不依赖外部公共库。
# shellcheck disable=SC2034
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
readonly COMMON_VERSION="4.0.0"
readonly DEPLOY_LOG_DIR="/var/log/vps-deploy"

print_header() {
    local title="${1:-部署工具}"
    clear 2>/dev/null || true
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    printf  "║           %-51s║\n" "$title"
    echo "║                                                              ║"
    printf  "║               版本: v%-40s║\n" "${COMMON_VERSION}"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_divider() {
    echo -e "${DIM}────────────────────────────────────────────────────────────────${NC}"
}

print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}▶ $1${NC}"
    print_divider
}

setup_logging() {
    local script_name="${1:-deploy}"
    mkdir -p "$DEPLOY_LOG_DIR"
    DEPLOY_LOG_FILE="${DEPLOY_LOG_DIR}/${script_name}-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$DEPLOY_LOG_FILE") 2>&1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === 日志开始: $DEPLOY_LOG_FILE ==="
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 脚本: $script_name"
}

log_info()    { echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%H:%M:%S') $*" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%H:%M:%S') $*" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*" >&2; }
log_step()    { echo -e "${CYAN}[STEP]${NC} $(date '+%H:%M:%S') $*" >&2; }
log_debug()   { echo -e "${DIM}[DEBUG]${NC} $(date '+%H:%M:%S') $*" >&2; }

generate_password() {
    local length="${1:-32}"
    openssl rand -base64 48 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

generate_session_secret() {
    local length="${1:-48}"
    openssl rand -base64 64 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

generate_api_key() {
    local prefix="${1:-sk-}"
    local key_body
    key_body=$(openssl rand -base64 48 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 45)
    echo "${prefix}${key_body}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR] 必须使用 root 权限运行此脚本。${NC}"
        echo -e "${YELLOW}请使用: sudo $0${NC}"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

detect_os_version() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "${VERSION_CODENAME:-unknown}"
    else
        echo "unknown"
    fi
}

detect_server_ip() {
    local ip
    ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || \
         curl -s --connect-timeout 5 https://ifconfig.me 2>/dev/null || \
         curl -s --connect-timeout 5 https://icanhazip.com 2>/dev/null || \
         hostname -I 2>/dev/null | awk '{print $1}')
    echo "$ip"
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)   echo "linux_amd64" ;;
        arm64|aarch64)  echo "linux_arm64" ;;
        *)              echo "unknown" ;;
    esac
}

check_port_available() {
    local port="$1"
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
        return 1
    fi
    return 0
}

ensure_port_available() {
    local port="$1"
    local service_name="${2:-服务}"
    if ! check_port_available "$port"; then
        log_error "端口 $port 已被占用，$service_name 无法使用此端口。"
        log_info "请先释放端口或修改脚本中的端口配置。"
        exit 1
    fi
    log_debug "端口 $port 可用"
}

check_command_available() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "缺少必要工具: $cmd，请安装后重试。"
        return 1
    fi
    return 0
}

ensure_commands() {
    local missing=""
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing="$missing $cmd"
        fi
    done
    if [ -n "$missing" ]; then
        log_error "缺少必要工具:${missing}"
        log_info "请运行: apt-get install -y${missing}"
        exit 1
    fi
}

detect_nginx_http3() {
    if command -v nginx &>/dev/null && nginx -V 2>&1 | grep -q "http_v3_module"; then
        return 0
    fi
    return 1
}

get_main_domain_email() {
    local domain="$1"
    local main_domain
    main_domain=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
    echo "admin@${main_domain}"
}

is_valid_ssl_email() {
    local email="$1"
    [ -z "$email" ] && return 1
    echo "$email" | grep -qE "@(example\.com|localhost|test\.com)" && return 1
    return 0
}

ensure_acme_sh_config() {
    local domain="$1"
    local expected_email
    expected_email=$(get_main_domain_email "$domain")

    if [ ! -f ~/.acme.sh/acme.sh ]; then
        log_info "安装 acme.sh..."
        curl -s --connect-timeout 10 https://get.acme.sh | sh -s email="$expected_email" >/dev/null 2>&1 || true
        return 0
    fi

    if [ -f ~/.acme.sh/account.conf ]; then
        local current_email
        current_email=$(grep "^ACCOUNT_EMAIL=" ~/.acme.sh/account.conf 2>/dev/null | cut -d"'" -f2 || true)

        if ! is_valid_ssl_email "$current_email"; then
            log_info "修正 acme.sh 邮箱配置..."
            sed -i "s/^ACCOUNT_EMAIL=.*/ACCOUNT_EMAIL='$expected_email'/g" ~/.acme.sh/account.conf
            rm -rf ~/.acme.sh/ca/*/account.json 2>/dev/null || true
        fi
    fi
}

apply_ssl_certificate() {
    local domain="$1"
    local ssl_dir="$2"
    local mode="$3"

    mkdir -p "$ssl_dir"

    case "$mode" in
        http)
            log_info "HTTP 模式，跳过 SSL 证书配置。"
            echo "无 (HTTP 模式)"
            return 0
            ;;
        domain)
            log_info "申请 Let's Encrypt ECC-256 证书..."

            ensure_acme_sh_config "$domain"
            local safe_domain temp_conf default_site default_backup default_moved=false
            safe_domain=$(printf '%s' "$domain" | tr -c 'A-Za-z0-9_.-' '_')
            temp_conf="/etc/nginx/conf.d/00-acme-${safe_domain}.conf"
            default_site="/etc/nginx/sites-enabled/default"
            default_backup="/etc/nginx/sites-enabled/default.disabled-by-ssl"

            cat > "$temp_conf" <<NGINX_TEMP
server {
    listen 80;
    server_name $domain;
    location /.well-known/acme-challenge/ {
        root /var/www/acme;
    }
}
NGINX_TEMP

            mkdir -p /var/www/acme
            chmod 755 /var/www/acme
            if [ -f "$default_site" ]; then
                mv "$default_site" "$default_backup" 2>/dev/null && default_moved=true || true
            fi
            systemctl reload nginx >/dev/null 2>&1 || true

            if ~/.acme.sh/acme.sh --issue --server letsencrypt -d "$domain" --webroot /var/www/acme --keylength ec-256 >&2; then
                ~/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
                    --key-file       "$ssl_dir/key.pem" \
                    --fullchain-file "$ssl_dir/fullchain.pem" \
                    --reloadcmd     "systemctl reload nginx" >/dev/null 2>&1 || true

                if [ -f "$ssl_dir/fullchain.pem" ]; then
                    log_success "SSL 证书申请成功 (Let's Encrypt ECC-256)"
                    rm -f "$temp_conf"
                    if [ "$default_moved" = true ] && [ -f "$default_backup" ]; then
                        mv "$default_backup" "$default_site" 2>/dev/null || true
                    fi
                    systemctl reload nginx >/dev/null 2>&1 || true
                    echo "Let's Encrypt (ECC-256)"
                    return 0
                fi
            fi

            log_warning "Let's Encrypt 申请失败，降级为自签名证书..."
            rm -f "$temp_conf"
            if [ "$default_moved" = true ] && [ -f "$default_backup" ]; then
                mv "$default_backup" "$default_site" 2>/dev/null || true
            fi
            systemctl reload nginx >/dev/null 2>&1 || true
            ;;
        ip)
            log_info "生成自签名证书 (IP 模式)..."
            ;;
    esac

    local san
    if validate_ip "$domain" 2>/dev/null; then
        san="IP:$domain"
    else
        san="DNS:$domain"
    fi

    if openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$ssl_dir/key.pem" \
        -out "$ssl_dir/fullchain.pem" \
        -subj "/CN=$domain" \
        -addext "subjectAltName=$san" >/dev/null 2>&1; then
        log_success "自签名证书生成成功"
        echo "自签名证书"
    else
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$ssl_dir/key.pem" \
            -out "$ssl_dir/fullchain.pem" \
            -subj "/CN=$domain" >/dev/null 2>&1
        log_success "自签名证书生成成功 (兼容模式)"
        echo "自签名证书"
    fi
}

readonly NGINX_SSL_CONFIG='
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_tickets on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    add_header Strict-Transport-Security "max-age=31536000" always;'

readonly NGINX_REDIRECT_LOGIC='
    set $isRedcert 1;
    if ($server_port != 443) {
        set $isRedcert 2;
    }
    if ( $uri ~ /\.well-known/ ) {
        set $isRedcert 1;
    }
    if ($isRedcert != 1) {
        rewrite ^(.*)$ https://$host$1 permanent;
    }'

backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup
        backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"
        cp -a "$file" "$backup"
        log_info "已备份: $backup"
    fi
}

find_nginx_conf_by_server_name() {
    local domain="$1"
    local conf_dir="${2:-/etc/nginx/conf.d}"
    local conf

    [ -d "$conf_dir" ] || return 1

    while IFS= read -r -d '' conf; do
        if awk -v domain="$domain" '
            {
                for (i = 1; i <= NF; i++) {
                    token = $i
                    gsub(/[{};]/, "", token)

                    if (in_server_name && token == domain) found = 1
                    if (in_server_name && $i ~ /;/) in_server_name = 0
                    if (token == "server_name") in_server_name = 1
                }
            }
            END { exit found ? 0 : 1 }
        ' "$conf"; then
            echo "$conf"
            return 0
        fi
    done < <(find "$conf_dir" -maxdepth 1 -type f -name "*.conf" -print0 2>/dev/null)

    return 1
}

detect_compose_cmd() {
    if docker compose version &>/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
    else
        echo ""
    fi
}

wait_for_healthy() {
    local compose_cmd="$1"
    local service_dir="$2"
    local max_wait="${3:-60}"
    local interval="${4:-5}"
    shift 4
    local required_services=("$@")

    cd "$service_dir" || { log_error "无法进入目录: $service_dir"; return 1; }

    local waited=0
    while [ "$waited" -lt "$max_wait" ]; do
        local all_healthy=true

        if [ "${#required_services[@]}" -eq 0 ]; then
            if $compose_cmd ps 2>/dev/null | grep -q "(healthy)"; then
                log_success "服务已健康运行 (${waited}s)"
                return 0
            fi
            all_healthy=false
        else
            for svc in "${required_services[@]}"; do
                if ! $compose_cmd ps 2>/dev/null | grep -q "${svc}.*(healthy)"; then
                    all_healthy=false
                    break
                fi
            done
        fi

        if [ "$all_healthy" = true ]; then
            log_success "所有指定服务已健康运行 (${waited}s)"
            return 0
        fi

        if ! $compose_cmd ps 2>/dev/null | grep -q "Up"; then
            log_warning "检测到容器未运行，继续等待..."
        fi

        sleep "$interval"
        waited=$((waited + interval))
    done

    log_warning "等待超时 (${max_wait}s)，请手动检查服务状态"
    $compose_cmd ps 2>/dev/null || true
    return 1
}

is_noninteractive() {
    [ "${HONGAIBOX_UNATTENDED:-}" = "1" ]
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        printf "%s [Y/n]: " "$prompt"
    else
        printf "%s [y/N]: " "$prompt"
    fi

    read -r response
    response=${response:-$default}

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

wait_key() {
    echo ""
    read -r -p "按 Enter 键继续..." _
}

validate_domain() {
    local domain="$1"
    if [ -z "$domain" ]; then
        log_error "域名不能为空。"
        return 1
    fi
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "域名格式不正确: $domain"
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    local IFS=. octet

    if [ -z "$ip" ]; then
        log_error "IP 不能为空。"
        return 1
    fi

    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        for octet in $ip; do
            if [ "$octet" -gt 255 ]; then
                log_error "IPv4 地址格式不正确: $ip"
                return 1
            fi
        done
        return 0
    fi

    if [[ "$ip" == *:* && "$ip" =~ ^[0-9A-Fa-f:]+$ ]]; then
        return 0
    fi

    log_error "IP 地址格式不正确: $ip"
    return 1
}

validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "端口必须是 1-65535 的数字: $port"
        return 1
    fi
    return 0
}

validate_sni() {
    local sni="$1"
    validate_domain "$sni"
}

escape_double_quoted() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

select_access_mode() {
    echo "" >&2
    echo -e "${CYAN}>>> 请选择访问方式${NC}" >&2
    echo "" >&2
    echo "  1) 使用域名（推荐）- 自动申请 Let's Encrypt 证书" >&2
    echo "  2) 使用 IP 地址   - 自签名证书，无需域名" >&2
    echo "  3) 仅使用 HTTP    - 无 SSL 证书，仅限内网/开发环境" >&2
    echo "" >&2

    local mode
    while true; do
        read -r -p "请选择 [1/2/3]: " mode
        case "$mode" in
            1) echo "domain"; return 0 ;;
            2) echo "ip"; return 0 ;;
            3) echo "http"; return 0 ;;
            *) log_warning "无效选择，请重新输入" >&2 ;;
        esac
    done
}

get_domain_for_mode() {
    local mode="$1"

    case "$mode" in
        domain)
            local domain
            read -r -p "请输入域名 (例如 api.example.com): " domain
            validate_domain "$domain" || exit 1
            echo "$domain"
            ;;
        ip|http)
            local server_ip ip_confirm domain
            server_ip=$(detect_server_ip)
            if [ -z "$server_ip" ] || ! validate_ip "$server_ip"; then
                log_error "无法获取有效服务器 IP，请手动输入。" >&2
                while true; do
                    read -r -p "请输入服务器 IP 地址: " server_ip
                    validate_ip "$server_ip" && break
                done
            fi
            echo "" >&2
            echo -e "检测到服务器 IP: ${GREEN}$server_ip${NC}" >&2

            if [ "$mode" = "http" ]; then
                echo -e "${YELLOW}⚠️  HTTP 模式警告：${NC}" >&2
                echo -e "${YELLOW}   - 数据传输不加密，API Key 可能泄露${NC}" >&2
                echo -e "${YELLOW}   - 仅建议在内网或开发环境使用${NC}" >&2
            fi

            echo "" >&2
            read -r -p "确认使用此 IP？(y/n，或直接输入其他 IP): " ip_confirm

            case "$ip_confirm" in
                [Yy]|"") echo "$server_ip" ;;
                [Nn])
                    while true; do
                        read -r -p "请输入 IP 地址: " domain
                        validate_ip "$domain" && break
                    done
                    echo "$domain"
                    ;;
                *)
                    if validate_ip "$ip_confirm"; then
                        echo "$ip_confirm"
                    else
                        exit 1
                    fi
                    ;;
            esac
            ;;
    esac
}

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

# Service definitions (order = dependency order)
declare -A SVC_NAME SVC_DESC SVC_HINT SVC_SCRIPT SVC_DEPENDS
SVC_NAME[$SVC_NGINX]="Nginx (HTTP/3)"
SVC_DESC[$SVC_NGINX]="Nginx 官方主线仓库安装，支持 HTTP/3 (QUIC)、TCP BBR 优化"
SVC_HINT[$SVC_NGINX]="512MB 内存"
SVC_SCRIPT[$SVC_NGINX]="$INSTALL_DIR/nginx/install.sh"
SVC_DEPENDS[$SVC_NGINX]=""

SVC_NAME[$SVC_DOCKER]="Docker 容器环境"
SVC_DESC[$SVC_DOCKER]="Docker Engine + Docker Compose 插件"
SVC_HINT[$SVC_DOCKER]="无额外需求"
SVC_SCRIPT[$SVC_DOCKER]="$INSTALL_DIR/docker/install.sh"
SVC_DEPENDS[$SVC_DOCKER]=""

SVC_NAME[$SVC_CLIPROXY]="CliproxyAPI"
SVC_DESC[$SVC_CLIPROXY]="轻量 AI API 转发代理 (~50MB)，支持 OpenAI/Claude/Gemini"
SVC_HINT[$SVC_CLIPROXY]="256MB 内存"
SVC_SCRIPT[$SVC_CLIPROXY]="$INSTALL_DIR/cliproxyapi/install.sh"
SVC_DEPENDS[$SVC_CLIPROXY]="$SVC_NGINX"

SVC_NAME[$SVC_NEWAPI]="New-API"
SVC_DESC[$SVC_NEWAPI]="AI 模型网关与资产管理系统，支持多模型聚合、计费、用户管理"
SVC_HINT[$SVC_NEWAPI]="≥ 1GB 内存"
SVC_SCRIPT[$SVC_NEWAPI]="$INSTALL_DIR/new-api/install.sh"
SVC_DEPENDS[$SVC_NEWAPI]="$SVC_NGINX $SVC_DOCKER"

SVC_NAME[$SVC_PI]="Pi 编程助手"
SVC_DESC[$SVC_PI]="极简终端 AI 编程助手，支持 Anthropic/OpenAI/Gemini/DeepSeek"
SVC_HINT[$SVC_PI]="500MB 磁盘"
SVC_SCRIPT[$SVC_PI]="$INSTALL_DIR/pi-coding-agent/install.sh"
SVC_DEPENDS[$SVC_PI]=""

# Ordered list for display
readonly ALL_SERVICES=(
    "$SVC_NGINX" "$SVC_DOCKER" "$SVC_CLIPROXY"
    "$SVC_NEWAPI" "$SVC_PI"
)

# Runtime state
declare -A ALREADY_INSTALLED   # true if already present on system
declare -A TO_INSTALL          # true if user selected to install
declare -A SERVICE_DOMAIN      # per Web service domain/IP
declare -A INSTALL_FAILED      # true if service failed/skipped due dependency
INSTALL_ORDER=()               # resolved dependency order
INSTALL_RESULTS=()             # for summary
FAILED=0                       # non-zero when any service failed

# User config
ACCESS_MODE=""
DOMAIN=""                     # single Web service IP/domain fallback
ADMIN_PASSWORD=""              # cliproxyapi
DB_TYPE="postgresql"           # newapi

# ==================== 服务检测 ====================

detect_installed_services() {
    echo ""
    echo -e "${CYAN}正在检测已安装的服务...${NC}"

    for svc in "${ALL_SERVICES[@]}"; do
        case "$svc" in
            "$SVC_NGINX")
                if command -v nginx &>/dev/null \
                    && nginx -t >/dev/null 2>&1 \
                    && systemctl is-active --quiet nginx 2>/dev/null; then
                    ALREADY_INSTALLED[$svc]=true
                fi
                ;;
            "$SVC_DOCKER")
                if command -v docker &>/dev/null \
                    && systemctl is-active --quiet docker 2>/dev/null \
                    && (docker compose version &>/dev/null || command -v docker-compose &>/dev/null); then
                    ALREADY_INSTALLED[$svc]=true
                fi
                ;;
            "$SVC_CLIPROXY")
                if [ -f /opt/cliproxyapi/version.txt ] || [ -f /etc/systemd/system/cliproxyapi.service ]; then
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
        esac
    done
}

# ==================== 显示服务面板 ====================

show_service_panel() {
    clear 2>/dev/null || true
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

        if [ "${ALREADY_INSTALLED[$svc]:-}" = "true" ]; then
            status="${GREEN}✓ 已安装${NC}"
        else
            status="${DIM}○ 未安装${NC}"
        fi

        # Alignment: name 22 chars, hint 20 chars
        printf "  %b%-22s%b %b%-20s%b %-40s %b\n" \
            "$BOLD" "$name" "$NC" \
            "$DIM" "$hint" "$NC" \
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

is_web_service() {
    case "$1" in
        "$SVC_CLIPROXY"|"$SVC_NEWAPI") return 0 ;;
        *) return 1 ;;
    esac
}

web_service_count() {
    local count=0
    local svc
    for svc in "${INSTALL_ORDER[@]}"; do
        if is_web_service "$svc" && [ "${ALREADY_INSTALLED[$svc]:-}" != "true" ]; then
            ((count+=1))
        fi
    done
    echo "$count"
}

needs_access_mode() {
    local svc
    for svc in "${INSTALL_ORDER[@]}"; do
        if is_web_service "$svc" && [ "${ALREADY_INSTALLED[$svc]:-}" != "true" ]; then
            return 0
        fi
    done
    return 1
}

# ==================== 全局配置：访问模式 ====================

configure_access_mode() {
    local web_count svc
    web_count=$(web_service_count)

    echo ""
    echo -e "${CYAN}>>> 配置访问方式${NC}"
    echo ""

    if [ "$web_count" -gt 1 ]; then
        ACCESS_MODE="domain"
        echo -e "${YELLOW}检测到多个 Web 服务。为避免 Nginx 配置互相覆盖，必须为每个服务配置独立域名。${NC}"
        echo -e "${DIM}例如: cliproxy.example.com 与 newapi.example.com${NC}"
        echo ""
    else
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
    fi

    case "$ACCESS_MODE" in
        domain)
            echo ""
            local svc domain existing_svc duplicate
            for svc in "${INSTALL_ORDER[@]}"; do
                if ! is_web_service "$svc" || [ "${ALREADY_INSTALLED[$svc]:-}" = "true" ]; then
                    continue
                fi

                while true; do
                    read -r -p "请输入 ${SVC_NAME[$svc]} 域名 (例如 ${svc}.example.com): " domain
                    if ! validate_domain "$domain"; then
                        continue
                    fi

                    duplicate=false
                    for existing_svc in "${!SERVICE_DOMAIN[@]}"; do
                        if [ "${SERVICE_DOMAIN[$existing_svc]}" = "$domain" ]; then
                            duplicate=true
                            break
                        fi
                    done

                    if [ "$duplicate" = true ]; then
                        log_error "域名已被其他服务使用，请为每个 Web 服务使用独立域名。"
                        continue
                    fi

                    SERVICE_DOMAIN[$svc]="$domain"
                    break
                done
            done
            ;;
        ip|http)
            DOMAIN="$(detect_server_ip)"
            if [ -z "$DOMAIN" ] || ! validate_ip "$DOMAIN"; then
                echo ""
                while true; do
                    read -r -p "无法自动获取有效公网 IP，请手动输入: " DOMAIN
                    validate_ip "$DOMAIN" && break
                done
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
                [Nn])
                    while true; do
                        read -r -p "请输入 IP 地址: " DOMAIN
                        validate_ip "$DOMAIN" && break
                    done
                    ;;
            esac

            local single_svc=""
            for svc in "${INSTALL_ORDER[@]}"; do
                if is_web_service "$svc" && [ "${ALREADY_INSTALLED[$svc]:-}" != "true" ]; then
                    single_svc="$svc"
                    break
                fi
            done
            [ -n "$single_svc" ] && SERVICE_DOMAIN[$single_svc]="$DOMAIN"
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
    esac
}

collect_service_configs() {
    for svc in "${INSTALL_ORDER[@]}"; do
        case "$svc" in
            "$SVC_CLIPROXY"|"$SVC_NEWAPI")
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

        local svc
        if [ "$ACCESS_MODE" = "domain" ]; then
            for svc in "${INSTALL_ORDER[@]}"; do
                if is_web_service "$svc" && [ -n "${SERVICE_DOMAIN[$svc]:-}" ]; then
                    echo -e "  ${SVC_NAME[$svc]}: ${GREEN}${SERVICE_DOMAIN[$svc]}${NC}"
                fi
            done
        else
            echo -e "  IP:       ${GREEN}$DOMAIN${NC}"
        fi
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
        ((current+=1))
        local script="${SVC_SCRIPT[$svc]}"
        local name="${SVC_NAME[$svc]}"

        print_section "[$current/$total] 安装 $name"

        local dep dep_failed=false
        for dep in ${SVC_DEPENDS[$svc]}; do
            if [ "${INSTALL_FAILED[$dep]:-}" = "true" ]; then
                dep_failed=true
                break
            fi
        done
        if [ "$dep_failed" = true ]; then
            log_error "$name 依赖安装失败，已跳过"
            INSTALL_RESULTS+=("✗ $name — 依赖失败，已跳过")
            INSTALL_FAILED[$svc]=true
            FAILED=1
            echo ""
            continue
        fi

        if [ ! -f "$script" ]; then
            log_error "安装脚本不存在: $script"
            INSTALL_RESULTS+=("✗ $name — 脚本缺失")
            INSTALL_FAILED[$svc]=true
            FAILED=1
            continue
        fi

        chmod +x "$script"

        # Build env vars
        local -a extra_env=()
        extra_env+=("HONGAIBOX_UNATTENDED=1")

        local svc_domain="${SERVICE_DOMAIN[$svc]:-}"
        if is_web_service "$svc"; then
            [ -n "$ACCESS_MODE" ] && extra_env+=("HONGAIBOX_ACCESS_MODE=$ACCESS_MODE")
            [ -z "$svc_domain" ] && svc_domain="$DOMAIN"
            [ -n "$svc_domain" ] && extra_env+=("HONGAIBOX_DOMAIN=$svc_domain")
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
        esac

        # Component install.sh owns idempotency/repair/skip behavior.
        # The root installer only resolves order and passes collected config.
        # Execute component install.sh directly (not via 'bash') to preserve $0
        # for scripts that use BASH_SOURCE==$0 guards.
        if env "${extra_env[@]}" "$script"; then
            log_success "$name 安装成功"
            INSTALL_RESULTS+=("✓ $name")
            ALREADY_INSTALLED[$svc]=true
        else
            log_error "$name 安装失败"
            INSTALL_RESULTS+=("✗ $name — 失败")
            INSTALL_FAILED[$svc]=true
            FAILED=1
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

    if [ "$FAILED" -ne 0 ]; then
        log_error "部分服务安装失败，请根据上方日志排查。"
        exit 1
    fi
}

# ==================== 执行 ====================
main "$@"
