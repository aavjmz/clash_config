#!/bin/bash

# 网络优化脚本 - 解决 Cursor 超时问题
# 创建时间: 2026-01-13
# 路径: scripts/network/optimize-network.sh

echo "======================================="
echo "开始优化网络参数以减少连接超时"
echo "======================================="

# 备份当前配置
echo ""
echo "1. 备份当前 sysctl 配置..."
cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)

# 优化 TCP Keepalive 参数
echo ""
echo "2. 优化 TCP Keepalive 参数..."
cat >> /etc/sysctl.conf << 'SYSCTL_EOF'

# ===== 网络优化配置 (2026-01-13) =====
# 解决 Cursor/代理连接超时问题

# TCP Keepalive 优化 - 减少死连接检测时间
net.ipv4.tcp_keepalive_time = 120        # 2分钟开始发送 keepalive (原: 7200秒)
net.ipv4.tcp_keepalive_intvl = 15        # 15秒间隔 (原: 75秒)
net.ipv4.tcp_keepalive_probes = 5        # 5次探测 (原: 9次)

# 连接跟踪超时优化
net.netfilter.nf_conntrack_tcp_timeout_established = 7200   # 2小时 (原: 5天)

# TCP 重传优化
net.ipv4.tcp_retries2 = 8                # 减少重传次数 (原: 15)

# TCP 连接优化
net.ipv4.tcp_fin_timeout = 30            # FIN-WAIT-2 超时 30秒 (原: 60)
net.ipv4.tcp_max_syn_backlog = 8192      # SYN 队列大小
net.core.somaxconn = 8192                # 连接队列大小
net.core.netdev_max_backlog = 5000       # 网卡接收队列

# TCP 快速打开 (可选，提升性能)
net.ipv4.tcp_fastopen = 3                # 启用客户端和服务端 TFO

# 连接跟踪表大小优化
net.netfilter.nf_conntrack_max = 131072  # 增加到 128k (原: 7680)

SYSCTL_EOF

echo "配置已添加到 /etc/sysctl.conf"

# 应用配置
echo ""
echo "3. 应用新配置..."
sysctl -p

echo ""
echo "4. 验证关键参数..."
echo "TCP Keepalive Time:      $(sysctl -n net.ipv4.tcp_keepalive_time) 秒"
echo "TCP Keepalive Interval:  $(sysctl -n net.ipv4.tcp_keepalive_intvl) 秒"
echo "TCP Keepalive Probes:    $(sysctl -n net.ipv4.tcp_keepalive_probes) 次"
echo "Conntrack Timeout:       $(sysctl -n net.netfilter.nf_conntrack_tcp_timeout_established) 秒"
echo "Conntrack Max:           $(sysctl -n net.netfilter.nf_conntrack_max)"

echo ""
echo "======================================="
echo "✅ 网络参数优化完成！"
echo "======================================="
echo ""
echo "说明："
echo "- TCP Keepalive: 从 2小时 减少到 2分钟"
echo "- Conntrack 超时: 从 5天 减少到 2小时"
echo "- 连接表大小: 从 7680 增加到 131072"
echo ""
echo "这些优化将："
echo "1. 更快检测和清理死连接"
echo "2. 减少连接超时问题"
echo "3. 提升代理稳定性"
echo ""
echo "配置已持久化，重启后依然生效。"
echo ""

