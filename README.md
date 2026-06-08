# VPS 集群部署工具

> **版本**: v3.5.0
> **更新日期**: 2026-06-08
> **许可证**: MIT

一套 VPS 集群自动化部署工具，用于构建 AI API 网关服务和代理节点。

---

## 目录

- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [项目结构](#项目结构)
- [组件说明](#组件说明)
- [部署架构](#部署架构)
- [常用命令](#常用命令)
- [常见问题](#常见问题)

---

## 环境要求

### 支持的操作系统

| 操作系统 | 版本 | 测试状态 |
|---------|------|---------|
| **Ubuntu** | 20.04 / 22.04 / 24.04 | ✅ 推荐 |
| **Debian** | 11 / 12 | ✅ 支持 |
| **CentOS Stream** | 9 | ✅ 支持（部分模块有限制） |

### 硬件要求

| 组件 | 最低配置 | 推荐配置 |
|------|---------|---------|
| **nginx** | 512MB 内存, 500MB 磁盘 | 1GB 内存, 2GB 磁盘 |
| **cliproxyapi** | 256MB 内存 | 512MB 内存 |
| **new-api** | 1GB 内存 (Docker) | 2GB 内存 |
| **pi-coding-agent** | 500MB 磁盘 | 512MB 内存 |

### 前置条件

- **Root 权限**: 所有脚本需要 root 用户执行
- **网络连接**: 需要访问 GitHub、Docker Hub 等
- **域名（可选）**: 申请 SSL 证书需要已解析的域名（[Cloudflare DNS 配置指南](docs/cloudflare-dns-guide.md)）；也支持 IP 模式（自签名证书）和 HTTP 模式
- **端口开放**: 80 (HTTP), 443 (HTTPS)

---

## 快速开始

### 方式一：引导式部署（推荐）

```bash
cd vps_deployment_ai_tools
chmod +x deploy_cluster.sh
./deploy_cluster.sh
```

脚本按顺序引导完成各组件安装：Nginx → Docker → CliproxyAPI → New-API → Pi。

### 方式二：单独部署

```bash
# 仅部署 Nginx
cd nginx && ./install_nginx.sh

# 仅部署 New-API（会自动安装 Docker）
cd new-api && ./install_newapi_docker.sh

# 仅部署 Pi Coding Agent
cd pi-coding-agent && ./install_pi.sh
```

### 查看帮助

```bash
./deploy_cluster.sh -h
./deploy_cluster.sh --version
```

所有子脚本同样支持 `-h` / `--help` 查看详细说明。

---

## 项目结构

```
vps_deployment_ai_tools/
├── deploy_cluster.sh              # 全流程部署引导脚本
├── README.md                      # 本文档
│
├── lib/                           # 公共函数库
│   └── common.sh                  # 颜色、日志、安全检查、SSL 等
│
├── docs/                          # 辅助文档
│   └── cloudflare-dns-guide.md    # Cloudflare DNS 配置指南
│
├── overview/                      # 项目总览与指引
│   └── README.md
│
├── nginx/                         # Nginx 基础设施（必选）
│   ├── install_nginx.sh
│   └── README.md
│
├── docker/                        # Docker 容器环境（推荐）
│   ├── install_docker.sh
│   └── README.md
│
├── cliproxyapi/                   # CliproxyAPI 轻量代理
│   ├── install_cliproxyapi_v2.sh
│   ├── apply_ssl.sh
│   ├── uninstall_cliproxyapi.sh
│   └── README.md
│
├── new-api/                       # New-API AI 网关
│   ├── install_newapi_docker.sh
│   ├── docker-compose.yml
│   ├── upgrade_newapi_docker.sh
│   ├── upgrade_newapi_alpha.sh
│   ├── uninstall_newapi_docker.sh
│   └── README.md
│
├── pi-coding-agent/               # Pi 终端编程助手
│   ├── install_pi.sh
│   └── README.md
│
└── science/                       # 网络工具（独立，手动部署）
    ├── setup.sh
    └── README.md
```

---

## 组件说明

### nginx - Nginx 基础设施【必选】

> **部署方式**: 官方仓库安装

- Nginx 来自 nginx.org 官方主线仓库，支持 HTTP/3 (QUIC)
- 自动开启 TCP BBR，优化系统内核参数
- 构建模块化配置结构 (conf.d/)
- 自动备份已有配置文件

```bash
cd nginx && ./install_nginx.sh
```

---

### docker - Docker 容器环境【推荐】

> **部署方式**: 自动安装

- Docker Engine + Docker Compose 插件
- 自动修复 Debian/Ubuntu apt 源问题
- 官方脚本优先，失败后按发行版手动安装
- 支持直接运行和 `source` 引用两种模式

New-API 等 Docker 服务的前置依赖。

```bash
cd docker && ./install_docker.sh
```

---

### cliproxyapi - CliproxyAPI 轻量代理

> **依赖**: nginx | **部署方式**: 二进制 + Systemd

- 轻量级 AI API 转发代理，资源占用极低（~50MB）
- 支持 OpenAI、Claude、Gemini 等主流 AI 模型 API
- 适合低配 VPS（内存 < 1GB）
- 使用 openssl rand 生成安全密钥

```bash
cd cliproxyapi && ./install_cliproxyapi_v2.sh
```

---

### new-api - New-API AI 网关

> **依赖**: nginx, Docker | **部署方式**: Docker Compose

- 新一代大模型网关与 AI 资产管理系统
- 支持 OpenAI、Claude、Gemini、Azure 等多种模型聚合
- 完整的用户管理、令牌分组、计费系统
- 技术栈：Docker Compose + PostgreSQL/MySQL + Redis
- 使用 openssl rand 生成安全密码
- 健康检查轮询替代固定延时等待

```bash
cd new-api && ./install_newapi_docker.sh
```

---

### pi-coding-agent - Pi 终端编程助手

> **依赖**: Node.js (脚本自动安装) | **部署方式**: npm 全局安装

- 极简终端编程助手，支持交互式和非交互式模式
- 支持 Anthropic、OpenAI、Google Gemini、DeepSeek 等多种 AI 提供商
- 可自定义扩展、技能包、提示词模板和主题
- 无需本地 GPU，通过 API Key 连接远程 AI 服务

```bash
cd pi-coding-agent && ./install_pi.sh
```

---

### science - 网络工具

> **依赖**: 无 | **部署方式**: Xray 二进制直连

- VLESS + XTLS-Vision + Reality 协议
- 无需域名、无需 SSL 证书
- 自动生成 X25519 密钥，完美伪造目标站点证书
- 不包含在主部署脚本中，需手动执行

```bash
cd science && ./setup.sh
```

---

## 部署架构

### 依赖关系

```
nginx (必选)
    ↓
docker (推荐)
    ↓
┌───┴───┬───────────┐
↓       ↓           ↓
cliproxy  new-api

pi-coding-agent (独立)
    ↓ (通过 API 或 SSH 转发)
cliproxyapi / new-api

science (独立，手动部署，无需依赖)
```

### 访问模式

所有服务脚本均支持三种访问模式：

| 模式 | SSL 证书 | 适用场景 |
|------|----------|----------|
| **域名模式** | Let's Encrypt（自动申请） | 生产环境（推荐） |
| **IP 模式** | 自签名证书 | 测试环境/无域名场景 |
| **HTTP 模式** | 无 | 内网/开发环境 |

### SSL 安全基线

所有 Nginx 配置统一使用 **TLSv1.2+**，已移除不安全的 TLSv1.1。

### 多服务域名配置

> **⚠️ 重要**：同一台服务器部署多个服务时，必须为每个服务使用不同的子域名。
>
> Nginx 配置文件路径为 `/etc/nginx/conf.d/{域名}.conf`，相同域名会导致配置覆盖。
>
> 正确示例：`proxy.example.com`、`api.example.com`、`newapi.example.com`

---

## 常用命令

### Nginx

```bash
systemctl status nginx
nginx -t
systemctl reload nginx
tail -f /var/log/nginx/error.log
```

### Docker / New-API

```bash
cd /opt/docker-services/new-api
docker compose ps
docker compose logs -f new-api
docker compose restart
```

### SSL 证书

```bash
~/.acme.sh/acme.sh --list
~/.acme.sh/acme.sh --renew -d example.com --ecc --force
systemctl reload nginx
```

### Pi Coding Agent

```bash
pi --version                    # 查看版本
pi -p "任务描述"                  # 非交互式单次任务
pi -c                           # 继续上次会话
npm update -g @earendil-works/pi-coding-agent  # 更新 Pi
```

---

## 常见问题

### 1. 脚本执行报错 "Permission denied"

```bash
chmod +x *.sh && ./install_xxx.sh
```

### 2. Docker 服务启动失败

```bash
docker compose logs           # 查看详细日志
netstat -tlnp | grep :3000    # 检查端口占用
```

### 3. SSL 证书申请失败

- 确保域名已正确解析到服务器
- 确保 80 端口开放且未被占用
- Proxy status 设为 DNS only（关闭 Cloudflare CDN 代理）

```bash
dig +short your-domain.com
netstat -tlnp | grep :80
```

### 4. 内存不足

对于低配 VPS（<1GB），建议使用 CliproxyAPI 而非 New-API。脚本会自动创建 Swap 空间。

### 5. Pi 安装后无法使用

- 确保 Node.js >= 18 已安装: `node --version`
- 确保 API Key 已配置: `export ANTHROPIC_API_KEY=sk-ant-...`
- 检查网络是否可达对应 AI 服务端点

---

## deploy_cluster.sh 说明

全流程部署引导脚本，按顺序引导安装：

```bash
./deploy_cluster.sh

# 脚本依次询问：
# 1. 安装 Nginx（必选）
# 2. 安装 Docker（推荐）
# 3. 安装 CliproxyAPI（可选）
# 4. 安装 New-API（可选）
# 5. 安装 Pi Coding Agent（可选）
```

支持 `-h` 查看帮助，`--version` 查看版本。

---

## 安全说明

- 所有密码和密钥使用 `openssl rand` 生成（加密安全随机数）
- SSL/TLS 最低版本: TLSv1.2（已移除不安全的 TLSv1.1）
- 安装日志自动记录到 `/var/log/vps-deploy/`
- Nginx 配置会先备份再覆盖，防止配置丢失
- 数据库和 Redis 密码均为随机生成，不硬编码

---

**最后更新**: 2026-06-08
