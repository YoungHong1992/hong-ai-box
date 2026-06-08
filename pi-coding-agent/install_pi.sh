#!/bin/bash
#
# Pi Coding Agent 安装脚本
# 版本: v1.0
# 更新日期: 2026-06-05
# 依赖: Node.js >= 18 (脚本会自动安装)
#
# 用法:
#   chmod +x install_pi.sh
#   ./install_pi.sh
#
# 说明:
#   1. 检测并安装 Node.js (v22 LTS)
#   2. 通过 npm 全局安装 pi-coding-agent
#

set -e

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

log_step() { echo -e "${CYAN}[$(date +%H:%M:%S)]${RESET} ${GREEN}$*${RESET}"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }

echo "============================================"
echo "   Pi Coding Agent 安装脚本"
echo "============================================"
echo ""

# === Step 1: 检查 root 权限 ===
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 用户执行此脚本"
    exit 1
fi

# === Step 2: 安装 Node.js ===
log_step "Step 1/2: 检测 Node.js..."

if command -v node &>/dev/null; then
    NODE_VERSION=$(node --version | sed 's/v//')
    log_warn "Node.js 已安装 (v${NODE_VERSION})，跳过"
else
    log_step "安装 Node.js v22 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
    echo ""
    log_step "Node.js 安装完成: $(node --version)"
    log_step "npm 版本: $(npm --version)"
fi

# === Step 3: 安装 Pi ===
log_step "Step 2/2: 安装 Pi Coding Agent..."

if command -v pi &>/dev/null; then
    PI_VERSION=$(pi --version 2>/dev/null || echo "unknown")
    log_warn "Pi 已安装 (v${PI_VERSION})，升级到最新版..."
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
else
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
fi

echo ""
log_step "Pi Coding Agent 安装完成!"
log_step "版本: $(pi --version)"
log_step "路径: $(which pi)"
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
