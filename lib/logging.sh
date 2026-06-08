#!/bin/bash
# shellcheck shell=bash
################################################################################
# 日志系统
################################################################################

readonly DEPLOY_LOG_DIR="/var/log/vps-deploy"

setup_logging() {
    local script_name="${1:-deploy}"
    mkdir -p "$DEPLOY_LOG_DIR"
    DEPLOY_LOG_FILE="${DEPLOY_LOG_DIR}/${script_name}-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$DEPLOY_LOG_FILE") 2>&1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === 日志开始: $DEPLOY_LOG_FILE ==="
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 脚本: $script_name"
}

log_info()    { echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%H:%M:%S') $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%H:%M:%S') $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*" >&2; }
log_step()    { echo -e "${CYAN}[STEP]${NC} $(date '+%H:%M:%S') $*"; }
log_debug()   { echo -e "${DIM}[DEBUG]${NC} $(date '+%H:%M:%S') $*"; }
