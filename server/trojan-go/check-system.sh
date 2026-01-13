#!/bin/bash
#
# Trojan-Go 系统环境检查脚本
# 检查系统是否满足高并发优化要求
# 使用方法: bash check-system.sh
#

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

check_pass() {
    echo -e "  ${COLOR_GREEN}✓ PASS${COLOR_RESET} - $1"
    ((PASS_COUNT++))
}

check_warn() {
    echo -e "  ${COLOR_YELLOW}⚠ WARN${COLOR_RESET} - $1"
    ((WARN_COUNT++))
}

check_fail() {
    echo -e "  ${COLOR_RED}✗ FAIL${COLOR_RESET} - $1"
    ((FAIL_COUNT++))
}

echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Trojan-Go 系统环境检查${COLOR_RESET}"
echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo ""

# 1. 操作系统检查
echo -e "${COLOR_YELLOW}[1/10] 操作系统${COLOR_RESET}"
OS_TYPE=$(uname -s)
OS_VERSION=$(uname -r)
echo "  系统类型: $OS_TYPE"
echo "  内核版本: $OS_VERSION"

if [ "$OS_TYPE" = "Linux" ]; then
    check_pass "Linux 系统"

    # 检查内核版本（BBR 需要 4.9+）
    KERNEL_MAJOR=$(echo "$OS_VERSION" | cut -d. -f1)
    KERNEL_MINOR=$(echo "$OS_VERSION" | cut -d. -f2)

    if [ "$KERNEL_MAJOR" -gt 4 ] || ([ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -ge 9 ]); then
        check_pass "内核版本支持 BBR ($OS_VERSION >= 4.9)"
    else
        check_warn "内核版本较旧 ($OS_VERSION < 4.9)，BBR 不可用"
    fi
else
    check_fail "不支持的操作系统: $OS_TYPE"
fi
echo ""

# 2. CPU 检查
echo -e "${COLOR_YELLOW}[2/10] CPU 资源${COLOR_RESET}"
CPU_CORES=$(nproc 2>/dev/null || echo "unknown")
echo "  CPU 核心数: $CPU_CORES"

if [ "$CPU_CORES" != "unknown" ]; then
    if [ "$CPU_CORES" -ge 4 ]; then
        check_pass "CPU 核心数充足 ($CPU_CORES >= 4)"
    elif [ "$CPU_CORES" -ge 2 ]; then
        check_warn "CPU 核心数偏低 ($CPU_CORES)，建议 4 核以上"
    else
        check_fail "CPU 核心数不足 ($CPU_CORES < 2)"
    fi
else
    check_warn "无法检测 CPU 核心数"
fi
echo ""

# 3. 内存检查
echo -e "${COLOR_YELLOW}[3/10] 内存资源${COLOR_RESET}"
if command -v free &> /dev/null; then
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    echo "  总内存: ${TOTAL_MEM} MB"

    if [ "$TOTAL_MEM" -ge 4096 ]; then
        check_pass "内存充足 ($TOTAL_MEM MB >= 4GB)"
    elif [ "$TOTAL_MEM" -ge 2048 ]; then
        check_warn "内存偏低 ($TOTAL_MEM MB)，建议 4GB 以上"
    else
        check_fail "内存不足 ($TOTAL_MEM MB < 2GB)"
    fi
else
    check_warn "无法检测内存信息"
fi
echo ""

# 4. Docker 检查
echo -e "${COLOR_YELLOW}[4/10] Docker 环境${COLOR_RESET}"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    echo "  Docker 版本: $DOCKER_VERSION"
    check_pass "Docker 已安装"

    # 检查 Docker 是否运行
    if docker ps &> /dev/null; then
        check_pass "Docker 服务正常运行"
    else
        check_fail "Docker 服务未运行或无权限"
    fi

    # 检查 Docker Compose
    if command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version | awk '{print $4}' | tr -d ',')
        echo "  Docker Compose 版本: $COMPOSE_VERSION"
        check_pass "Docker Compose 已安装"
    elif docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version --short)
        echo "  Docker Compose 版本: $COMPOSE_VERSION (V2)"
        check_pass "Docker Compose V2 已安装"
    else
        check_fail "Docker Compose 未安装"
    fi
else
    check_fail "Docker 未安装"
fi
echo ""

# 5. 内核参数检查
echo -e "${COLOR_YELLOW}[5/10] 内核参数${COLOR_RESET}"

check_sysctl() {
    local param=$1
    local expected=$2
    local current=$(sysctl -n "$param" 2>/dev/null || echo "N/A")

    echo "  $param: $current (期望: $expected)"

    if [ "$current" = "N/A" ]; then
        check_warn "$param 不存在"
    elif [ "$current" -ge "$expected" ] 2>/dev/null; then
        check_pass "$param 已优化"
    else
        check_warn "$param 未优化 (当前: $current, 建议: $expected)"
    fi
}

check_sysctl "net.core.somaxconn" 65535
check_sysctl "net.ipv4.tcp_max_syn_backlog" 8192
check_sysctl "fs.file-max" 2097152
echo ""

# 6. TCP Fast Open 检查
echo -e "${COLOR_YELLOW}[6/10] TCP Fast Open${COLOR_RESET}"
TFO=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo "N/A")
echo "  tcp_fastopen: $TFO"

if [ "$TFO" = "N/A" ]; then
    check_warn "TCP Fast Open 不可用"
elif [ "$TFO" -eq 3 ]; then
    check_pass "TCP Fast Open 已启用 (客户端+服务端)"
elif [ "$TFO" -eq 2 ]; then
    check_warn "TCP Fast Open 仅服务端启用，建议设为 3"
else
    check_warn "TCP Fast Open 未启用，建议设为 3"
fi
echo ""

# 7. BBR 检查
echo -e "${COLOR_YELLOW}[7/10] BBR 拥塞控制${COLOR_RESET}"
BBR=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")
echo "  拥塞控制算法: $BBR"

if [ "$BBR" = "bbr" ]; then
    check_pass "BBR 已启用"

    if lsmod | grep -q tcp_bbr; then
        check_pass "BBR 模块已加载"
    else
        check_warn "BBR 模块未加载"
    fi
elif [ "$BBR" = "cubic" ]; then
    check_warn "使用默认算法 (cubic)，建议启用 BBR"
else
    check_warn "未知拥塞控制算法: $BBR"
fi
echo ""

# 8. 文件描述符检查
echo -e "${COLOR_YELLOW}[8/10] 文件描述符限制${COLOR_RESET}"
ULIMIT_N=$(ulimit -n)
echo "  当前用户限制: $ULIMIT_N"

if [ "$ULIMIT_N" -ge 1048576 ]; then
    check_pass "文件描述符限制已优化 ($ULIMIT_N >= 1048576)"
elif [ "$ULIMIT_N" -ge 65535 ]; then
    check_warn "文件描述符限制偏低 ($ULIMIT_N)，建议 1048576"
else
    check_fail "文件描述符限制过低 ($ULIMIT_N < 65535)"
fi

# 检查系统全局限制
FILE_MAX=$(cat /proc/sys/fs/file-max 2>/dev/null || echo "N/A")
echo "  系统全局限制: $FILE_MAX"

if [ "$FILE_MAX" != "N/A" ] && [ "$FILE_MAX" -ge 2097152 ]; then
    check_pass "系统文件描述符限制充足"
else
    check_warn "系统文件描述符限制偏低，建议 2097152"
fi
echo ""

# 9. 端口可用性检查
echo -e "${COLOR_YELLOW}[9/10] 端口占用检查${COLOR_RESET}"

check_port() {
    local port=$1
    if command -v netstat &> /dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo "  端口 $port: 已占用"
            check_warn "端口 $port 已被占用"
        else
            echo "  端口 $port: 可用"
            check_pass "端口 $port 可用"
        fi
    elif command -v ss &> /dev/null; then
        if ss -tuln 2>/dev/null | grep -q ":$port "; then
            echo "  端口 $port: 已占用"
            check_warn "端口 $port 已被占用"
        else
            echo "  端口 $port: 可用"
            check_pass "端口 $port 可用"
        fi
    else
        check_warn "无法检查端口 (netstat/ss 未安装)"
    fi
}

check_port 80
check_port 443
check_port 8443
echo ""

# 10. 磁盘空间检查
echo -e "${COLOR_YELLOW}[10/10] 磁盘空间${COLOR_RESET}"
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
DISK_AVAIL_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
echo "  可用空间: $DISK_AVAIL"

if [ "$DISK_AVAIL_GB" -ge 10 ]; then
    check_pass "磁盘空间充足 ($DISK_AVAIL >= 10GB)"
elif [ "$DISK_AVAIL_GB" -ge 5 ]; then
    check_warn "磁盘空间偏低 ($DISK_AVAIL)，建议 10GB 以上"
else
    check_fail "磁盘空间不足 ($DISK_AVAIL < 5GB)"
fi
echo ""

# 汇总结果
echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo -e "${COLOR_BLUE}  检查结果汇总${COLOR_RESET}"
echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo ""
echo -e "${COLOR_GREEN}通过: $PASS_COUNT${COLOR_RESET}"
echo -e "${COLOR_YELLOW}警告: $WARN_COUNT${COLOR_RESET}"
echo -e "${COLOR_RED}失败: $FAIL_COUNT${COLOR_RESET}"
echo ""

# 给出建议
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "${COLOR_RED}系统环境存在问题，请先解决失败项${COLOR_RESET}"
    echo ""
    echo "常见解决方案:"
    echo "1. 安装 Docker: curl -fsSL https://get.docker.com | sh"
    echo "2. 优化内核参数: sudo bash apply-high-concurrency.sh"
    echo "3. 升级服务器配置: 建议 4 核 CPU + 4GB 内存"
    exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
    echo -e "${COLOR_YELLOW}系统环境基本满足要求，但有部分警告项${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}建议运行优化脚本: sudo bash apply-high-concurrency.sh${COLOR_RESET}"
    exit 0
else
    echo -e "${COLOR_GREEN}✓ 系统环境完全满足高并发优化要求！${COLOR_RESET}"
    echo -e "${COLOR_GREEN}可以直接部署: sudo bash apply-high-concurrency.sh${COLOR_RESET}"
    exit 0
fi
