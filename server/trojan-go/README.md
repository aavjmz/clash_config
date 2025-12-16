# Trojan-Go 一键部署脚本

🚀 在 VPS 上一键部署安全、隐蔽的 Trojan-Go 代理服务

## 📖 项目简介

本项目提供了一套完整的 Trojan-Go 部署解决方案，使用 Docker 容器化部署，通过 Nginx 反向代理实现流量伪装，支持一键安装和卸载。

### 架构设计

```
                    ┌─────────────────────┐
Internet ──────────►│  Nginx (443/HTTPS)  │
                    │  - SSL 终止          │
                    │  - 伪装网站          │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Trojan-Go (8443)   │
                    │  - WebSocket 代理    │
                    │  - 多用户支持        │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Certbot            │
                    │  - SSL 证书自动续期  │
                    └─────────────────────┘
```

## ✨ 功能特点

### 安全性和隐蔽性

- ✅ **真实网站伪装**：反向代理到真实 HTTPS 网站，流量特征难以识别
- ✅ **随机 WebSocket 路径**：自动生成 16 位随机十六进制路径
- ✅ **强 SSL 配置**：TLS 1.2/1.3，现代密码套件，OCSP Stapling
- ✅ **安全头部**：HSTS、X-Frame-Options、CSP 等全面防护
- ✅ **Docker 安全加固**：no-new-privileges，日志限制

### 易用性

- ✅ **一键部署**：交互式配置，全自动化安装
- ✅ **一键卸载**：安全清理，可选保留数据
- ✅ **多用户支持**：支持配置多个 Trojan 密码
- ✅ **自动证书管理**：Let's Encrypt 证书自动申请和续期
- ✅ **健康检查**：自动验证服务状态

### 兼容性

- ✅ 支持 Ubuntu、Debian、CentOS、RHEL 系统
- ✅ 支持 Docker Compose V1 和 V2
- ✅ 不影响服务器上的其他 Web 应用

## 🚀 快速开始

### 前置要求

1. **VPS 服务器**
   - 操作系统：Ubuntu 18.04+, Debian 9+, CentOS 7+
   - 至少 512MB 内存
   - 开放端口：80, 443

2. **域名**
   - 已解析到服务器 IP 地址
   - 支持 Let's Encrypt 证书申请

3. **Root 权限**
   - 需要使用 `sudo` 或 `root` 用户运行脚本

### 一键部署

```bash
# 1. 克隆或下载项目
git clone https://github.com/your-repo/trojan-go-deploy.git
cd trojan-go-deploy

# 2. 运行部署脚本
sudo bash deploy.sh
```

### 部署过程

脚本会引导您完成以下配置：

1. **域名配置**
   - 输入已解析到服务器的域名
   - 脚本会自动验证 DNS 解析

2. **邮箱配置**
   - 用于 SSL 证书通知和紧急联系

3. **伪装方式选择**
   - **方式 1**：反向代理真实网站（推荐，隐蔽性最强）
   - **方式 2**：使用本地静态页面

4. **WebSocket 路径**
   - **选项 1**：自动生成随机路径（推荐，安全性最高）
   - **选项 2**：自定义路径

5. **用户密码配置**
   - 支持输入多个密码（多用户）
   - 留空自动生成强密码

### 部署完成

部署成功后，脚本会显示：

- ✅ 服务器信息（域名、WebSocket 路径）
- ✅ 用户密码列表
- ✅ 客户端配置示例（Clash、Shadowrocket）
- ✅ 常用管理命令

部署信息会保存到：`/root/trojan-deploy/deployment-info.txt`

## 🗑️ 一键卸载

```bash
sudo bash uninstall.sh
```

卸载脚本支持以下操作：

- 停止并删除所有 Docker 容器
- 可选删除配置文件
- 可选删除 SSL 证书
- 可选删除 Docker 镜像
- 可选卸载 Docker 环境
- 可选清理防火墙规则

## 📱 客户端配置

### Clash 配置示例

```yaml
proxies:
  - name: "Trojan-example.com"
    type: trojan
    server: example.com
    port: 443
    password: your-password
    udp: true
    sni: example.com
    alpn:
      - h2
      - http/1.1
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: /your-websocket-path
      headers:
        Host: example.com
```

### Shadowrocket 配置

```
trojan://your-password@example.com:443?allowInsecure=0&sni=example.com&ws=1&wspath=/your-websocket-path#Trojan-example.com
```

### 支持的客户端

- **Windows**：Clash for Windows, V2rayN
- **macOS**：ClashX Pro, V2rayU
- **Android**：Clash for Android, V2rayNG
- **iOS**：Shadowrocket, Quantumult X

## 🔧 管理命令

### 服务管理

```bash
# 进入部署目录
cd /root/trojan-deploy

# 查看服务状态
docker compose ps

# 查看所有日志
docker compose logs -f

# 查看 Nginx 日志
docker compose logs -f nginx

# 查看 Trojan-Go 日志
docker compose logs -f trojan-go

# 重启所有服务
docker compose restart

# 重启单个服务
docker compose restart nginx
docker compose restart trojan-go

# 停止所有服务
docker compose down

# 启动所有服务
docker compose up -d
```

### 证书管理

```bash
# 查看证书信息
openssl x509 -in /root/trojan-deploy/certbot/conf/live/your-domain.com/fullchain.pem -text -noout

# 查看证书有效期
openssl x509 -in /root/trojan-deploy/certbot/conf/live/your-domain.com/fullchain.pem -noout -dates

# 手动续期证书
cd /root/trojan-deploy
docker compose run --rm certbot renew

# 测试续期（不实际执行）
docker compose run --rm certbot renew --dry-run
```

### 配置修改

修改配置后需要重启对应服务：

```bash
cd /root/trojan-deploy

# 修改 Trojan-Go 配置后
vi trojan-go/config/config.json
docker compose restart trojan-go

# 修改 Nginx 配置后
vi nginx/conf.d/trojan.conf
docker compose restart nginx
```

## 🔍 常见问题

### 1. SSL 证书申请失败

**可能原因：**
- 域名未正确解析到服务器 IP
- 80 端口被占用或被防火墙阻止
- 服务器与 Let's Encrypt 连接异常

**解决方法：**

```bash
# 检查域名解析
dig your-domain.com
nslookup your-domain.com

# 检查 80 端口
netstat -tlnp | grep :80
ss -tlnp | grep :80

# 检查防火墙
ufw status
firewall-cmd --list-all

# 手动申请证书
cd /root/trojan-deploy
docker compose up -d nginx
docker compose run --rm certbot certonly --webroot \
    --webroot-path=/var/www/certbot \
    -d your-domain.com \
    --email your@email.com \
    --agree-tos
```

### 2. 容器无法启动

**检查方法：**

```bash
cd /root/trojan-deploy

# 查看容器状态
docker compose ps

# 查看详细日志
docker compose logs

# 检查配置文件语法
# Nginx 配置检查
docker run --rm -v /root/trojan-deploy/nginx/conf.d:/etc/nginx/conf.d nginx:alpine nginx -t

# Trojan-Go 配置检查（JSON 格式）
cat /root/trojan-deploy/trojan-go/config/config.json | jq .
```

### 3. 客户端无法连接

**排查步骤：**

```bash
# 1. 检查服务器防火墙
ufw status
firewall-cmd --list-all

# 2. 检查端口监听
netstat -tlnp | grep -E ':80|:443'

# 3. 测试 HTTPS 访问
curl -I https://your-domain.com

# 4. 测试 WebSocket 连接
curl -I -H "Connection: Upgrade" -H "Upgrade: websocket" \
     https://your-domain.com/your-websocket-path

# 5. 检查 Trojan-Go 监听
docker exec trojan-go netstat -tlnp | grep 8443

# 6. 验证密码配置
docker exec trojan-go cat /etc/trojan-go/config.json | grep password
```

### 4. 伪装网站无法访问

**检查方法：**

```bash
# 查看 Nginx 日志
docker compose logs nginx

# 测试反向代理目标
curl -I https://target-website.com

# 检查 Nginx 配置中的 proxy_pass
cat /root/trojan-deploy/nginx/conf.d/trojan.conf | grep proxy_pass
```

### 5. 证书自动续期失败

**检查方法：**

```bash
# 查看 Certbot 日志
docker compose logs certbot

# 手动测试续期
cd /root/trojan-deploy
docker compose run --rm certbot renew --dry-run

# 检查证书有效期
openssl x509 -in /root/trojan-deploy/certbot/conf/live/your-domain.com/fullchain.pem -noout -dates
```

## 🔒 安全建议

### 系统层面

```bash
# 1. 启用 BBR 拥塞控制（提高性能）
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# 2. 配置防火墙（仅开放必要端口）
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS
ufw enable

# 3. 定期更新系统
apt update && apt upgrade -y  # Ubuntu/Debian
yum update -y                 # CentOS/RHEL

# 4. 定期更新 Docker 镜像
cd /root/trojan-deploy
docker compose pull
docker compose up -d
docker image prune -f
```

### 应用层面

1. **使用强密码**
   - 至少 32 字符的随机密码
   - 使用脚本自动生成的密码

2. **随机化 WebSocket 路径**
   - 使用自动生成的随机路径
   - 避免使用常见路径（/ws, /ray, /trojan）

3. **反向代理真实网站**
   - 选择访问量大的正常网站
   - 避免使用敏感或违规网站

4. **定期更换密码**
   - 建议每 3-6 个月更换一次密码
   - 修改 `/root/trojan-deploy/trojan-go/config/config.json`
   - 重启服务：`docker compose restart trojan-go`

5. **监控日志**
   - 定期查看访问日志
   - 发现异常及时处理

### 隐蔽性建议

1. **伪装网站内容**
   - 使用真实网站反向代理（推荐）
   - 保持伪装网站内容更新

2. **避免特征性配置**
   - 不使用默认端口
   - 不在根路径提供 WebSocket
   - 隐藏服务器软件版本信息

3. **流量特征混淆**
   - WebSocket 传输
   - TLS 1.3 优先
   - HTTP/2 支持

## 📂 项目结构

```
trojan-go/
├── deploy.sh                    # 一键部署脚本
├── uninstall.sh                 # 一键卸载脚本
├── install-docker.sh            # Docker 安装脚本
├── templates/                   # 配置模板目录
│   ├── nginx-site.conf.template
│   └── trojan-config.json.template
├── trojan-deploy/               # 部署目录（运行时生成）
│   ├── docker-compose.yml       # Docker Compose 配置
│   ├── deployment-info.txt      # 部署信息摘要
│   ├── nginx/
│   │   ├── conf.d/
│   │   │   └── trojan.conf      # Nginx 配置
│   │   └── html/
│   │       └── index.html       # 伪装网站
│   ├── trojan-go/
│   │   ├── config/
│   │   │   ├── config.json      # Trojan-Go 配置
│   │   │   ├── geoip.dat
│   │   │   └── geosite.dat
│   │   └── logs/
│   │       └── trojan.log
│   └── certbot/
│       ├── conf/                # SSL 证书
│       └── www/                 # ACME 验证
└── README.md                    # 项目文档
```

## 🛠️ 高级配置

### 添加新用户

编辑 Trojan-Go 配置文件：

```bash
vi /root/trojan-deploy/trojan-go/config/config.json
```

在 `password` 数组中添加新密码：

```json
{
    "password": [
        "user1-password",
        "user2-password",
        "user3-password"   // 新用户
    ]
}
```

重启服务：

```bash
cd /root/trojan-deploy
docker compose restart trojan-go
```

### 更换伪装网站

编辑 Nginx 配置文件：

```bash
vi /root/trojan-deploy/nginx/conf.d/trojan.conf
```

修改 `proxy_pass` 指向新的网站：

```nginx
location / {
    proxy_pass https://new-target-website.com;
    proxy_set_header Host new-target-website.com;
    # ...
}
```

重启 Nginx：

```bash
docker compose restart nginx
```

### 性能优化

编辑 Trojan-Go 配置，调整并发数：

```json
{
    "mux": {
        "enabled": true,
        "concurrency": 16,     // 增加并发数
        "idle_timeout": 60
    }
}
```

### 多域名支持

在同一服务器上为不同域名部署多个实例：

```bash
# 实例 1
DEPLOY_DIR=/root/trojan-deploy-1 bash deploy.sh

# 实例 2
DEPLOY_DIR=/root/trojan-deploy-2 bash deploy.sh
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

## ⚠️ 免责声明

本项目仅供学习和研究使用，请遵守当地法律法规。使用本项目所产生的一切后果由使用者自行承担。

## 📞 联系方式

- GitHub Issues: [提交问题](https://github.com/your-repo/trojan-go-deploy/issues)
- 邮箱: your-email@example.com

---

**感谢使用 Trojan-Go 一键部署脚本！**

如果觉得有帮助，请给个 ⭐ Star 支持一下！
