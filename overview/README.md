# VPS 集群部署工具 — 项目总览

> **版本**: v3.3
> **更新日期**: 2026-06-08
> **许可证**: MIT

本目录是项目的**序/指引目录**，不包含可执行脚本，仅提供项目架构、依赖关系和快速导航。

---

## 模块索引

| 目录 | 名称 | 类型 | 说明 |
|------|------|------|------|
| `overview/` | 项目总览 | 📖 文档 | 本文档，项目入口指引 |
| `nginx/` | Nginx 基础设施 | 🔧 必选 | HTTP/3 反向代理，所有服务基础 |
| `docker/` | Docker 容器环境 | 🔧 推荐 | New-API 等容器服务前置依赖 |
| `cliproxyapi/` | CliproxyAPI 轻量代理 | 🤖 可选 | 轻量 AI API 转发（~50MB 内存） |
| `new-api/` | New-API AI 网关 | 🤖 可选 | 完整大模型网关 + 资产管理 |
| `pi-coding-agent/` | Pi 终端编程助手 | 💻 可选 | 终端 AI 编程助手 |
| `science/` | 网络工具 | 🌐 独立 | VLESS + Reality，无需域名/证书，手动部署 |

---

## 依赖关系

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

science (独立，手动部署)
```

---

## 推荐部署顺序

```bash
# 方式一：引导式一键部署（不含 science）
./deploy_cluster.sh

# 方式二：按需单独部署
cd nginx && ./install_nginx.sh                  # 1. 基础设施（必选）
cd docker && ./install_docker.sh                # 2. 容器环境（推荐）
cd new-api && ./install_newapi_docker.sh        # 3. AI 网关
cd cliproxyapi && ./install_cliproxyapi_v2.sh   # 或轻量代理
cd pi-coding-agent && ./install_pi.sh           # 5. 编程助手（可选）
cd science && ./setup.sh                        # 手动：网络工具（独立）
```

---

## 访问模式

所有服务统一支持三种模式：

| 模式 | SSL 证书 | 适用场景 |
|------|----------|----------|
| **域名模式** | Let's Encrypt（自动） | 生产环境（推荐） |
| **IP 模式** | 自签名证书 | 测试 / 无域名 |
| **HTTP 模式** | 无 | 内网 / 开发 |

---

## 相关文档

- [Cloudflare DNS 配置指南](../docs/cloudflare-dns-guide.md)
- [项目 README](../README.md)
