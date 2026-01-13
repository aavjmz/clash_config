#!/bin/bash
#
# 自动应用高并发优化配置脚本
# 使用方法: sudo bash apply-high-concurrency.sh
#

set -e

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Trojan-Go 高并发优化配置部署工具${COLOR_RESET}"
echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo ""

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${COLOR_RED}错误: 请使用 sudo 运行此脚本${COLOR_RESET}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="${SCRIPT_DIR}/trojan-deploy"

# 步骤 1: 备份现有配置
echo -e "${COLOR_YELLOW}[1/6] 备份现有配置...${COLOR_RESET}"
BACKUP_DIR="${SCRIPT_DIR}/backups/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -f "${SCRIPT_DIR}/templates/trojan-config.json.template" ]; then
    cp "${SCRIPT_DIR}/templates/trojan-config.json.template" "${BACKUP_DIR}/"
fi

if [ -f "${DEPLOY_DIR}/docker-compose.yml" ]; then
    cp "${DEPLOY_DIR}/docker-compose.yml" "${BACKUP_DIR}/"
fi

echo -e "${COLOR_GREEN}✓ 备份完成: ${BACKUP_DIR}${COLOR_RESET}"

# 步骤 2: 应用 Trojan-Go 配置
echo -e "${COLOR_YELLOW}[2/6] 应用 Trojan-Go 高并发配置...${COLOR_RESET}"
if [ -f "${SCRIPT_DIR}/templates/trojan-config-high-concurrency.json.template" ]; then
    cp "${SCRIPT_DIR}/templates/trojan-config-high-concurrency.json.template" \
       "${SCRIPT_DIR}/templates/trojan-config.json.template"
    echo -e "${COLOR_GREEN}✓ Trojan-Go 配置已更新${COLOR_RESET}"
else
    echo -e "${COLOR_RED}✗ 找不到 trojan-config-high-concurrency.json.template${COLOR_RESET}"
    exit 1
fi

# 步骤 3: 应用 Docker Compose 配置
echo -e "${COLOR_YELLOW}[3/6] 应用 Docker Compose 高并发配置...${COLOR_RESET}"
if [ -f "${SCRIPT_DIR}/docker-compose-high-concurrency.yml" ]; then
    cp "${SCRIPT_DIR}/docker-compose-high-concurrency.yml" \
       "${DEPLOY_DIR}/docker-compose.yml"
    echo -e "${COLOR_GREEN}✓ Docker Compose 配置已更新${COLOR_RESET}"
else
    echo -e "${COLOR_RED}✗ 找不到 docker-compose-high-concurrency.yml${COLOR_RESET}"
    exit 1
fi

# 步骤 4: 应用 Nginx 主配置
echo -e "${COLOR_YELLOW}[4/6] 应用 Nginx 高并发配置...${COLOR_RESET}"
if [ -f "${SCRIPT_DIR}/nginx-high-concurrency.conf" ]; then
    mkdir -p "${DEPLOY_DIR}/nginx"
    cp "${SCRIPT_DIR}/nginx-high-concurrency.conf" \
       "${DEPLOY_DIR}/nginx/nginx.conf"
    echo -e "${COLOR_GREEN}✓ Nginx 配置已更新${COLOR_RESET}"
else
    echo -e "${COLOR_YELLOW}⚠ 找不到 nginx-high-concurrency.conf，跳过${COLOR_RESET}"
fi

# 步骤 5: 优化系统内核参数
echo -e "${COLOR_YELLOW}[5/6] 优化系统内核参数...${COLOR_RESET}"

# 检查是否已添加优化参数
if ! grep -q "# Trojan-Go 高并发优化" /etc/sysctl.conf; then
    cat >> /etc/sysctl.conf <<EOF

# Trojan-Go 高并发优化 - 添加于 $(date)
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 262144
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_fastopen = 3
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 2000000
fs.file-max = 2097152
vm.swappiness = 10
EOF

    # 尝试启用 BBR（可能需要内核支持）
    if lsmod | grep -q "tcp_bbr"; then
        echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
        echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    fi

    sysctl -p
    echo -e "${COLOR_GREEN}✓ 内核参数已优化${COLOR_RESET}"
else
    echo -e "${COLOR_YELLOW}⚠ 内核参数已优化过，跳过${COLOR_RESET}"
fi

# 优化文件描述符限制
if ! grep -q "# Trojan-Go limits" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf <<EOF

# Trojan-Go limits
*  soft  nofile  1048576
*  hard  nofile  1048576
*  soft  nproc   65535
*  hard  nproc   65535
root soft nofile 1048576
root hard nofile 1048576
EOF
    echo -e "${COLOR_GREEN}✓ 文件描述符限制已优化${COLOR_RESET}"
else
    echo -e "${COLOR_YELLOW}⚠ 文件描述符已优化过，跳过${COLOR_RESET}"
fi

# 步骤 6: 重启服务
echo -e "${COLOR_YELLOW}[6/6] 重启 Trojan-Go 服务...${COLOR_RESET}"
cd "$DEPLOY_DIR"

# 检查是否有运行的容器
if docker-compose ps | grep -q "Up"; then
    echo -e "${COLOR_BLUE}停止现有服务...${COLOR_RESET}"
    docker-compose down
fi

echo -e "${COLOR_BLUE}启动优化后的服务...${COLOR_RESET}"
docker-compose up -d

echo ""
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}  部署完成!${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo ""
echo -e "${COLOR_BLUE}服务状态:${COLOR_RESET}"
docker-compose ps
echo ""
echo -e "${COLOR_BLUE}查看日志:${COLOR_RESET}"
echo "  docker-compose logs -f trojan-go"
echo "  docker-compose logs -f nginx"
echo ""
echo -e "${COLOR_BLUE}性能监控:${COLOR_RESET}"
echo "  docker stats trojan-go trojan-nginx"
echo ""
echo -e "${COLOR_YELLOW}注意: 某些内核参数需要重启系统才能完全生效${COLOR_RESET}"
echo -e "${COLOR_YELLOW}建议稍后执行: sudo reboot${COLOR_RESET}"
echo ""
