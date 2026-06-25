#!/bin/bash
# shellcheck disable=SC2034

################################################################################
#
# New-API Docker 部署脚本
# 版本: v4.0.0
#
# 功能说明：
#   1. 部署 New-API AI 模型聚合管理系统（Docker 方式）
#   2. 自动配置 PostgreSQL / MySQL 数据库
#   3. 自动配置 Redis 缓存
#   4. 自动申请 SSL 证书 / 自签名证书
#   5. 自动配置 Nginx 反向代理
#   6. 生成安全随机密码并保存到信息文件
#
# 用法:
#   ./install.sh        # 交互式部署
#   ./install.sh -h     # 显示帮助
#
# 前置条件：
#   - Docker 和 Docker Compose 已安装（可通过 ../docker/install.sh）
#   - Nginx 已安装（可通过 ../nginx/install.sh）
#   - 域名需已解析到本服务器
#
################################################################################

set -euo pipefail

HONGAIBOX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HONGAIBOX_REPO_DIR="$(cd "$HONGAIBOX_SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/credentials.sh
source "$HONGAIBOX_REPO_DIR/lib/credentials.sh"

# ==================== 公共函数 ====================
# 本脚本可在完整仓库内独立运行，并复用 ../lib 公共库。
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


# ==================== 帮助 ====================
show_help() {
    cat <<'EOF'
New-API Docker 部署脚本

用法:
  ./install.sh       # 交互式部署
  ./install.sh -h    # 显示此帮助

功能:
  - Docker Compose 部署 (New-API + PostgreSQL/MySQL + Redis)
  - 支持域名/IP/HTTP 三种访问模式
  - 自动申请 Let's Encrypt 证书
  - Nginx 反向代理 + HTTP/3 支持

前置条件:
  - 已安装 Docker (../docker/install.sh)
  - 已安装 Nginx (../nginx/install.sh)
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
NEWAPI_PORT=3000
CONF_D="/etc/nginx/conf.d"
SSL_DIR="/etc/nginx/ssl"
DOCKER_ROOT="/opt/docker-services"
SERVICE_DIR="$DOCKER_ROOT/new-api"
DATA_DIR="$SERVICE_DIR/data"
LOGS_DIR="$SERVICE_DIR/logs"
DOCKER_IMAGE="calciumion/new-api:latest"
DOCKER_NETWORK="ai-services"

# ==================== 环境检查 ====================
check_root
setup_logging "newapi-install"

ensure_commands curl wget openssl

if ! command -v docker &> /dev/null \
    || ! systemctl is-active --quiet docker 2>/dev/null \
    || [ -z "$(detect_compose_cmd)" ]; then
    log_error "Docker/Compose 环境未就绪。"
    log_info "请先安装 Docker：进入仓库根目录的 docker/ 目录运行 sudo ./install.sh，或使用根目录 sudo ./install.sh 选择 Docker。"
    exit 1
fi

COMPOSE_CMD=$(detect_compose_cmd)
if [ -z "$COMPOSE_CMD" ]; then
    log_error "未检测到 docker-compose。请安装: apt-get install docker-compose-plugin"
    exit 1
fi

if ! command -v nginx &> /dev/null; then
    log_error "未检测到 Nginx。"
    log_info "请先安装 Nginx：进入仓库根目录的 nginx/ 目录运行 sudo ./install.sh，或使用根目录 sudo ./install.sh 选择 Nginx。"
    exit 1
fi

if ! nginx -t >/dev/null 2>&1 || ! systemctl is-active --quiet nginx 2>/dev/null; then
    log_error "Nginx 未正常运行或配置测试未通过。"
    log_info "请先修复/启动 Nginx 后再运行本脚本：systemctl start nginx && nginx -t"
    exit 1
fi

# 端口检查（覆盖安装时允许现有 New-API 占用端口）
if [ ! -f "$SERVICE_DIR/docker-compose.yml" ]; then
    ensure_port_available "$NEWAPI_PORT" "New-API"
fi

# ==================== 欢迎 ====================
clear 2>/dev/null || true
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}   New-API Docker 部署程序 v${COMMON_VERSION}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -f "$SERVICE_DIR/docker-compose.yml" ]; then
    log_warning "检测到已安装 New-API"
    if ! is_noninteractive; then
        if ! confirm "是否覆盖安装？"; then
            log_info "安装已取消。"
            exit 0
        fi
    fi
fi

# ==================== 交互输入 ====================
log_step "[1/8] 请输入配置信息"
echo ""

if is_noninteractive; then
    MODE="${HONGAIBOX_ACCESS_MODE:-domain}"
    DOMAIN="${HONGAIBOX_DOMAIN:-$(detect_server_ip)}"
    DB_CHOICE="${HONGAIBOX_DB_TYPE:-postgresql}"
    case "$DB_CHOICE" in
        mysql|MySQL) DB_CHOICE=2 ;;
        *)           DB_CHOICE=1 ;;
    esac
    USE_DOMAIN=false
    USE_HTTP_ONLY=false
    case "$MODE" in
        domain) USE_DOMAIN=true ;;
        http)   USE_HTTP_ONLY=true ;;
    esac
else
    MODE=$(select_access_mode)

    USE_DOMAIN=false
    USE_HTTP_ONLY=false
    case "$MODE" in
        domain) USE_DOMAIN=true ;;
        http)   USE_HTTP_ONLY=true ;;
    esac

    DOMAIN=$(get_domain_for_mode "$MODE")
fi

SERVER_IP=$(detect_server_ip)

case "$MODE" in
    domain) validate_domain "$DOMAIN" || exit 1 ;;
    ip|http) validate_ip "$DOMAIN" || exit 1 ;;
    *) log_error "未知访问模式: $MODE"; exit 1 ;;
esac

PREEXISTING_CONF="$(find_nginx_conf_by_server_name "$DOMAIN" "$CONF_D" || true)"
if [ -n "$PREEXISTING_CONF" ] && ! grep -q "NEW-API-START" "$PREEXISTING_CONF"; then
    log_error "Nginx server_name 已被其他配置占用: $PREEXISTING_CONF"
    log_error "请为 New-API 使用独立域名，避免覆盖其他服务。"
    exit 1
fi

echo ""

# 数据库类型选择
USE_POSTGRESQL=true
DB_TYPE="PostgreSQL"
DB_IMAGE="postgres:15"
if is_noninteractive; then
    case "$DB_CHOICE" in
        2)
            USE_POSTGRESQL=false
            DB_TYPE="MySQL"
            DB_IMAGE="mysql:8.2"
            ;;
    esac
else
    echo -e "${CYAN}选择数据库类型:${NC}"
    echo "  1) PostgreSQL 15 (推荐)"
    echo "  2) MySQL 8.2"
    read -r -p "请选择 [1-2, 默认 1]: " DB_CHOICE
    case "$DB_CHOICE" in
        2)
            USE_POSTGRESQL=false
            DB_TYPE="MySQL"
            DB_IMAGE="mysql:8.2"
            ;;
    esac
fi

log_info "已选择: $DB_TYPE"
echo ""

# 使用安全随机生成密码
log_info "正在生成安全随机密码..."
DB_PASSWORD=$(generate_password 32)
REDIS_PASSWORD=$(generate_password 32)
SESSION_SECRET=$(generate_session_secret 48)
log_success "密码已生成（将保存到凭据文件，不会输出到日志）"
echo ""

# 确认
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$USE_DOMAIN" = true ]; then
    echo -e "${YELLOW}⚠️  请确保域名已解析:${NC}"
    echo -e "域名:   ${GREEN}$DOMAIN${NC}"
    echo -e "目标IP: ${GREEN}$SERVER_IP${NC}"
elif [ "$USE_HTTP_ONLY" = true ]; then
    echo -e "${YELLOW}⚠️  HTTP 模式: 数据不加密${NC}"
    echo -e "访问地址: ${GREEN}http://$DOMAIN${NC}"
else
    echo -e "${YELLOW}⚠️  IP 模式: 将使用自签名证书${NC}"
    echo -e "访问地址: ${GREEN}https://$DOMAIN${NC}"
fi
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
if ! is_noninteractive; then
    read -r -p "按回车键继续部署..." _
fi

# ==================== 创建目录 ====================
log_step "[2/8] 创建目录结构..."

mkdir -p "$DOCKER_ROOT" "$SERVICE_DIR" "$DATA_DIR/postgres" "$DATA_DIR/redis" "$LOGS_DIR"
log_success "目录创建完成"

# ==================== 生成 docker-compose.yml ====================
log_step "[3/8] 生成 Docker Compose 配置..."

if [ "$USE_POSTGRESQL" = true ]; then
    cat > "$SERVICE_DIR/docker-compose.yml" <<COMPOSE_EOF
version: '3.8'

services:
  new-api:
    image: $DOCKER_IMAGE
    container_name: new-api
    restart: always
    ports:
      - "127.0.0.1:$NEWAPI_PORT:3000"
    volumes:
      - ./data:/data
      - ./logs:/app/logs
    environment:
      - SQL_DSN=postgresql://newapi:$DB_PASSWORD@postgres:5432/newapi
      - REDIS_CONN_STRING=redis://:$REDIS_PASSWORD@redis:6379
      - SESSION_SECRET=$SESSION_SECRET
      - TZ=Asia/Shanghai
      - ERROR_LOG_ENABLED=true
      - BATCH_UPDATE_ENABLED=true
      - STREAMING_TIMEOUT=300
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - $DOCKER_NETWORK
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:3000/api/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  postgres:
    image: $DB_IMAGE
    container_name: newapi-postgres
    restart: always
    environment:
      POSTGRES_USER: newapi
      POSTGRES_PASSWORD: $DB_PASSWORD
      POSTGRES_DB: newapi
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - $DOCKER_NETWORK
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U newapi"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: newapi-redis
    restart: always
    command: redis-server --requirepass $REDIS_PASSWORD --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - $DOCKER_NETWORK
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "$REDIS_PASSWORD", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

networks:
  $DOCKER_NETWORK:
    name: $DOCKER_NETWORK
    driver: bridge

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
COMPOSE_EOF
else
    cat > "$SERVICE_DIR/docker-compose.yml" <<COMPOSE_EOF
version: '3.8'

services:
  new-api:
    image: $DOCKER_IMAGE
    container_name: new-api
    restart: always
    ports:
      - "127.0.0.1:$NEWAPI_PORT:3000"
    volumes:
      - ./data:/data
      - ./logs:/app/logs
    environment:
      - SQL_DSN=newapi:$DB_PASSWORD@tcp(mysql:3306)/newapi
      - REDIS_CONN_STRING=redis://:$REDIS_PASSWORD@redis:6379
      - SESSION_SECRET=$SESSION_SECRET
      - TZ=Asia/Shanghai
      - ERROR_LOG_ENABLED=true
      - BATCH_UPDATE_ENABLED=true
      - STREAMING_TIMEOUT=300
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - $DOCKER_NETWORK
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:3000/api/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  mysql:
    image: $DB_IMAGE
    container_name: newapi-mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $DB_PASSWORD
      MYSQL_DATABASE: newapi
      MYSQL_USER: newapi
      MYSQL_PASSWORD: $DB_PASSWORD
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - $DOCKER_NETWORK
    command: --default-authentication-plugin=mysql_native_password --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p$DB_PASSWORD"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: newapi-redis
    restart: always
    command: redis-server --requirepass $REDIS_PASSWORD --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - $DOCKER_NETWORK
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "$REDIS_PASSWORD", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

networks:
  $DOCKER_NETWORK:
    name: $DOCKER_NETWORK
    driver: bridge

volumes:
  mysql_data:
    driver: local
  redis_data:
    driver: local
COMPOSE_EOF
fi

log_success "Docker Compose 配置已生成"

# ==================== 拉取镜像 ====================
log_step "[4/8] 拉取 Docker 镜像..."

cd "$SERVICE_DIR"

log_info "正在拉取镜像（可能需要几分钟）..."
if $COMPOSE_CMD pull; then
    log_success "镜像拉取完成"
else
    log_error "镜像拉取失败，请检查网络连接。"
    exit 1
fi

# ==================== 启动服务 ====================
log_step "[5/8] 启动 Docker 服务..."

log_info "正在启动容器..."
if $COMPOSE_CMD up -d; then
    log_success "容器启动成功"
else
    log_error "容器启动失败"
    $COMPOSE_CMD logs 2>/dev/null || true
    exit 1
fi

# 使用健康检查轮询替代固定 sleep
log_info "等待服务健康检查通过（最多 90 秒）..."
wait_for_healthy "$COMPOSE_CMD" "$SERVICE_DIR" 90 5 "new-api" || true

if $COMPOSE_CMD ps 2>/dev/null | grep -q "Up"; then
    log_success "服务运行正常"
else
    log_warning "服务可能未正常启动，请检查日志"
    $COMPOSE_CMD ps 2>/dev/null || true
fi

# ==================== SSL 证书 ====================
log_step "[6/8] 配置 SSL 证书..."

DOMAIN_SSL_DIR="$SSL_DIR/$DOMAIN"

if [ "$USE_HTTP_ONLY" = true ]; then
    SSL_TYPE="无 (HTTP 模式)"
    log_info "HTTP 模式，跳过 SSL 证书配置"
elif [ "$USE_DOMAIN" = true ]; then
    SSL_TYPE=$(apply_ssl_certificate "$DOMAIN" "$DOMAIN_SSL_DIR" "domain")
else
    SSL_TYPE=$(apply_ssl_certificate "$DOMAIN" "$DOMAIN_SSL_DIR" "ip")
fi

# ==================== Nginx 配置 ====================
log_step "[7/8] 配置 Nginx 反向代理..."

NGINX_SUPPORTS_HTTP3=false
if detect_nginx_http3; then
    NGINX_SUPPORTS_HTTP3=true
    log_info "检测到 HTTP/3 支持"
fi

CONF_FILE="$CONF_D/${DOMAIN}.conf"

EXISTING_DOMAIN_CONF="$(find_nginx_conf_by_server_name "$DOMAIN" "$CONF_D" || true)"
if [ -n "$EXISTING_DOMAIN_CONF" ] && ! grep -q "NEW-API-START" "$EXISTING_DOMAIN_CONF"; then
    log_error "Nginx server_name 已被其他配置占用: $EXISTING_DOMAIN_CONF"
    log_error "请为 New-API 使用独立域名，避免覆盖其他服务。"
    exit 1
fi
[ -f "$CONF_FILE" ] && backup_file "$CONF_FILE"

# 公共 location 块
read -r -d '' NGINX_LOCATION <<'NGX_LOC_EOF' || true
    #NEW-API-START
    location / {
        proxy_pass http://127.0.0.1:NEWAPI_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket 支持
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # SSE 流式响应支持
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
        chunked_transfer_encoding on;
    }
    #NEW-API-END
NGX_LOC_EOF

if [ "$USE_HTTP_ONLY" = true ]; then
    cat > "$CONF_FILE" <<NGX_HTTP
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 50m;
    tcp_nodelay on;
    access_log /var/log/nginx/newapi_access.log;
    error_log /var/log/nginx/newapi_error.log warn;
$NGINX_LOCATION
}
NGX_HTTP
elif [ "$NGINX_SUPPORTS_HTTP3" = true ]; then
    cat > "$CONF_FILE" <<NGX_H3
server {
    listen 80;
    listen 443 ssl;
    listen 443 quic;
    http2 on;
    server_name $DOMAIN;
    client_max_body_size 50m;
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

    access_log /var/log/nginx/newapi_access.log;
    error_log /var/log/nginx/newapi_error.log warn;
$NGINX_LOCATION
}
NGX_H3
else
    cat > "$CONF_FILE" <<NGX_H2
server {
    listen 80;
    listen 443 ssl;
    http2 on;
    server_name $DOMAIN;
    client_max_body_size 50m;
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

    access_log /var/log/nginx/newapi_access.log;
    error_log /var/log/nginx/newapi_error.log warn;
$NGINX_LOCATION
}
NGX_H2
fi

# 替换占位符
sed -i "s|NEWAPI_PORT_PLACEHOLDER|$NEWAPI_PORT|g" "$CONF_FILE"

log_success "Nginx 配置已生成: $CONF_FILE"

if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx || true
    log_success "Nginx 已重载"
else
    log_error "Nginx 配置测试失败"
    nginx -t 2>&1 || true
fi

# ==================== 生成凭据信息文件 ====================
log_step "[8/8] 生成凭据信息文件..."

CREDENTIALS_FILE="$SERVICE_DIR/hongaibox-credentials.txt"

if [ "$USE_HTTP_ONLY" = true ]; then
    ACCESS_URL="http://$DOMAIN"
elif [ "$USE_DOMAIN" = true ]; then
    ACCESS_URL="https://$DOMAIN"
else
    ACCESS_URL="https://$DOMAIN"
fi

write_credentials_file "$CREDENTIALS_FILE" <<INFO_EOF
================================================
       New-API Docker 部署完成 (v${COMMON_VERSION})
================================================
部署时间: $(date '+%Y-%m-%d %H:%M:%S')
访问模式: $(if [ "$USE_HTTP_ONLY" = true ]; then echo "HTTP"; elif [ "$USE_DOMAIN" = true ]; then echo "域名"; else echo "IP"; fi)
访问地址: $ACCESS_URL

⚠️ 首次访问请在 Web 界面创建管理员账号
$( [ "$USE_HTTP_ONLY" = true ] && echo "⚠️  HTTP 模式: 数据不加密，仅限内网/开发" )
$( [ "$USE_HTTP_ONLY" = false ] && [ "$USE_DOMAIN" = false ] && echo "⚠️  IP 模式: 浏览器会提示证书不安全" )

[数据库信息]
类型:      $DB_TYPE
用户名:    newapi
密码:      $DB_PASSWORD
数据库名:  newapi

[Redis 信息]
密码:      $REDIS_PASSWORD

[Session Secret]
$SESSION_SECRET

⚠️ 重要：请妥善保管以上密码信息！

[服务目录]
Docker 目录:  $SERVICE_DIR
配置文件:     $SERVICE_DIR/docker-compose.yml

[Docker 管理]
进入目录:  cd $SERVICE_DIR
查看状态:  $COMPOSE_CMD ps
查看日志:  $COMPOSE_CMD logs -f new-api
重启服务:  $COMPOSE_CMD restart

[升级]
cd $SERVICE_DIR && $COMPOSE_CMD pull && $COMPOSE_CMD up -d

[SSL 证书]
类型:      $SSL_TYPE
证书目录:  $DOMAIN_SSL_DIR/

[官方文档]
https://docs.newapi.pro/zh/docs
================================================
INFO_EOF

log_success "凭据信息已保存: $CREDENTIALS_FILE"

# ==================== 完成 ====================
clear 2>/dev/null || true
printf '%s\n' "================================================"
printf '%s\n' "       New-API Docker 部署完成 (v${COMMON_VERSION})"
printf '%s\n' "================================================"
printf '访问地址: %s\n' "$ACCESS_URL"
printf '凭据文件: %s\n' "$CREDENTIALS_FILE"
printf '%s\n' "请到凭据文件中查看数据库密码、Redis 密码和 Session Secret。"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ New-API 部署完成！${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "🔐 凭据文件: ${YELLOW}$CREDENTIALS_FILE${NC}"
echo -e "🌐 访问地址: ${GREEN}$ACCESS_URL${NC}"
echo -e "📊 服务状态: ${CYAN}cd $SERVICE_DIR && $COMPOSE_CMD ps${NC}"
echo ""
if [ "$USE_HTTP_ONLY" = true ]; then
    echo -e "${YELLOW}⚠️ HTTP 模式: 数据不加密${NC}"
elif [ "$USE_DOMAIN" = false ]; then
    echo -e "${YELLOW}⚠️ IP 模式: 证书不受信任${NC}"
fi
echo -e "${YELLOW}⚠️ 下一步: 访问 Web 界面创建管理员账号${NC}"
echo ""
log_success "日志已保存: $DEPLOY_LOG_FILE"
