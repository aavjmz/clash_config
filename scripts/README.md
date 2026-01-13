# 网络优化与监控脚本

本目录包含用于优化和监控服务器网络性能的脚本集合。

## 📁 目录结构

```
scripts/
├── network/           # 网络优化脚本
│   └── optimize-network.sh
├── monitoring/        # 监控脚本
│   └── check-optimization.sh
└── backup/           # 备份脚本（预留）
```

## 🔧 网络优化脚本

### `network/optimize-network.sh`

系统级 TCP/IP 网络参数优化脚本，解决代理连接超时问题。

**优化内容：**
- TCP Keepalive: 2小时 → 2分钟
- 连接跟踪表: 7,680 → 131,072 (扩大 17 倍)
- TCP 重传次数: 15 → 8
- Conntrack 超时: 5天 → 2小时

**使用方法：**
```bash
# 需要 root 权限
sudo bash scripts/network/optimize-network.sh
```

**特性：**
- ✅ 自动备份原配置
- ✅ 配置持久化（重启生效）
- ✅ 实时验证优化效果

## 📊 监控脚本

### `monitoring/check-optimization.sh`

网络配置检查和监控脚本，生成详细的系统状态报告。

**监控内容：**
- 系统网络参数
- 连接状态统计
- TCP 重传和超时统计
- Docker 容器状态
- Nginx 配置验证
- 系统资源使用
- 网络连通性测试

**使用方法：**
```bash
bash scripts/monitoring/check-optimization.sh
```

**输出：**
- 控制台实时显示
- 报告保存到 `reports/optimization_check_YYYYMMDD_HHMMSS.txt`

## 📋 使用场景

### 场景 1：初次部署优化
```bash
# 1. 执行网络优化
sudo bash scripts/network/optimize-network.sh

# 2. 验证优化效果
bash scripts/monitoring/check-optimization.sh

# 3. 查看生成的报告
cat reports/optimization_check_*.txt
```

### 场景 2：定期健康检查
```bash
# 设置每天自动检查（可选）
echo "0 2 * * * /root/github/clash_config/scripts/monitoring/check-optimization.sh" | crontab -

# 手动执行检查
bash scripts/monitoring/check-optimization.sh
```

### 场景 3：问题诊断
```bash
# 当出现连接超时问题时
bash scripts/monitoring/check-optimization.sh

# 查看最新报告
ls -lt reports/ | head -5
```

## 🎯 优化效果

| 指标 | 优化前 | 优化后 | 改善 |
|------|--------|--------|------|
| 死连接检测 | 2 小时 | 2 分钟 | 60x ⚡ |
| 连接表容量 | 7,680 | 131,072 | 17x 📈 |
| TCP 重传超时 | ~30 分钟 | ~100 秒 | 18x ⚡ |

## 📝 注意事项

1. **网络优化脚本**需要 root 权限执行
2. 优化配置会**立即生效**且**持久化**
3. 所有修改都会**自动备份**原配置
4. 建议先在测试环境验证

## 🔗 相关文档

- 系统优化说明：参见 git commit `d0396f8`
- Nginx 配置优化：`/root/xray-deploy/nginx/conf.d/trojan.conf`
- Docker Compose：`/root/xray-deploy/docker-compose.yml`

## 📞 问题反馈

如遇到问题，请提供以下信息：
1. 执行的命令
2. 错误信息
3. `check-optimization.sh` 生成的报告

---

**最后更新：** 2026-01-13  
**维护者：** Claude Sonnet 4.5
