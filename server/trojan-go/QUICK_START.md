# 高并发优化 - 快速开始

## 一、一键部署（推荐）

```bash
cd /home/user/clash_config/server/trojan-go
sudo bash apply-high-concurrency.sh
```

执行后会自动：
- ✅ 备份现有配置
- ✅ 应用高并发配置
- ✅ 优化系统内核参数
- ✅ 重启服务

## 二、手动部署

### 1. 备份配置
```bash
cd /home/user/clash_config/server/trojan-go
cp templates/trojan-config.json.template templates/trojan-config.json.template.bak
cp trojan-deploy/docker-compose.yml trojan-deploy/docker-compose.yml.bak
```

### 2. 应用配置
```bash
# Trojan-Go 配置
cp templates/trojan-config-high-concurrency.json.template \
   templates/trojan-config.json.template

# Docker Compose 配置
cp docker-compose-high-concurrency.yml \
   trojan-deploy/docker-compose.yml

# Nginx 配置（可选）
cp nginx-high-concurrency.conf \
   trojan-deploy/nginx/nginx.conf
```

### 3. 系统优化
```bash
# 内核参数
sudo bash -c 'cat >> /etc/sysctl.conf <<EOF
net.core.somaxconn = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.ip_local_port_range = 1024 65535
EOF'

sudo sysctl -p

# 文件描述符
sudo bash -c 'cat >> /etc/security/limits.conf <<EOF
*  soft  nofile  1048576
*  hard  nofile  1048576
EOF'
```

### 4. 重启服务
```bash
cd trojan-deploy
docker-compose down
docker-compose up -d
```

## 三、性能监控

### 实时监控
```bash
bash monitor-performance.sh
```

### 查看日志
```bash
cd trojan-deploy
docker-compose logs -f trojan-go
docker-compose logs -f nginx
```

### 资源监控
```bash
docker stats trojan-go trojan-nginx
```

## 四、关键优化参数

| 配置项 | 默认值 | 优化值 | 说明 |
|--------|--------|--------|------|
| Trojan MUX 并发 | 8 | **64** | 多路复用并发流 |
| Nginx worker_connections | 1024 | **16384** | 单进程最大连接 |
| 系统 somaxconn | 128 | **65535** | 监听队列长度 |
| 文件描述符 | 1024 | **1048576** | 最大打开文件数 |

## 五、性能预期

- **并发连接数**: 10,000+
- **延迟 (P99)**: < 50ms
- **吞吐量**: 1+ Gbps
- **CPU 利用率**: < 80%

## 六、故障排查

### 服务无法启动
```bash
# 检查容器状态
docker-compose ps

# 查看错误日志
docker-compose logs
```

### 连接数仍然很低
```bash
# 检查文件描述符
ulimit -n

# 检查内核参数
sysctl net.core.somaxconn
```

### 回滚到原配置
```bash
# 找到备份目录
ls -lh backups/

# 恢复配置
cp backups/backup-YYYYMMDD-HHMMSS/trojan-config.json.template \
   templates/trojan-config.json.template

# 重启服务
cd trojan-deploy && docker-compose restart
```

## 七、相关文档

- 详细优化方案: `HIGH_CONCURRENCY_OPTIMIZATION.md`
- 监控脚本: `monitor-performance.sh`
- 部署脚本: `apply-high-concurrency.sh`
