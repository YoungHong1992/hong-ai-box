# hongaibox — 洪哥的 AI 工具箱

> **版本**: v4.0.0
> **更新日期**: 2026-06-08
> **许可证**: MIT

一套面向云服务器的 AI 工具自动化部署工具，采用现代化 TUI（Text User Interface）交互，让你通过键盘方向键、空格、回车即可完成整套 AI 集群的部署。

---

## 特性

- 🖥️ **交互式 TUI**：基于 [Bubble Tea](https://github.com/charmbracelet/bubbletea) 的现代化终端界面，告别繁琐的命令行问答
- 🚀 **一键部署**：勾选服务 → 填写配置 → 确认安装，三步完成
- 📦 **单二进制分发**：编译为单个可执行文件，零依赖，跨发行版
- 🔒 **安全基线**：密码/密钥由 `crypto/rand` 生成，TLS 1.2+，自动 SSL 证书
- 🧩 **模块化后端**：后端安装逻辑渐进式复用 Bash 脚本，稳定可靠

---

## 快速开始

### 从源码构建

```bash
git clone https://github.com/hongge/hongaibox.git
cd hongaibox
make build
sudo ./hongaibox
```

### 查看帮助

```bash
./hongaibox -h
./hongaibox --version
```

---

## 项目结构

```
hongaibox/
├── cmd/hongaibox/              # Go 主入口
├── internal/
│   ├── app/                    # Bubble Tea TUI 应用
│   ├── wizard/                 # 服务定义与配置结构
│   └── backend/                # Bash 脚本执行器
├── scripts/                    # 后端安装脚本（Bash）
│   ├── nginx/
│   ├── docker/
│   ├── cliproxyapi/
│   ├── new-api/
│   ├── pi-coding-agent/
│   ├── science/
│   └── lib/                    # Bash 公共库
├── tests/                      # Bats 测试
├── docs/                       # 辅助文档
└── Makefile
```

---

## 组件说明

| 组件 | 描述 | 资源需求 |
|------|------|----------|
| **Nginx** | HTTP/3 (QUIC) + BBR 优化，所有服务的基础设施 | 512MB 内存 |
| **Docker** | Docker Engine + Compose 插件 | 无额外需求 |
| **CliproxyAPI** | 轻量 AI API 转发代理 (~50MB) | 256MB 内存 |
| **New-API** | AI 模型网关与资产管理系统 | ≥ 1GB 内存 |
| **Pi** | 终端 AI 编程助手 | 500MB 磁盘 |
| **Science** | VLESS + XTLS-Vision + Reality | 极低 |

---

## 开发

### 构建

```bash
make build
```

### 测试

```bash
make test       # Go 单元测试
make shellcheck # Bash 脚本静态检查
```

### 依赖

- Go 1.24+
- Bubble Tea / Huh / Lipgloss / Bubbles

---

## 安全说明

- 所有密码和密钥使用加密安全随机数生成
- SSL/TLS 最低版本: TLSv1.2
- 安装日志自动记录到 `/var/log/vps-deploy/`
- Nginx 配置先备份再覆盖

---

**最后更新**: 2026-06-08
