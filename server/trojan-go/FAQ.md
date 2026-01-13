# 高并发优化 - 常见问题解答 (FAQ)

## 📋 目录

- [安装与部署](#安装与部署)
- [性能问题](#性能问题)
- [配置问题](#配置问题)
- [系统优化](#系统优化)
- [监控与调试](#监控与调试)
- [故障恢复](#故障恢复)

---

## 安装与部署

### Q1: 一键部署脚本需要 root 权限吗？

**A:** 是的。脚本需要修改系统内核参数和文件描述符限制，必须使用 `sudo` 运行：

```bash
sudo bash apply-high-concurrency.sh
```

### Q2: 优化后需要重启服务器吗？

**A:** 大部分优化不需要重启，但以下情况建议重启：

- ✅ **不需要重启**：Docker 配置、Trojan-Go 配置、Nginx 配置
- ⚠️ **建议重启**：修改 `/etc/sysctl.conf` 后（虽然 `sysctl -p` 可立即生效）
- ✅ **必须重新登录**：修改 `/etc/security/limits.conf` 后

### Q3: 可以只应用部分优化吗？

**A:** 可以。优化分为多个层次，可以逐步应用：

1. **第一阶段**：仅应用 Trojan-Go 配置
   ```bash
   cp templates/trojan-config-high-concurrency.json.template \
      templates/trojan-config.json.template
   ```

2. **第二阶段**：添加 Docker 资源限制
   ```bash
   cp docker-compose-high-concurrency.yml trojan-deploy/docker-compose.yml
   ```

3. **第三阶段**：系统内核优化
   ```bash
   sudo bash apply-high-concurrency.sh  # 只执行系统优化部分
   ```

### Q4: 如何验证优化是否生效？

**A:** 使用以下命令检查：

```bash
# 1. 检查 Trojan-Go 配置
docker exec trojan-go cat /etc/trojan-go/config.json | grep concurrency
# 应显示: "concurrency": 64

# 2. 检查内核参数
sysctl net.core.somaxconn
# 应显示: net.core.somaxconn = 65535

# 3. 检查文件描述符
ulimit -n
# 应显示: 1048576

# 4. 检查 Docker 资源限制
docker inspect trojan-go | grep -A 5 Memory
```

---

## 性能问题

### Q5: 应用优化后性能反而下降了？

**A:** 可能的原因和解决方案：

1. **服务器资源不足**
   - 检查 CPU/内存使用：`docker stats`
   - 建议配置：至少 4 核 CPU + 4GB 内存
   - 解决：降低资源限制或升级服务器

2. **日志占用 I/O**
   - 检查日志级别：应为 `log_level: 2` 或更高
   - 关闭 Nginx access_log（已在配置中）
   - 清理旧日志：`docker exec trojan-go rm -f /var/log/trojan-go/*.log.old`

3. **网络问题**
   - 检查带宽限制
   - 测试延迟：`ping domain.com`
   - 检查 MTU 设置：`ip link show`

### Q6: 为什么并发数还是很低？

**A:** 逐步排查：

```bash
# 1. 检查容器文件描述符限制
docker exec trojan-go sh -c 'ulimit -n'
# 应该是 1000000

# 2. 检查宿主机限制
ulimit -n
# 应该是 1048576

# 3. 检查系统全局限制
cat /proc/sys/fs/file-max
# 应该是 2097152

# 4. 检查当前连接数
docker exec trojan-go netstat -an | grep :8443 | wc -l

# 5. 检查 Nginx worker_connections
docker exec trojan-nginx cat /etc/nginx/nginx.conf | grep worker_connections
# 应该是 16384
```

### Q7: CPU 使用率过高怎么办？

**A:** 优化措施：

1. **提高日志级别**（减少日志 I/O）
   ```json
   "log_level": 3  // 从 2 改为 3 (warning 级别)
   ```

2. **禁用 WebSocket 压缩**（已在配置中）
   ```json
   "websocket": {
       "compression": false
   }
   ```

3. **调整 Docker CPU 限制**
   ```yaml
   deploy:
     resources:
       limits:
         cpus: '6.0'  # 增加 CPU 配额
   ```

4. **检查是否受到攻击**
   ```bash
   # 查看连接数最多的 IP
   docker exec trojan-nginx netstat -an | grep :443 | awk '{print $5}' | \
       cut -d: -f1 | sort | uniq -c | sort -rn | head -20
   ```

### Q8: 内存占用过高怎么办？

**A:** 排查步骤：

```bash
# 1. 查看容器内存使用
docker stats --no-stream trojan-go trojan-nginx

# 2. 检查日志文件大小
du -sh /home/user/clash_config/server/trojan-go/trojan-deploy/trojan-go/logs/

# 3. 清理日志
docker exec trojan-go truncate -s 0 /var/log/trojan-go/trojan.log

# 4. 调整内存限制
# 编辑 docker-compose.yml
memory: 4G  # 增加到 4GB
```

---

## 配置问题

### Q9: MUX 并发数设置多少合适？

**A:** 根据场景选择：

| 场景 | 并发数 | 说明 |
|------|--------|------|
| 个人使用 | 8-16 | 默认值 |
| 小团队 (10-50 人) | 32-64 | 推荐值 |
| 中型部署 (100-500 人) | 64-128 | 高并发 |
| 大型部署 (1000+ 人) | 128-256 | 极限性能 |

**注意**：并发数越高，内存占用越大。每增加 64 并发约增加 50-100MB 内存。

### Q10: TCP Fast Open 启用失败？

**A:** 需要满足以下条件：

```bash
# 1. 检查内核版本（需要 Linux 3.7+）
uname -r

# 2. 检查内核支持
cat /proc/sys/net/ipv4/tcp_fastopen
# 0 = 禁用
# 1 = 客户端启用
# 2 = 服务端启用
# 3 = 全部启用（推荐）

# 3. 启用 TFO
sudo sysctl -w net.ipv4.tcp_fastopen=3

# 4. 永久生效
echo "net.ipv4.tcp_fastopen = 3" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Q11: BBR 拥塞控制启用失败？

**A:** BBR 需要 Linux 4.9+ 内核：

```bash
# 1. 检查内核版本
uname -r

# 2. 检查 BBR 模块
lsmod | grep tcp_bbr

# 3. 如果未加载，手动加载
sudo modprobe tcp_bbr
echo "tcp_bbr" | sudo tee -a /etc/modules-load.d/modules.conf

# 4. 启用 BBR
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
sudo sysctl -w net.core.default_qdisc=fq

# 5. 验证
sysctl net.ipv4.tcp_congestion_control
# 应显示: net.ipv4.tcp_congestion_control = bbr
```

**如果内核版本过低**：
- Ubuntu 18.04+：自带 BBR 支持
- CentOS 7：需要升级内核到 4.9+
- Debian 9+：自带 BBR 支持

---

## 系统优化

### Q12: 文件描述符设置不生效？

**A:** 需要重新登录或重启：

```bash
# 1. 修改后必须重新登录
exit
# 重新 SSH 登录

# 2. 验证
ulimit -n
# 应该显示 1048576

# 3. 如果还是不生效，检查配置
cat /etc/security/limits.conf | grep nofile

# 4. 确保没有其他限制
# 编辑 /etc/systemd/system.conf 和 /etc/systemd/user.conf
DefaultLimitNOFILE=1048576
```

### Q13: Docker 容器内的限制如何设置？

**A:** Docker 有独立的限制机制：

```yaml
# docker-compose.yml 中设置
ulimits:
  nofile:
    soft: 1000000
    hard: 1000000
  nproc:
    soft: 65535
    hard: 65535
```

**验证**：
```bash
docker exec trojan-go sh -c 'ulimit -n'
docker exec trojan-go sh -c 'ulimit -u'
```

### Q14: 系统参数修改后如何立即生效？

**A:** 使用 `sysctl -p`：

```bash
# 1. 编辑配置
sudo vim /etc/sysctl.conf

# 2. 立即生效
sudo sysctl -p

# 3. 验证特定参数
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_tw_reuse
```

---

## 监控与调试

### Q15: 如何实时查看性能指标？

**A:** 使用提供的监控脚本：

```bash
# 实时监控（每 5 秒刷新）
bash monitor-performance.sh

# 自定义刷新间隔（每 2 秒）
bash monitor-performance.sh 2

# 查看容器资源
docker stats trojan-go trojan-nginx

# 查看日志
docker-compose logs -f --tail 100 trojan-go
```

### Q16: 如何进行压力测试？

**A:** 使用提供的压测脚本：

```bash
# 基准测试（轻量）
bash benchmark.sh yourdomain.com

# 压力测试（重量，需确认）
bash stress-test.sh yourdomain.com

# 手动测试
ab -n 10000 -c 100 https://yourdomain.com/
```

### Q17: 如何查看详细的连接信息？

**A:** 使用以下命令：

```bash
# 1. 查看所有 TCP 连接
docker exec trojan-go netstat -antp

# 2. 统计连接状态
docker exec trojan-go netstat -an | awk '/tcp/ {print $6}' | sort | uniq -c

# 3. 查看 ESTABLISHED 连接数
docker exec trojan-go netstat -an | grep ESTABLISHED | wc -l

# 4. 查看连接最多的 IP
docker exec trojan-nginx netstat -an | grep :443 | \
    awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
```

---

## 故障恢复

### Q18: 如何回滚到优化前的配置？

**A:** 使用自动备份：

```bash
# 1. 查看备份
ls -lh /home/user/clash_config/server/trojan-go/backups/

# 2. 找到最近的备份（例如 backup-20260113-120000）
BACKUP_DIR="backups/backup-20260113-120000"

# 3. 恢复 Trojan-Go 配置
cp "$BACKUP_DIR/trojan-config.json.template" \
   templates/trojan-config.json.template

# 4. 恢复 Docker Compose 配置
cp "$BACKUP_DIR/docker-compose.yml" \
   trojan-deploy/docker-compose.yml

# 5. 重启服务
cd trojan-deploy
docker-compose down
docker-compose up -d
```

### Q19: 服务无法启动怎么办？

**A:** 逐步排查：

```bash
# 1. 查看容器状态
docker-compose ps

# 2. 查看错误日志
docker-compose logs trojan-go
docker-compose logs nginx

# 3. 检查配置文件语法
docker exec trojan-go /usr/bin/trojan-go -test -config /etc/trojan-go/config.json
docker exec trojan-nginx nginx -t

# 4. 检查端口占用
sudo netstat -tulpn | grep -E ':80|:443|:8443'

# 5. 强制重建
docker-compose down -v
docker-compose up -d --force-recreate
```

### Q20: 优化后发现连接不稳定？

**A:** 可能的原因：

1. **MTU 设置问题**
   ```bash
   # 检查 MTU
   ip link show

   # 调整 Docker 网络 MTU
   # 编辑 docker-compose.yml
   networks:
     trojan-net:
       driver_opts:
         com.docker.network.driver.mtu: 1450  # 降低 MTU
   ```

2. **TCP Keep-Alive 过于激进**
   ```json
   "tcp": {
       "keep_alive_idle": 60,  // 增加到 60s
       "keep_alive_interval": 20  // 增加到 20s
   }
   ```

3. **防火墙/安全组限制**
   ```bash
   # 检查防火墙规则
   sudo iptables -L -n

   # 检查连接跟踪表
   cat /proc/sys/net/netfilter/nf_conntrack_max

   # 增加连接跟踪表大小
   sudo sysctl -w net.netfilter.nf_conntrack_max=1000000
   ```

---

## 📞 获取帮助

如果以上 FAQ 无法解决您的问题：

1. **查看详细文档**：`HIGH_CONCURRENCY_OPTIMIZATION.md`
2. **检查日志**：`docker-compose logs -f`
3. **运行诊断**：`bash monitor-performance.sh`
4. **提交 Issue**：包含以下信息
   - 操作系统和版本
   - Docker 版本
   - 错误日志
   - 配置文件内容
   - 复现步骤

---

**最后更新**: 2026-01-13
**适用版本**: Trojan-Go latest, Docker Compose V2
