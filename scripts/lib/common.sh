#!/bin/bash
# shellcheck shell=bash
################################################################################
#
# VPS 部署工具 — 公共函数库入口
#
# 版本: v4.0.0
# 用法:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   source "$SCRIPT_DIR/../lib/common.sh"
#
# 说明:
#   本文件仅作为统一入口，按顺序加载各子模块。
#   如需按需加载，可直接 source 子模块文件。
#
################################################################################

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/colors.sh
source "$_LIB_DIR/colors.sh"
# shellcheck source=lib/logging.sh
source "$_LIB_DIR/logging.sh"
# shellcheck source=lib/security.sh
source "$_LIB_DIR/security.sh"
# shellcheck source=lib/system.sh
source "$_LIB_DIR/system.sh"
# shellcheck source=lib/network.sh
source "$_LIB_DIR/network.sh"
# shellcheck source=lib/ssl.sh
source "$_LIB_DIR/ssl.sh"
# shellcheck source=lib/nginx.sh
source "$_LIB_DIR/nginx.sh"
# shellcheck source=lib/docker.sh
source "$_LIB_DIR/docker.sh"
# shellcheck source=lib/interactive.sh
source "$_LIB_DIR/interactive.sh"
