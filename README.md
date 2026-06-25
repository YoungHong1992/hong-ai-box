# hongaibox — 洪哥的 AI 工具箱

> **版本**: v4.0.0
> **更新日期**: 2026-06-23
> **许可证**: MIT

一套面向云服务器的 AI 工具自动化部署脚本，选择服务 → 填写配置 → 一键安装，三步完成整套 AI 集群的部署。

---

## ✨ 特性

- 🚀 **一键部署**：一个脚本，勾选服务即可安装常用 AI 组件
- 🎨 **彩色终端界面**：清晰的交互式引导，告别繁琐的命令行问答
- 🔒 **安全基线**：fail2ban、swap、日志限制、TLS 1.2+，自动 SSL 证书
- 📦 **零依赖**：纯 Bash 实现，兼容 Debian/Ubuntu，无需安装额外运行时
- 🧩 **模块化**：每个服务可独立安装，也可通过总入口一键部署
- 🐳 **Compose 优先**：CPA / New-API 默认采用 Docker Compose，CPA 保留裸机安装选项

---

## 🚀 快速开始

### 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/YoungHong1992/hong-ai-box/main/install.sh | sudo bash
```

> 该命令会先下载完整仓库到临时目录，再启动交互式安装；如需固定版本，可改用 release 页面中的 tag 命令。

### 下载完整包安装

```bash
curl -fsSLO https://github.com/YoungHong1992/hong-ai-box/releases/latest/download/hong-ai-box.tar.gz
tar xzf hong-ai-box.tar.gz
cd hong-ai-box
sudo ./install.sh
```

### 克隆仓库安装

```bash
git clone https://github.com/YoungHong1992/hong-ai-box.git
cd hong-ai-box
sudo ./install.sh
```

### 单独安装某个服务

在完整仓库内，每个组件目录都可独立进入并运行统一命名的 `install.sh`；组件脚本会复用仓库内 `lib/` 公共库，请不要只复制单个组件脚本运行。

```bash
cd maintenance && sudo ./install.sh        # 安装服务器维护基线
cd ../nginx && sudo ./install.sh           # 安装 Nginx
cd ../docker && sudo ./install.sh          # 安装 Docker
cd ../cliproxyapi && sudo ./install.sh     # 安装 CliproxyAPI（默认 Docker Compose）
# CPA 裸机安装：cd ../cliproxyapi && sudo HONGAIBOX_CLIPROXY_DEPLOY_MODE=bare ./install.sh
cd ../new-api && sudo ./install.sh         # 安装 New-API
cd ../pi-coding-agent && sudo ./install.sh # 安装 Pi
```

> CliproxyAPI / New-API 需要已安装 Nginx；默认 Docker Compose 部署还需要 Docker + Compose。缺少依赖时，对应脚本会提示先安装依赖后再继续。CPA 如需裸机二进制 + Systemd，可设置 `HONGAIBOX_CLIPROXY_DEPLOY_MODE=bare`。

---

## 📁 项目结构

```
hong-ai-box/
├── install.sh                  # 🎯 总入口：部署常用 AI 组件
├── lib/                        # 公共 Bash 工具库（凭据写入等）
├── maintenance/                # 服务器维护基线 (fail2ban / swap / 日志限制)
├── nginx/                      # Nginx (HTTP/3 + BBR)
├── docker/                     # Docker Engine + Compose
├── cliproxyapi/                # 轻量 AI API 转发代理
├── new-api/                    # AI 模型网关
├── pi-coding-agent/            # 终端 AI 编程助手
├── docs/                       # 辅助文档
├── tests/                      # 静态检查、凭据与集成测试脚本
└── README.md
```

---

## 📦 组件说明

| 组件 | 描述 | 资源需求 |
|------|------|----------|
| **Maintenance** | fail2ban、swap、journald 限制、Docker 日志轮转 | 基础维护 |
| **Nginx** | HTTP/3 (QUIC) + BBR 优化，所有服务的基础设施 | 512MB 内存 |
| **Docker** | Docker Engine + Compose 插件 | 无额外需求 |
| **CliproxyAPI** | 轻量 AI API 转发代理，默认 Docker Compose，可选裸机 | 256MB 内存 |
| **New-API** | AI 模型网关与资产管理系统，Docker Compose | ≥ 1GB 内存 |
| **Pi** | 终端 AI 编程助手 | 500MB 磁盘 |

---

## 🛠 使用流程

```
1. 检测 → 自动发现已安装的服务
2. 选择 → 输入表格序号选择 1 个服务；已安装服务也可选择
3. 概览 → 查看该服务当前状态；确认继续安装/覆盖，或返回首页
4. 配置 → 设置访问方式（域名/IP/HTTP）和各项参数
5. 确认 → 查看配置总览，确认无误
6. 安装 → 按依赖顺序自动执行安装脚本
7. 完成 → 显示总结和常用管理命令，可回到首页继续安装其他服务
```

> 同时部署 CliproxyAPI 与 New-API 时，请为每个 Web 服务准备独立域名，避免多个服务争用同一个 Nginx `server_name` 和 `/` 路由。

---

## 🔒 安全说明

- 所有密码和密钥使用加密安全随机数生成
- SSL/TLS 最低版本: TLSv1.2
- 安装日志自动记录到 `/var/log/vps-deploy/`
- fail2ban 默认启用 SSH 防暴力破解
- swap 自动按内存配置，降低小内存 VPS OOM 风险
- journald / Docker 日志轮转限制磁盘占用
- Nginx 配置先备份再覆盖
- 支持域名（Let's Encrypt）和 IP（自签名）两种证书模式

---

## 🧪 开发

### 本地测试

```bash
# 安装 shellcheck
apt-get install -y shellcheck

# 静态检查 + 仓库测试
./tests/run.sh

# 真实安装幂等测试（会修改当前机器维护基线，建议只在 CI/临时机执行）
sudo ./tests/test-maintenance-idempotency.sh
```

---

**最后更新**: 2026-06-23
