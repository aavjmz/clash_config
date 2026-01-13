#!/bin/bash
#
# Trojan-Go 性能监控脚本
# 使用方法: bash monitor-performance.sh [interval]
#

INTERVAL=${1:-5}  # 默认 5 秒刷新
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

clear

while true; do
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
    echo -e "${COLOR_BLUE}  Trojan-Go 性能监控${COLOR_RESET}"
    echo -e "${COLOR_BLUE}  更新时间: $(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
    echo ""

    # Trojan-Go 连接数
    echo -e "${COLOR_GREEN}[1] Trojan-Go 连接统计${COLOR_RESET}"
    if docker exec trojan-go netstat -an 2>/dev/null | grep -q ":8443"; then
        TROJAN_CONN=$(docker exec trojan-go netstat -an 2>/dev/null | grep :8443 | wc -l)
        TROJAN_ESTABLISHED=$(docker exec trojan-go netstat -an 2>/dev/null | grep :8443 | grep ESTABLISHED | wc -l)
        echo "  总连接数: $TROJAN_CONN"
        echo "  活跃连接: $TROJAN_ESTABLISHED"
    else
        echo "  无法获取连接数据（容器可能未运行）"
    fi
    echo ""

    # Nginx 连接数
    echo -e "${COLOR_GREEN}[2] Nginx 连接统计${COLOR_RESET}"
    if docker exec trojan-nginx netstat -an 2>/dev/null | grep -q ":443"; then
        NGINX_CONN=$(docker exec trojan-nginx netstat -an 2>/dev/null | grep :443 | wc -l)
        NGINX_ESTABLISHED=$(docker exec trojan-nginx netstat -an 2>/dev/null | grep :443 | grep ESTABLISHED | wc -l)
        echo "  总连接数: $NGINX_CONN"
        echo "  活跃连接: $NGINX_ESTABLISHED"
    else
        echo "  无法获取连接数据（容器可能未运行）"
    fi
    echo ""

    # 容器资源使用
    echo -e "${COLOR_GREEN}[3] 容器资源使用${COLOR_RESET}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \
        trojan-go trojan-nginx 2>/dev/null || echo "  无法获取容器统计"
    echo ""

    # TCP 连接状态统计
    echo -e "${COLOR_GREEN}[4] 系统 TCP 连接状态${COLOR_RESET}"
    ss -s 2>/dev/null || netstat -s 2>/dev/null | grep -A 10 "Tcp:"
    echo ""

    # 系统负载
    echo -e "${COLOR_GREEN}[5] 系统负载${COLOR_RESET}"
    uptime
    echo ""

    # 磁盘使用
    echo -e "${COLOR_GREEN}[6] 磁盘使用 (日志目录)${COLOR_RESET}"
    DEPLOY_DIR="$(cd "$(dirname "$0")/trojan-deploy" 2>/dev/null && pwd)"
    if [ -d "$DEPLOY_DIR" ]; then
        du -sh "$DEPLOY_DIR/trojan-go/logs" 2>/dev/null || echo "  日志目录不存在"
        du -sh "$DEPLOY_DIR/nginx" 2>/dev/null || echo "  Nginx 目录不存在"
    fi
    echo ""

    echo -e "${COLOR_YELLOW}按 Ctrl+C 退出监控... (${INTERVAL}s 后刷新)${COLOR_RESET}"
    echo ""

    sleep "$INTERVAL"
    clear
done
