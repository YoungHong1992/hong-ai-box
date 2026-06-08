#!/bin/bash
# shellcheck shell=bash
################################################################################
# Bats 测试公共辅助函数
#
# 自动 mock log_* 和颜色变量，避免测试依赖真实终端
# 用法: 在 bats 文件的 setup() 中:
#         load helpers
#         load_lib security system  # 按需加载
################################################################################

# ─── 加载库模块 ────────────────────────────────────────────────

load_lib() {
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
    for mod in "$@"; do
        # shellcheck disable=SC1090
        source "${lib_dir}/${mod}.sh"
    done
}

# ─── Mock 颜色变量（在 lib 加载后覆盖，避免 \033 在 TAP 输出中产生乱码）──

RED=""
GREEN=""
YELLOW=""
BLUE=""
MAGENTA=""
CYAN=""
WHITE=""
NC=""
BOLD=""
DIM=""

# 版本号（部分被测函数引用）
COMMON_VERSION="${COMMON_VERSION:-3.5.0}"

# ─── Mock 日志函数（静默输出，测试可按需覆盖）─────────────────

log_info()    { :; }
log_success() { :; }
log_warning() { :; }
log_error()   { :; }
log_step()    { :; }
log_debug()   { :; }

print_header()  { :; }
print_divider() { :; }
print_section() { :; }
