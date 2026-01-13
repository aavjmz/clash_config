#!/bin/bash

# 网络优化配置检查脚本
# 创建时间: 2026-01-13
# 路径: scripts/monitoring/check-optimization.sh

OUTPUT_DIR="/root/github/clash_config/reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/optimization_check_${TIMESTAMP}.txt"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 定义输出函数
output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

# 清空或创建输出文件
> "$OUTPUT_FILE"

output "==========================================="
output "  网络优化配置检查报告"
output "  生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
output "==========================================="
output ""

output "📊 1. 系统级网络参数"
output "-------------------------------------------"
output "TCP Keepalive Time:      $(sysctl -n net.ipv4.tcp_keepalive_time) 秒 (优化值: 120)"
output "TCP Keepalive Interval:  $(sysctl -n net.ipv4.tcp_keepalive_intvl) 秒 (优化值: 15)"
output "TCP Keepalive Probes:    $(sysctl -n net.ipv4.tcp_keepalive_probes) 次 (优化值: 5)"
output "TCP Retries:             $(sysctl -n net.ipv4.tcp_retries2) 次 (优化值: 8)"
output "TCP FIN Timeout:         $(sysctl -n net.ipv4.tcp_fin_timeout) 秒 (优化值: 30)"
output "Conntrack Max:           $(sysctl -n net.netfilter.nf_conntrack_max) (优化值: 131072)"
output "Conntrack Current:       $(cat /proc/sys/net/netfilter/nf_conntrack_count)"
output "Conntrack Usage:         $(awk "BEGIN {printf \"%.2f%%\", $(cat /proc/sys/net/netfilter/nf_conntrack_count) / $(cat /proc/sys/net/netfilter/nf_conntrack_max) * 100}")"
output "Conntrack Timeout:       $(sysctl -n net.netfilter.nf_conntrack_tcp_timeout_established) 秒 (优化值: 7200)"
output ""

output "🔌 2. 连接状态统计"
output "-------------------------------------------"
ss -s | tee -a "$OUTPUT_FILE"
output ""

output "📈 3. TCP 统计（重传和超时）"
output "-------------------------------------------"
netstat -s | grep -E "segments retransmitted|connections aborted due to timeout" | head -2 | tee -a "$OUTPUT_FILE"
output ""

output "🐳 4. Docker 容器状态"
output "-------------------------------------------"
docker compose -f /root/xray-deploy/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}" | tee -a "$OUTPUT_FILE"
output ""

output "📝 5. Nginx WebSocket 配置"
output "-------------------------------------------"
output "检查 proxy_socket_keepalive 是否启用："
grep -A2 "proxy_socket_keepalive" /root/xray-deploy/nginx/conf.d/trojan.conf | tee -a "$OUTPUT_FILE" || output "❌ 未找到配置"
output ""
output "检查超时配置："
grep "proxy_.*_timeout" /root/xray-deploy/nginx/conf.d/trojan.conf | grep -v "#" | tee -a "$OUTPUT_FILE"
output ""

output "💾 6. 系统资源使用"
output "-------------------------------------------"
output "内存使用:"
free -h | tee -a "$OUTPUT_FILE"
output ""
output "CPU 负载:"
uptime | tee -a "$OUTPUT_FILE"
output ""

output "🌐 7. 网络连通性测试"
output "-------------------------------------------"
output "测试到 8.8.8.8 的连接:"
ping -c 5 -W 2 8.8.8.8 2>&1 | grep -E "transmitted|loss|avg" | tee -a "$OUTPUT_FILE"
output ""

output "==========================================="
output "✅ 检查完成！"
output "==========================================="
output ""
output "报告已保存到: $OUTPUT_FILE"
output ""
output "💡 有用的命令:"
output "  - 实时查看 Nginx 日志:"
output "    docker compose -f /root/xray-deploy/docker-compose.yml logs -f nginx"
output ""
output "  - 实时查看 Xray 日志:"
output "    docker compose -f /root/xray-deploy/docker-compose.yml logs -f xray"
output ""
output "  - 查看历史报告:"
output "    ls -lh $OUTPUT_DIR/"
output ""

# 显示报告文件路径
echo ""
echo "📄 完整报告: $OUTPUT_FILE"
echo ""

