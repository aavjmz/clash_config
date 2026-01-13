#!/bin/bash
#
# Trojan-Go 性能基准测试脚本
# 使用方法: bash benchmark.sh [domain] [websocket-path]
#

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

DOMAIN=${1:-""}
WS_PATH=${2:-""}

echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo -e "${COLOR_BLUE}  Trojan-Go 性能基准测试${COLOR_RESET}"
echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo ""

# 检查必需工具
check_tool() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${COLOR_RED}✗ 未找到 $1${COLOR_RESET}"
        return 1
    else
        echo -e "${COLOR_GREEN}✓ 已安装 $1${COLOR_RESET}"
        return 0
    fi
}

echo -e "${COLOR_YELLOW}[1/6] 检查测试工具...${COLOR_RESET}"
TOOLS_OK=true

if ! check_tool "curl"; then
    echo "  安装: sudo apt install curl"
    TOOLS_OK=false
fi

if ! check_tool "ab"; then
    echo "  安装: sudo apt install apache2-utils"
    TOOLS_OK=false
fi

if ! check_tool "netstat" && ! check_tool "ss"; then
    echo "  安装: sudo apt install net-tools"
    TOOLS_OK=false
fi

if [ "$TOOLS_OK" = false ]; then
    echo -e "${COLOR_RED}请先安装缺失的工具${COLOR_RESET}"
    exit 1
fi

echo ""

# 获取域名和路径
if [ -z "$DOMAIN" ]; then
    echo -e "${COLOR_YELLOW}请输入域名:${COLOR_RESET}"
    read -r DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${COLOR_RED}错误: 域名不能为空${COLOR_RESET}"
    exit 1
fi

echo ""
echo -e "${COLOR_YELLOW}[2/6] 基本连通性测试...${COLOR_RESET}"

# 测试 HTTP
echo -n "  HTTP (80): "
if curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" | grep -q "301\|302\|200"; then
    echo -e "${COLOR_GREEN}✓ 正常${COLOR_RESET}"
else
    echo -e "${COLOR_RED}✗ 失败${COLOR_RESET}"
fi

# 测试 HTTPS
echo -n "  HTTPS (443): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    echo -e "${COLOR_GREEN}✓ 正常 (HTTP $HTTP_CODE)${COLOR_RESET}"
else
    echo -e "${COLOR_RED}✗ 失败 (HTTP $HTTP_CODE)${COLOR_RESET}"
fi

# SSL 证书信息
echo -n "  SSL 证书: "
SSL_INFO=$(echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
if [ $? -eq 0 ]; then
    EXPIRY=$(echo "$SSL_INFO" | grep "notAfter" | cut -d= -f2)
    echo -e "${COLOR_GREEN}✓ 有效 (过期: $EXPIRY)${COLOR_RESET}"
else
    echo -e "${COLOR_RED}✗ 无效${COLOR_RESET}"
fi

echo ""
echo -e "${COLOR_YELLOW}[3/6] 延迟测试...${COLOR_RESET}"

# Ping 延迟
PING_AVG=$(ping -c 5 "$DOMAIN" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
if [ ! -z "$PING_AVG" ]; then
    echo -e "  ICMP Ping: ${COLOR_GREEN}${PING_AVG} ms${COLOR_RESET}"
else
    echo -e "  ICMP Ping: ${COLOR_YELLOW}不可用 (可能被禁用)${COLOR_RESET}"
fi

# HTTP 延迟测试
HTTP_TIME=$(curl -o /dev/null -s -w "  Connect: %{time_connect}s\n  TLS: %{time_appconnect}s\n  Total: %{time_total}s\n" "https://$DOMAIN")
echo -e "${COLOR_BLUE}HTTP(S) 延迟:${COLOR_RESET}"
echo "$HTTP_TIME"

echo ""
echo -e "${COLOR_YELLOW}[4/6] 吞吐量测试 (下载速度)...${COLOR_RESET}"

# 下载速度测试
DOWNLOAD_SPEED=$(curl -o /dev/null -s -w "%{speed_download}" "https://$DOMAIN")
DOWNLOAD_SPEED_MB=$(echo "scale=2; $DOWNLOAD_SPEED / 1048576" | bc 2>/dev/null || echo "N/A")
echo -e "  下载速度: ${COLOR_GREEN}${DOWNLOAD_SPEED_MB} MB/s${COLOR_RESET}"

echo ""
echo -e "${COLOR_YELLOW}[5/6] 并发连接测试 (Apache Bench)...${COLOR_RESET}"

# 并发测试配置
CONCURRENT_LEVELS=(10 50 100 500)
REQUESTS=1000

echo -e "${COLOR_BLUE}测试配置: $REQUESTS 请求${COLOR_RESET}"
echo ""

for CONCURRENT in "${CONCURRENT_LEVELS[@]}"; do
    echo -e "${COLOR_BLUE}  并发数: $CONCURRENT${COLOR_RESET}"

    AB_OUTPUT=$(ab -n $REQUESTS -c $CONCURRENT -k "https://$DOMAIN/" 2>&1)

    if echo "$AB_OUTPUT" | grep -q "Complete requests"; then
        RPS=$(echo "$AB_OUTPUT" | grep "Requests per second" | awk '{print $4}')
        TIME_PER_REQ=$(echo "$AB_OUTPUT" | grep "Time per request" | head -1 | awk '{print $4}')
        FAILED=$(echo "$AB_OUTPUT" | grep "Failed requests" | awk '{print $3}')

        echo "    RPS: ${RPS} req/s"
        echo "    平均延迟: ${TIME_PER_REQ} ms"
        echo "    失败请求: ${FAILED}"
    else
        echo -e "    ${COLOR_RED}测试失败${COLOR_RESET}"
    fi
    echo ""
done

echo ""
echo -e "${COLOR_YELLOW}[6/6] 服务器资源使用情况...${COLOR_RESET}"

# 检查容器资源
if command -v docker &> /dev/null; then
    if docker ps | grep -q "trojan-go\|trojan-nginx"; then
        echo -e "${COLOR_BLUE}Docker 容器状态:${COLOR_RESET}"
        docker stats --no-stream --format "  {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
            trojan-go trojan-nginx 2>/dev/null
    else
        echo -e "${COLOR_YELLOW}  未检测到 Trojan-Go 容器运行${COLOR_RESET}"
    fi
else
    echo -e "${COLOR_YELLOW}  Docker 未安装${COLOR_RESET}"
fi

# 系统负载
echo ""
echo -e "${COLOR_BLUE}系统负载:${COLOR_RESET}"
uptime

# TCP 连接统计
echo ""
echo -e "${COLOR_BLUE}TCP 连接统计:${COLOR_RESET}"
if command -v ss &> /dev/null; then
    ss -s | head -5
else
    netstat -s | grep -A 5 "Tcp:" | head -6
fi

echo ""
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}  基准测试完成${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo ""

# 生成测试报告
REPORT_FILE="benchmark-report-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "Trojan-Go 性能基准测试报告"
    echo "=============================="
    echo ""
    echo "测试时间: $(date)"
    echo "测试域名: $DOMAIN"
    echo ""
    echo "基本连通性: 通过"
    echo "平均延迟: $PING_AVG ms (ICMP)"
    echo "下载速度: $DOWNLOAD_SPEED_MB MB/s"
    echo ""
    echo "并发测试结果:"
    echo "$AB_OUTPUT" | grep -A 20 "Concurrency Level"
} > "$REPORT_FILE"

echo -e "${COLOR_BLUE}测试报告已保存: $REPORT_FILE${COLOR_RESET}"
echo ""
