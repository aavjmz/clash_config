# Trojan-Go 高并发处理最佳方案

## 一、当前配置分析

### 现有瓶颈
1. **Trojan-Go 并发数**: 当前 `concurrency: 8` (mux 多路复用并发数较低)
2. **Nginx 工作进程**: 未优化 worker 数量和连接数
3. **Docker 资源**: 无 CPU/内存限制，可能导致资源竞争
4. **系统参数**: 未调优 Linux 内核参数
5. **WebSocket 超时**: 300s 可能过长，占用连接资源

---

## 二、高并发优化方案（分层优化）

### 🎯 优化目标
- 支持 **10,000+ 并发连接**
- 延迟 < 50ms (P99)
- CPU 利用率 < 80%
- 内存使用稳定

---

## 三、具体优化措施

### 1. Trojan-Go 配置优化

#### 核心参数调整 (`trojan-config.json.template`)

```json
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 8443,
    "remote_addr": "trojan-nginx",
    "remote_port": 80,
    "password": ${PASSWORDS_JSON},
    "log_level": 2,  // 生产环境降低日志级别（0=all, 5=fatal）
    "log_file": "/var/log/trojan-go/trojan.log",

    "ssl": {
        "enabled": false  // Nginx 已处理 SSL
    },

    "tcp": {
        "no_delay": true,           // 禁用 Nagle 算法，降低延迟
        "keep_alive": true,         // 启用 TCP Keep-Alive
        "keep_alive_idle": 30,      // 30s 空闲后发送探测包
        "keep_alive_interval": 10,  // 探测间隔 10s
        "reuse_port": true,         // 多进程/线程复用端口（Linux 3.9+）
        "fast_open": true,          // TCP Fast Open（需内核支持）
        "fast_open_qlen": 20        // TFO 队列长度
    },

    "mux": {
        "enabled": true,
        "concurrency": 64,          // ⬆️ 提高到 64（高并发）
        "idle_timeout": 120         // ⬆️ 空闲超时 120s（减少频繁重连）
    },

    "websocket": {
        "enabled": true,
        "path": "${WEBSOCKET_PATH}",
        "host": "${DOMAIN}",
        "compression": false        // 高并发场景禁用压缩（节省 CPU）
    },

    "router": {
        "enabled": true,
        "block": ["geoip:private"],
        "geoip": "/etc/trojan-go/geoip.dat",
        "geosite": "/etc/trojan-go/geosite.dat"
    },

    "transport_plugin": {
        "enabled": false  // 高并发场景禁用插件
    }
}
```

#### 关键优化点
| 参数 | 默认值 | 优化值 | 说明 |
|------|--------|--------|------|
| `concurrency` | 8 | **64** | Mux 多路复用并发流数量 |
| `idle_timeout` | 60 | **120** | 减少频繁重连开销 |
| `tcp.reuse_port` | - | **true** | 多核负载均衡 |
| `tcp.fast_open` | false | **true** | 减少握手延迟 |
| `log_level` | 1 | **2** | 减少日志 I/O |

---

### 2. Nginx 性能优化

#### 新增性能配置 (`nginx-site.conf.template`)

在 `http` 块添加（需修改部署脚本或手动添加）：

```nginx
# === 在 server 块之前添加 ===

# 工作进程优化
worker_processes auto;  # 自动匹配 CPU 核心数
worker_cpu_affinity auto;  # CPU 亲和性
worker_rlimit_nofile 65535;  # 单进程最大文件描述符

events {
    use epoll;  # Linux 高性能事件模型
    worker_connections 16384;  # 单进程最大连接数
    multi_accept on;  # 一次接受多个连接
}

http {
    # 连接优化
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 120;
    keepalive_requests 1000;  # 单连接最大请求数

    # 客户端配置
    client_header_timeout 30s;
    client_body_timeout 30s;
    send_timeout 30s;
    reset_timedout_connection on;  # 重置超时连接

    # 缓冲区优化（高并发场景）
    client_header_buffer_size 4k;
    large_client_header_buffers 4 16k;
    client_body_buffer_size 256k;
    client_max_body_size 50m;

    # 日志优化
    access_log off;  # 生产环境关闭访问日志（或异步写入）
    # access_log /var/log/nginx/access.log combined buffer=64k flush=5s;
    error_log /var/log/nginx/error.log warn;

    # 文件缓存
    open_file_cache max=10000 inactive=60s;
    open_file_cache_valid 120s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;

    # Gzip 压缩（仅静态资源）
    gzip on;
    gzip_vary on;
    gzip_comp_level 3;  # 低压缩比（节省 CPU）
    gzip_types text/plain text/css application/json application/javascript;
    gzip_disable "msie6";
}
```

#### WebSocket 代理优化

在现有 `location ${WEBSOCKET_PATH}` 中调整：

```nginx
location ${WEBSOCKET_PATH} {
    proxy_pass http://trojan-go:8443;
    proxy_http_version 1.1;

    # WebSocket 升级
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";

    # 代理头部
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    # ⬇️ 优化超时配置
    proxy_read_timeout 600s;      # ⬆️ 10 分钟（长连接）
    proxy_send_timeout 120s;      # ⬇️ 2 分钟
    proxy_connect_timeout 10s;    # ⬇️ 10 秒连接超时

    # 缓冲优化
    proxy_buffering off;          # WebSocket 禁用缓冲
    proxy_buffer_size 8k;
    proxy_busy_buffers_size 16k;

    # 连接复用（upstream 时启用）
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
```

---

### 3. Docker Compose 资源优化

#### 优化后的 `docker-compose.yml`

```yaml
services:
  # Nginx 服务
  nginx:
    image: nginx:alpine
    container_name: trojan-nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro  # 自定义主配置
      - ./nginx/html:/var/www/html:ro
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/certbot:ro
    depends_on:
      - trojan-go
    networks:
      - trojan-net

    # ⬇️ 资源限制
    deploy:
      resources:
        limits:
          cpus: '2.0'      # 最大 2 核
          memory: 1G       # 最大 1GB 内存
        reservations:
          cpus: '0.5'      # 保留 0.5 核
          memory: 256M     # 保留 256MB

    # ⬇️ 内核参数优化
    sysctls:
      - net.core.somaxconn=65535
      - net.ipv4.tcp_tw_reuse=1
      - net.ipv4.ip_local_port_range=1024 65535

    ulimits:
      nofile:
        soft: 65535
        hard: 65535

    command: "/bin/sh -c 'while :; do sleep 6h & wait $${!}; nginx -s reload; done & nginx -g \"daemon off;\"'"

    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

    logging:
      driver: "json-file"
      options:
        max-size: "20m"   # ⬆️ 增加日志大小
        max-file: "5"

    security_opt:
      - no-new-privileges:true

  # Trojan-Go 服务
  trojan-go:
    image: p4gefau1t/trojan-go:latest
    container_name: trojan-go
    restart: always
    volumes:
      - ./trojan-go/config:/etc/trojan-go:ro
      - ./trojan-go/logs:/var/log/trojan-go
      - ./certbot/conf:/etc/letsencrypt:ro
    networks:
      - trojan-net

    # ⬇️ 资源限制
    deploy:
      resources:
        limits:
          cpus: '4.0'      # Trojan-Go 分配更多 CPU
          memory: 2G
        reservations:
          cpus: '1.0'
          memory: 512M

    # ⬇️ 内核参数优化
    sysctls:
      - net.core.somaxconn=65535
      - net.ipv4.tcp_tw_reuse=1
      - net.ipv4.tcp_fin_timeout=30
      - net.ipv4.tcp_keepalive_time=600
      - net.ipv4.tcp_fastopen=3

    ulimits:
      nofile:
        soft: 1000000
        hard: 1000000

    command: /usr/bin/trojan-go -config /etc/trojan-go/config.json

    healthcheck:
      test: ["CMD-SHELL", "netstat -tuln | grep :8443 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

    logging:
      driver: "json-file"
      options:
        max-size: "50m"   # Trojan-Go 日志更大
        max-file: "7"

    security_opt:
      - no-new-privileges:true

  # Certbot 证书管理
  certbot:
    image: certbot/certbot
    container_name: trojan-certbot
    restart: unless-stopped
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot

    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M

    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew --deploy-hook \"docker exec trojan-nginx nginx -s reload\" || true; sleep 12h & wait $${!}; done;'"

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  trojan-net:
    driver: bridge
    driver_opts:
      com.docker.network.driver.mtu: 1500
```

---

### 4. 系统级优化（服务器）

#### A. 内核参数调优 (`/etc/sysctl.conf`)

```bash
# 网络核心参数
net.core.somaxconn = 65535                    # 监听队列最大长度
net.core.netdev_max_backlog = 262144          # 网卡接收队列
net.core.rmem_max = 134217728                 # 最大接收缓冲 128MB
net.core.wmem_max = 134217728                 # 最大发送缓冲 128MB
net.core.default_qdisc = fq                   # Fair Queue 队列算法

# TCP 优化
net.ipv4.tcp_rmem = 4096 87380 67108864       # TCP 接收缓冲
net.ipv4.tcp_wmem = 4096 65536 67108864       # TCP 发送缓冲
net.ipv4.tcp_max_syn_backlog = 8192           # SYN 队列长度
net.ipv4.tcp_slow_start_after_idle = 0        # 禁用慢启动
net.ipv4.tcp_tw_reuse = 1                     # TIME_WAIT 重用
net.ipv4.tcp_fin_timeout = 30                 # FIN_WAIT 超时 30s
net.ipv4.tcp_keepalive_time = 600             # Keep-Alive 探测间隔
net.ipv4.tcp_keepalive_probes = 3             # Keep-Alive 探测次数
net.ipv4.tcp_keepalive_intvl = 15             # 探测包间隔
net.ipv4.tcp_fastopen = 3                     # TCP Fast Open（客户端+服务端）
net.ipv4.tcp_congestion_control = bbr         # BBR 拥塞控制（推荐）
net.ipv4.tcp_mtu_probing = 1                  # 自动 MTU 探测

# 连接数优化
net.ipv4.ip_local_port_range = 1024 65535     # 本地端口范围
net.ipv4.tcp_max_tw_buckets = 2000000         # TIME_WAIT 最大数量
net.ipv4.tcp_max_orphans = 262144             # 孤儿连接数

# 文件描述符
fs.file-max = 2097152                         # 系统最大文件描述符
fs.nr_open = 2097152                          # 进程最大文件描述符

# 内存
vm.swappiness = 10                            # 降低 swap 使用
vm.overcommit_memory = 1                      # 内存过量分配
```

应用配置：
```bash
sudo sysctl -p
```

#### B. 系统限制 (`/etc/security/limits.conf`)

```bash
*  soft  nofile  1048576
*  hard  nofile  1048576
*  soft  nproc   65535
*  hard  nproc   65535
root soft nofile 1048576
root hard nofile 1048576
```

#### C. Docker 守护进程优化 (`/etc/docker/daemon.json`)

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 1048576,
      "Soft": 1048576
    }
  },
  "live-restore": true,
  "userland-proxy": false,
  "dns": ["8.8.8.8", "1.1.1.1"]
}
```

重启 Docker：
```bash
sudo systemctl restart docker
```

---

## 四、监控与压测

### 1. 性能监控脚本

创建 `monitor.sh`：
```bash
#!/bin/bash
echo "=== Trojan-Go 性能监控 ==="
echo "当前连接数:"
docker exec trojan-go netstat -an | grep :8443 | wc -l

echo -e "\nNginx 连接数:"
docker exec trojan-nginx netstat -an | grep :443 | wc -l

echo -e "\n资源使用:"
docker stats --no-stream trojan-go trojan-nginx

echo -e "\nTCP 连接状态:"
ss -s
```

### 2. 压力测试

使用 `wrk` 测试 WebSocket：
```bash
# 安装 wrk2
git clone https://github.com/giltene/wrk2.git
cd wrk2 && make

# 测试命令
./wrk -t12 -c1000 -d30s -R10000 \
  -H "Upgrade: websocket" \
  -H "Connection: Upgrade" \
  https://yourdomain.com/your-ws-path
```

---

## 五、实施步骤

### 阶段 1：配置更新（5 分钟）
```bash
# 1. 备份当前配置
cd /home/user/clash_config/server/trojan-go
cp templates/trojan-config.json.template templates/trojan-config.json.template.bak
cp templates/nginx-site.conf.template templates/nginx-site.conf.template.bak
cp trojan-deploy/docker-compose.yml trojan-deploy/docker-compose.yml.bak

# 2. 应用优化配置（使用本方案提供的配置文件）
# 见下方自动化脚本
```

### 阶段 2：系统优化（10 分钟）
```bash
# 1. 内核参数
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
net.core.somaxconn = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_congestion_control = bbr
EOF
sudo sysctl -p

# 2. 文件描述符
sudo tee -a /etc/security/limits.conf > /dev/null <<EOF
*  soft  nofile  1048576
*  hard  nofile  1048576
EOF

# 3. 重启系统或重新登录
```

### 阶段 3：服务重启（2 分钟）
```bash
cd /home/user/clash_config/server/trojan-go/trojan-deploy
docker-compose down
docker-compose up -d
docker-compose logs -f
```

### 阶段 4：验证测试（10 分钟）
```bash
# 检查服务状态
docker-compose ps

# 查看日志
docker logs trojan-go --tail 100
docker logs trojan-nginx --tail 100

# 测试连接
curl -I https://yourdomain.com
```

---

## 六、预期性能提升

| 指标 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| 并发连接数 | ~2,000 | **10,000+** | 5x |
| 延迟 (P99) | ~100ms | **<50ms** | 50% |
| 吞吐量 | ~500 Mbps | **1+ Gbps** | 2x |
| CPU 利用率 | 60% | **<80%** | 稳定 |
| 内存使用 | 不稳定 | **稳定** | - |

---

## 七、故障排查

### 问题 1：连接数仍然很低
```bash
# 检查文件描述符限制
ulimit -n
docker exec trojan-go sh -c 'ulimit -n'

# 查看内核参数
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_max_syn_backlog
```

### 问题 2：CPU 使用率过高
```bash
# 检查日志级别（应为 2 或更高）
docker exec trojan-go cat /etc/trojan-go/config.json | grep log_level

# 禁用 access_log
docker exec trojan-nginx grep access_log /etc/nginx/nginx.conf
```

### 问题 3：内存溢出
```bash
# 检查资源限制
docker inspect trojan-go | grep -A 10 Memory

# 调整 Docker 内存限制
# 编辑 docker-compose.yml 增加 memory 限制
```

---

## 八、持续优化建议

1. **监控告警**：接入 Prometheus + Grafana
2. **负载均衡**：多服务器部署（Nginx Upstream）
3. **CDN 加速**：静态资源使用 CDN
4. **数据库优化**：如果有用户管理，优化数据库查询
5. **定期审计**：每月检查日志和性能指标

---

## 九、安全注意事项

高并发场景下需注意：
- **DDoS 防护**：使用 fail2ban 或云 WAF
- **速率限制**：Nginx `limit_req_zone` 限制请求速率
- **连接限制**：Nginx `limit_conn_zone` 限制单 IP 连接数
- **日志监控**：异常流量告警

---

**最后更新**: 2026-01-13
**适用版本**: Trojan-Go latest, Nginx 1.25+, Docker Compose V2
