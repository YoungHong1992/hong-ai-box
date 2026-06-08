#!/bin/bash

################################################################################
#
# Docker 自动安装脚本
# 版本: v3.5.0
#
# 功能说明：
#   1. 检测 Docker 是否已安装，已安装则确保服务运行
#   2. 自动修复 Debian/Ubuntu apt 源问题
#   3. 优先使用官方安装脚本，失败后按发行版手动安装
#   4. 安装 Docker Compose 插件
#   5. 启动并设置 Docker 开机自启
#
# 支持系统：
#   - Ubuntu 20.04+
#   - Debian 11+
#   - CentOS Stream 9 / Rocky / AlmaLinux / Fedora
#
# 使用方法：
#   chmod +x install_docker.sh
#   ./install_docker.sh          # 直接运行
#   ./install_docker.sh -h       # 显示帮助
#   source install_docker.sh     # 被其他脚本引用（提供 ensure_docker 函数）
#
################################################################################

# ==================== 加载公共库 ====================
LIBSH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
if [ -f "$LIBSH" ]; then
    # shellcheck source=lib/common.sh
    source "$LIBSH"
else
    echo -e "\033[0;31m[ERROR] 缺少公共库: $LIBSH\033[0m" >&2
    echo -e "请确保 lib/common.sh 存在（完整仓库克隆）。" >&2
    exit 1
fi

# ==================== 修复 apt 源 ====================

fix_apt_sources() {
    log_info "检查并修复 apt 源配置..."

    # 检测发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        local distro="$ID"
        local version="${VERSION_CODENAME:-}"
    else
        log_warning "无法检测系统发行版，跳过源修复"
        return 0
    fi

    # 针对 Debian 的修复
    if [ "$distro" = "debian" ]; then
        echo -e "${DIM}检测到 Debian $version${NC}"

        # 备份原始源文件
        if [ ! -f /etc/apt/sources.list.bak ]; then
            cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true
        fi

        # 修复 bullseye (Debian 11) 的安全源问题
        if [ "$version" = "bullseye" ]; then
            if grep -q "security.debian.org bullseye/updates" /etc/apt/sources.list 2>/dev/null; then
                log_warning "修复 Debian 11 安全源路径..."
                sed -i 's|security.debian.org bullseye/updates|security.debian.org/debian-security bullseye-security|g' /etc/apt/sources.list
            fi
            if grep -q "security.debian.org/debian bullseye/updates" /etc/apt/sources.list 2>/dev/null; then
                sed -i 's|security.debian.org/debian bullseye/updates|security.debian.org/debian-security bullseye-security|g' /etc/apt/sources.list
            fi
        fi

        # 修复 buster (Debian 10) - 已移至 archive
        if [ "$version" = "buster" ]; then
            if grep -q "deb.debian.org/debian buster" /etc/apt/sources.list 2>/dev/null; then
                log_warning "Debian 10 已结束支持，切换到 archive 源..."
                sed -i 's|deb.debian.org/debian|archive.debian.org/debian|g' /etc/apt/sources.list
                sed -i 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' /etc/apt/sources.list
                sed -i '/buster-updates/d' /etc/apt/sources.list
            fi
        fi
    fi

    # 清理并更新
    echo -e "${DIM}更新软件包列表...${NC}"
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    if apt-get update -qq 2>/dev/null; then
        log_success "apt 源配置正常"
        return 0
    else
        log_warning "apt 更新时有警告，尝试继续..."
        apt-get update --allow-releaseinfo-change 2>/dev/null || true
        return 0
    fi
}

# ==================== Docker 安装核心函数 ====================

ensure_docker() {
    # 已安装：检查版本并确保服务运行
    if command -v docker &> /dev/null; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null | grep -oP 'Docker version \K[0-9]+\.[0-9]+' || echo "unknown")
        log_success "Docker 已安装 (版本: $docker_version)"

        if ! systemctl is-active --quiet docker 2>/dev/null; then
            log_warning "Docker 服务未运行，正在启动..."
            systemctl start docker
            systemctl enable docker
        fi
        return 0
    fi

    log_step "安装 Docker..."
    echo ""

    # 先修复 apt 源
    fix_apt_sources

    # 安装必要的依赖
    echo -e "${DIM}安装依赖包...${NC}"
    apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null 2>&1

    # 方案一：使用官方安装脚本
    echo -e "${DIM}下载并运行 Docker 官方安装脚本...${NC}"

    if curl -fsSL --connect-timeout 30 https://get.docker.com -o /tmp/get-docker.sh 2>/dev/null; then
        if sh /tmp/get-docker.sh 2>&1; then
            rm -f /tmp/get-docker.sh
            systemctl start docker
            systemctl enable docker
            log_success "Docker 安装成功"
            return 0
        else
            log_warning "官方脚本安装失败，尝试手动安装..."
            rm -f /tmp/get-docker.sh
        fi
    fi

    # 方案二：手动安装
    echo -e "${DIM}使用备用安装方式...${NC}"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        local distro="$ID"
    fi

    case "$distro" in
        debian|ubuntu)
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL --connect-timeout 30 "https://download.docker.com/linux/$distro/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
            chmod a+r /etc/apt/keyrings/docker.gpg

            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$distro \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              tee /etc/apt/sources.list.d/docker.list > /dev/null

            apt-get update -qq
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|rocky|almalinux|fedora)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        *)
            log_error "不支持的发行版: $distro"
            echo -e "${YELLOW}请手动安装 Docker: https://docs.docker.com/engine/install/${NC}"
            return 1
            ;;
    esac

    # 启动 Docker 服务
    systemctl start docker
    systemctl enable docker

    # 验证安装
    if command -v docker &> /dev/null; then
        log_success "Docker 安装成功"
        docker --version
        return 0
    else
        log_error "Docker 安装失败"
        echo -e "${YELLOW}请手动安装 Docker: https://docs.docker.com/engine/install/${NC}"
        return 1
    fi
}

# ==================== 直接运行模式 ====================

# 当直接执行此脚本（非 source 引用）时，执行安装流程
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED:-}[ERROR] 必须使用 root 权限运行此脚本。"
        echo -e "${YELLOW:-}请使用: sudo ./install_docker.sh"
        exit 1
    fi

    # 处理 -h/--help
    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                echo "Docker 自动安装脚本 v${COMMON_VERSION:-3.5.0}"
                echo ""
                echo "用法:"
                echo "  ./install_docker.sh       # 安装 Docker"
                echo "  ./install_docker.sh -h    # 显示此帮助"
                echo "  source install_docker.sh  # 被其他脚本引用"
                echo ""
                echo "支持系统: Ubuntu 20.04+, Debian 11+, CentOS Stream 9+"
                exit 0
                ;;
        esac
    done

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}   Docker 自动安装程序 v${COMMON_VERSION:-3.5.0}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if ensure_docker; then
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}   Docker 环境就绪${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "Docker 版本:  $(docker --version 2>/dev/null || echo 'N/A')"
        echo -e "Compose 版本: $(docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo '未安装')"
        echo -e "服务状态:     $(systemctl is-active docker 2>/dev/null || echo 'unknown')"
        echo ""
    else
        exit 1
    fi
fi
