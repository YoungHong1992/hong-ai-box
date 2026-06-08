#!/bin/bash
# shellcheck shell=bash
################################################################################
# 系统检测
################################################################################

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
