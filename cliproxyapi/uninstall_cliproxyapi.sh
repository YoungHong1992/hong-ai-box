#!/bin/bash

################################################################################
#
# CliproxyAPI 完全卸载脚本
# 版本: v3.5.0
#
# 功能说明：
#   - 停止并删除 Systemd 服务
#   - 删除程序/配置/数据/日志文件
#   - 删除 Nginx 配置（仅 CliproxyAPI 相关）
#   - 保留 SSL 证书（可选）
#   - 不影响其他服务
#
# 用法:
#   ./uninstall_cliproxyapi.sh       # 交互式卸载
#   ./uninstall_cliproxyapi.sh -h    # 显示帮助
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# ==================== 帮助 ====================
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "CliproxyAPI 卸载脚本 v${COMMON_VERSION}"
            echo "用法: ./uninstall_cliproxyapi.sh"
            exit 0
            ;;
    esac
done

# ==================== 环境检查 ====================
check_root
setup_logging "cliproxyapi-uninstall"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}   CliproxyAPI 卸载程序 v${COMMON_VERSION}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -r -p "确认卸载 CliproxyAPI？此操作不可恢复。(y/N): " -n 1 -r REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "已取消卸载。"
    exit 0
fi

echo ""

# ==================== 1. 停止并删除 Systemd 服务 ====================
log_step "[1/6] 停止并删除 Systemd 服务..."

if systemctl list-units --full -all 2>/dev/null | grep -q "cliproxyapi.service"; then
    systemctl stop cliproxyapi 2>/dev/null || true
    systemctl disable cliproxyapi 2>/dev/null || true
    log_success "服务已停止并禁用"
else
    log_info "服务不存在，跳过"
fi

if [ -f /etc/systemd/system/cliproxyapi.service ]; then
    rm -f /etc/systemd/system/cliproxyapi.service
    systemctl daemon-reload
    log_success "服务文件已删除"
fi

# ==================== 2. 删除程序文件 ====================
log_step "[2/6] 删除程序文件..."

if [ -d /opt/cliproxyapi ]; then
    rm -rf /opt/cliproxyapi
    log_success "程序目录已删除: /opt/cliproxyapi"
fi

# ==================== 3. 删除配置文件 ====================
log_step "[3/6] 删除配置文件..."

if [ -d /etc/cliproxyapi ]; then
    if [ -f /etc/cliproxyapi/config.yaml ]; then
        echo -e "${YELLOW}当前 API 密钥:${NC}"
        grep -A 2 "api-keys:" /etc/cliproxyapi/config.yaml 2>/dev/null | grep "sk-" | sed 's/^/  /' || true
    fi
    rm -rf /etc/cliproxyapi
    log_success "配置目录已删除: /etc/cliproxyapi"
fi

# ==================== 4-5. 删除数据和日志 ====================
log_step "[4/6] 删除数据与日志..."

rm -rf /var/lib/cliproxyapi 2>/dev/null || true
log_success "数据目录已删除"

rm -rf /var/log/cliproxyapi 2>/dev/null || true
rm -f /var/log/nginx/cliproxyapi_*.log 2>/dev/null || true
log_success "日志已清理"

# ==================== 6. 删除 Nginx 配置 ====================
log_step "[5/6] 删除 Nginx 配置..."

NGINX_CONF_DIR="/etc/nginx/conf.d"
CLIPROXY_CONFIGS=$(find "$NGINX_CONF_DIR" -name "*.conf" -exec grep -l "cliproxyapi\|8317" {} \; 2>/dev/null || true)

if [ -n "$CLIPROXY_CONFIGS" ]; then
    echo -e "${YELLOW}找到以下 Nginx 配置文件:${NC}"
    # shellcheck disable=SC2001
    echo "$CLIPROXY_CONFIGS" | sed 's/^/  /'
    echo ""

    for conf in $CLIPROXY_CONFIGS; do
        DOMAIN=$(grep "server_name" "$conf" 2>/dev/null | head -1 | awk '{print $2}' | sed 's/;//g' || echo "")
        echo -e "域名: ${YELLOW}$DOMAIN${NC}"

        rm -f "$conf"
        log_success "已删除: $conf"

        # 询问是否删除 SSL 证书
        if [ -n "$DOMAIN" ] && [ -d "/etc/nginx/ssl/$DOMAIN" ]; then
            echo ""
            read -r -p "是否删除 $DOMAIN 的 SSL 证书? (y/N): " -n 1 -r SSL_REPLY
            echo
            if [[ $SSL_REPLY =~ ^[Yy]$ ]]; then
                rm -rf "/etc/nginx/ssl/$DOMAIN"
                # 清理 acme.sh 记录
                if [ -f ~/.acme.sh/acme.sh ]; then
                    ~/.acme.sh/acme.sh --remove -d "$DOMAIN" --ecc 2>/dev/null || true
                fi
                log_success "已删除 SSL 证书"
            else
                log_info "已保留 SSL 证书"
            fi
        fi
    done

    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx || true
        log_success "Nginx 已重载"
    else
        log_error "Nginx 配置测试失败，请手动检查"
    fi
else
    log_info "未找到相关 Nginx 配置"
fi

# ==================== 7. 清理源码（可选） ====================
log_step "[6/6] 清理残留..."

if [ -d /usr/local/src/CLIProxyAPI ]; then
    echo ""
    read -r -p "是否删除源码目录 /usr/local/src/CLIProxyAPI? (y/N): " -n 1 -r SRC_REPLY
    echo
    if [[ $SRC_REPLY =~ ^[Yy]$ ]]; then
        rm -rf /usr/local/src/CLIProxyAPI
        log_success "源码目录已删除"
    fi
fi

# ==================== 完成 ====================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   卸载完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}已删除:${NC} Systemd 服务 / 程序 / 配置 / 数据 / 日志 / Nginx 配置"
echo -e "${CYAN}保留:${NC} Nginx 主程序 / 其他服务 / SSL 证书（如选择）"
echo ""
log_success "日志已保存: $DEPLOY_LOG_FILE"
