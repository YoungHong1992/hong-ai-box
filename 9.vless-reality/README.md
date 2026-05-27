# VLESS + Reality 代理节点

> **版本**: v1.0
> **协议**: VLESS + XTLS-Vision + Reality
> **伪装目标**: www.microsoft.com

---

## 概述

基于 Xray-core 的 VLESS + Reality 代理节点，是目前最先进的代理方案之一。

### 为什么选择 Reality？

| 特性 | VMess + TLS 自签 | VLESS + Reality |
|------|:---:|:---:|
| 需要域名 | ✅ 推荐 | ❌ 不需要 |
| 需要 SSL 证书 | ✅ 需要 | ❌ 不需要 |
| 证书指纹 | 自签 → 暴露 | 偷真站 → 完美 |
| 被主动探测风险 | 高 | 极低 |
| 延迟 | 中等 | 极低 |
| GFW 抗性 | ⭐⭐ | ⭐⭐⭐⭐⭐ |

### 核心原理

Reality 通过 X25519 密钥对，动态复现目标站点（如 microsoft.com）的 TLS 握手特征。GFW 主动探测时返回的是真实证书，无法区分这是代理还是正常流量。

---

## 快速部署

```bash
cd 9.vless-reality
chmod +x install_reality.sh
./install_reality.sh
```

### 前置条件

- **Root 权限**
- **境外 VPS**（Debian / Ubuntu / CentOS）
- **端口 443 未被占用**（脚本会自动处理 Nginx 冲突）
- **无需域名**
- **无需 SSL 证书**

### 脚本做了什么

1. 生成 X25519 密钥对（核心：Reality 依赖此密钥伪造证书）
2. 生成 random UUID + shortId
3. 自动处理现有 Nginx 的 443 端口冲突
4. 安装 Xray-core 最新版
5. 配置 VLESS Reality 入站（端口 443）
6. 启用 BBR 加速
7. 生成客户端连接信息

---

## 客户端配置

### 通用参数

| 参数 | 值 |
|------|-----|
| 协议 | VLESS |
| 地址 | 服务器 IP |
| 端口 | 443 |
| UUID | 自动生成 |
| Flow | xtls-rprx-vision |
| 传输 | tcp |
| 安全 | reality |
| SNI | www.microsoft.com |
| Fingerprint | chrome |
| Public Key | 自动生成 |
| shortId | 自动生成 |

### 各客户端

- **v2rayN (Windows)**: 添加 VLESS 服务器 → 填写参数
- **Shadowrocket (iOS)**: 类型选 VLESS → Reality
- **v2rayNG (Android)**: 手动输入 VLESS + Reality
- **sing-box**: 支持 VLESS Reality 出站

---

## 服务管理

```bash
# 查看状态
systemctl status xray

# 重启
systemctl restart xray

# 查看日志
journalctl -u xray -f

# 停止
systemctl stop xray

# 卸载
systemctl stop xray && systemctl disable xray
rm -rf /usr/local/bin/xray /usr/local/etc/xray /var/log/xray
rm -f /etc/systemd/system/xray.service
systemctl daemon-reload
```

---

## 与现有 V2Ray 共存

如果服务器已安装 VMess + Nginx：

- Reality 占用 443 端口（最佳伪装）
- 脚本会自动迁移 Nginx 的 443 监听
- Nginx 继续在 80 端口提供 HTTP 服务
- 旧 VMess 节点失效（推荐迁移到 Reality）

---

## 安全建议

1. **定期更换 UUID**：编辑 `/usr/local/etc/xray/config.json` 后 `systemctl restart xray`
2. **更换伪装目标**：将 `dest` 改为其他大站（apple.com, amazon.com 等）
3. **勿用中国境内可访问的站点**：GFW 可能已监控这些流量
4. **建议搭配防火墙**：仅开放必要端口

---

## 文件结构

```
9.vless-reality/
├── install_reality.sh    # 部署脚本
├── README.md             # 本文档
└── reality_node_info.txt # 部署后生成的连接信息
```

---

**最后更新**: 2026-05-27
