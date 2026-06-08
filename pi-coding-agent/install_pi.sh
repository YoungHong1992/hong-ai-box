#!/bin/bash
#
# Pi Coding Agent 安装脚本
# 版本: v3.5.0
# 更新日期: 2026-06-08
# 依赖: Node.js >= 18 (脚本会自动安装)
#
# 用法:
#   chmod +x install_pi.sh
#   ./install_pi.sh              # 交互式安装
#   ./install_pi.sh -h           # 显示帮助
#   ./install_pi.sh --no-prompt  # 非交互式安装
#

set -euo pipefail

# ==================== 加载公共库 ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# ==================== 帮助信息 ====================
show_help() {
    cat <<'EOF'
Pi Coding Agent 安装脚本

用法:
  ./install_pi.sh              # 交互式安装
  ./install_pi.sh --no-prompt  # 非交互式安装（跳过确认）
  ./install_pi.sh -h           # 显示此帮助

说明:
  1. 检测并安装 Node.js (v22 LTS)
  2. 通过 npm 全局安装 pi-coding-agent

环境要求:
  - Root 权限
  - 网络连接（npm registry, nodesource.com）
EOF
    exit 0
}

# ==================== 参数解析 ====================
NO_PROMPT=false
for arg in "$@"; do
    case "$arg" in
        -h|--help) show_help ;;
        --no-prompt) NO_PROMPT=true ;;
    esac
done

# ==================== 安装流程 ====================
check_root
setup_logging "pi-install"

echo "============================================"
echo "   Pi Coding Agent 安装脚本 v${COMMON_VERSION}"
echo "============================================"
echo ""

if [ "$NO_PROMPT" = false ]; then
    if ! confirm "是否开始安装？"; then
        log_info "安装已取消。"
        exit 0
    fi
fi

# === Step 1: 安装 Node.js ===
log_step "Step 1/2: 检测 Node.js..."

if command -v node &>/dev/null; then
    NODE_VERSION=$(node --version | sed 's/v//')
    log_success "Node.js 已安装 (v${NODE_VERSION})"
else
    log_info "安装 Node.js v22 LTS..."
    curl -fsSL --connect-timeout 30 https://deb.nodesource.com/setup_22.x | bash - || { log_error "Node.js 安装失败"; exit 1; }
    apt-get install -y nodejs
    echo ""
    log_success "Node.js 安装完成: $(node --version)"
    log_info "npm 版本: $(npm --version)"
fi

# === Step 2: 安装 Pi ===
log_step "Step 2/2: 安装 Pi Coding Agent..."

if command -v pi &>/dev/null; then
    PI_VERSION=$(pi --version 2>/dev/null || echo "unknown")
    log_warning "Pi 已安装 (v${PI_VERSION})，升级到最新版..."
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
else
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
fi

echo ""
log_success "Pi Coding Agent 安装完成!"
log_info "版本: $(pi --version 2>/dev/null || echo 'unknown')"
log_info "路径: $(which pi)"
echo ""
echo "============================================"
echo "  使用方法:"
echo "    pi                # 交互模式"
echo "    pi -p \"提示词\"    # 非交互模式"
echo "    pi --help         # 查看帮助"
echo ""
echo "  配置 API Key:"
echo "    export ANTHROPIC_API_KEY=sk-ant-..."
echo "    pi"
echo "============================================"
echo ""
log_success "日志已保存: $DEPLOY_LOG_FILE"
