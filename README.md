# hongaibox — 洪哥的 AI 工具箱

> **版本**: v4.0.0
> **更新日期**: 2026-06-22
> **许可证**: MIT

一套面向云服务器的 AI 工具自动化部署脚本，选择服务 → 填写配置 → 一键安装，三步完成整套 AI 集群的部署。

---

## ✨ 特性

- 🚀 **一键部署**：一个脚本，勾选服务即可安装全部组件
- 🎨 **彩色终端界面**：清晰的交互式引导，告别繁琐的命令行问答
- 🔒 **安全基线**：密码/密钥自动生成，TLS 1.2+，自动 SSL 证书
- 📦 **零依赖**：纯 Bash 实现，兼容 Debian/Ubuntu，无需安装额外运行时
- 🧩 **模块化**：每个服务可独立安装，也可通过总入口一键部署

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

```bash
cd scripts
sudo ./nginx/install_nginx.sh          # 安装 Nginx
sudo ./docker/install_docker.sh        # 安装 Docker
sudo ./cliproxyapi/install_cliproxyapi_v2.sh  # 安装 CliproxyAPI
sudo ./new-api/install_newapi_docker.sh      # 安装 New-API
sudo ./pi-coding-agent/install_pi.sh         # 安装 Pi
sudo ./science/install_science.sh            # 安装 Science
```

---

## 📁 项目结构

```
hong-ai-box/
├── install.sh                  # 🎯 总入口：一键部署全部组件
├── scripts/                    # 安装脚本
│   ├── nginx/                  #   Nginx (HTTP/3 + BBR)
│   ├── docker/                 #   Docker Engine + Compose
│   ├── cliproxyapi/            #   轻量 AI API 转发代理
│   ├── new-api/                #   AI 模型网关
│   ├── pi-coding-agent/        #   终端 AI 编程助手
│   ├── science/                #   VLESS + Reality
│   └── lib/                    #   公共函数库（日志、颜色、网络等）
├── docs/                       # 辅助文档
└── README.md
```

---

## 📦 组件说明

| 组件 | 描述 | 资源需求 |
|------|------|----------|
| **Nginx** | HTTP/3 (QUIC) + BBR 优化，所有服务的基础设施 | 512MB 内存 |
| **Docker** | Docker Engine + Compose 插件 | 无额外需求 |
| **CliproxyAPI** | 轻量 AI API 转发代理 (~50MB) | 256MB 内存 |
| **New-API** | AI 模型网关与资产管理系统 | ≥ 1GB 内存 |
| **Pi** | 终端 AI 编程助手 | 500MB 磁盘 |
| **Science** | VLESS + XTLS-Vision + Reality | 极低 |

---

## 🛠 使用流程

```
1. 检测 → 自动发现已安装的服务
2. 选择 → 输入数字选择要安装的服务（支持多选）
3. 配置 → 设置访问方式（域名/IP/HTTP）和各项参数
4. 确认 → 查看配置总览，确认无误
5. 安装 → 按依赖顺序自动执行安装脚本
6. 完成 → 显示总结和常用管理命令
```

> 同时部署 CliproxyAPI 与 New-API 时，请为每个 Web 服务准备独立域名，避免多个服务争用同一个 Nginx `server_name` 和 `/` 路由。

---

## 🔒 安全说明

- 所有密码和密钥使用加密安全随机数生成
- SSL/TLS 最低版本: TLSv1.2
- 安装日志自动记录到 `/var/log/vps-deploy/`
- Nginx 配置先备份再覆盖
- 支持域名（Let's Encrypt）和 IP（自签名）两种证书模式

---

## 🧪 开发

### ShellCheck 静态检查

```bash
# 安装 shellcheck
apt-get install -y shellcheck

# 语法检查
find . -path ./.git -prune -o -name '*.sh' -print0 | xargs -0 -n1 bash -n

# ShellCheck
find . -path ./.git -prune -o -name '*.sh' -print0 | xargs -0 shellcheck -x -S warning
```

---

**最后更新**: 2026-06-22
