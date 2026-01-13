#!/bin/bash
#
# Trojan-Go 压力测试脚本
# 警告: 此脚本会产生高负载，仅在测试环境使用
# 使用方法: bash stress-test.sh [domain]
#

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

DOMAIN=${1:-""}

echo -e "${COLOR_RED}========================================${COLOR_RESET}"
echo -e "${COLOR_RED}  ⚠️  Trojan-Go 压力测试工具  ⚠️${COLOR_RESET}"
echo -e "${COLOR_RED}========================================${COLOR_RESET}"
echo -e "${COLOR_YELLOW}"
echo "警告: 此脚本会对服务器产生高负载!"
echo "仅应在测试环境或经过授权的情况下使用"
echo -e "${COLOR_RESET}"
echo -n "是否继续? (yes/no): "
read -r CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "已取消"
    exit 0
fi

echo ""

# 获取域名
if [ -z "$DOMAIN" ]; then
    echo -e "${COLOR_YELLOW}请输入测试域名:${COLOR_RESET}"
    read -r DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${COLOR_RED}错误: 域名不能为空${COLOR_RESET}"
    exit 1
fi

# 检查工具
echo -e "${COLOR_YELLOW}检查压测工具...${COLOR_RESET}"

if ! command -v ab &> /dev/null; then
    echo -e "${COLOR_RED}✗ Apache Bench (ab) 未安装${COLOR_RESET}"
    echo "安装: sudo apt install apache2-utils"
    USE_AB=false
else
    echo -e "${COLOR_GREEN}✓ Apache Bench 可用${COLOR_RESET}"
    USE_AB=true
fi

if ! command -v wrk &> /dev/null; then
    echo -e "${COLOR_YELLOW}⚠ wrk 未安装 (可选)${COLOR_RESET}"
    echo "安装: sudo apt install wrk 或从源码编译"
    USE_WRK=false
else
    echo -e "${COLOR_GREEN}✓ wrk 可用${COLOR_RESET}"
    USE_WRK=true
fi

echo ""

# 测试配置
TEST_URL="https://$DOMAIN/"
TEST_DURATION=30  # 秒

echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo -e "${COLOR_BLUE}  压力测试配置${COLOR_RESET}"
echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo "目标 URL: $TEST_URL"
echo "测试时长: ${TEST_DURATION}s"
echo ""

# 创建结果目录
RESULT_DIR="stress-test-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULT_DIR"

echo -e "${COLOR_YELLOW}开始压力测试...${COLOR_RESET}"
echo ""

# 测试 1: 低并发基准 (100 并发)
echo -e "${COLOR_BLUE}[测试 1/5] 基准测试 - 100 并发${COLOR_RESET}"
if [ "$USE_AB" = true ]; then
    ab -n 10000 -c 100 -k "$TEST_URL" > "$RESULT_DIR/01-baseline-100c.txt" 2>&1
    RPS=$(grep "Requests per second" "$RESULT_DIR/01-baseline-100c.txt" | awk '{print $4}')
    echo -e "  结果: ${COLOR_GREEN}${RPS} req/s${COLOR_RESET}"
else
    echo -e "  ${COLOR_YELLOW}跳过 (ab 不可用)${COLOR_RESET}"
fi
echo ""

# 测试 2: 中等并发 (500 并发)
echo -e "${COLOR_BLUE}[测试 2/5] 中等负载 - 500 并发${COLOR_RESET}"
if [ "$USE_AB" = true ]; then
    ab -n 50000 -c 500 -k "$TEST_URL" > "$RESULT_DIR/02-medium-500c.txt" 2>&1
    RPS=$(grep "Requests per second" "$RESULT_DIR/02-medium-500c.txt" | awk '{print $4}')
    echo -e "  结果: ${COLOR_GREEN}${RPS} req/s${COLOR_RESET}"
else
    echo -e "  ${COLOR_YELLOW}跳过 (ab 不可用)${COLOR_RESET}"
fi
echo ""

# 测试 3: 高并发 (1000 并发)
echo -e "${COLOR_BLUE}[测试 3/5] 高负载 - 1000 并发${COLOR_RESET}"
if [ "$USE_AB" = true ]; then
    ab -n 100000 -c 1000 -k "$TEST_URL" > "$RESULT_DIR/03-high-1000c.txt" 2>&1
    RPS=$(grep "Requests per second" "$RESULT_DIR/03-high-1000c.txt" | awk '{print $4}')
    FAILED=$(grep "Failed requests" "$RESULT_DIR/03-high-1000c.txt" | awk '{print $3}')
    echo -e "  结果: ${COLOR_GREEN}${RPS} req/s${COLOR_RESET}, 失败: ${FAILED}"
else
    echo -e "  ${COLOR_YELLOW}跳过 (ab 不可用)${COLOR_RESET}"
fi
echo ""

# 测试 4: 极限并发 (5000 并发)
echo -e "${COLOR_BLUE}[测试 4/5] 极限负载 - 5000 并发${COLOR_RESET}"
echo -e "${COLOR_YELLOW}  警告: 这将产生极高负载${COLOR_RESET}"
if [ "$USE_AB" = true ]; then
    ab -n 50000 -c 5000 -k "$TEST_URL" > "$RESULT_DIR/04-extreme-5000c.txt" 2>&1
    RPS=$(grep "Requests per second" "$RESULT_DIR/04-extreme-5000c.txt" | awk '{print $4}')
    FAILED=$(grep "Failed requests" "$RESULT_DIR/04-extreme-5000c.txt" | awk '{print $3}')
    echo -e "  结果: ${COLOR_GREEN}${RPS} req/s${COLOR_RESET}, 失败: ${FAILED}"
else
    echo -e "  ${COLOR_YELLOW}跳过 (ab 不可用)${COLOR_RESET}"
fi
echo ""

# 测试 5: wrk 持续压测
if [ "$USE_WRK" = true ]; then
    echo -e "${COLOR_BLUE}[测试 5/5] wrk 持续压测 - 12 线程 400 连接 ${TEST_DURATION}s${COLOR_RESET}"
    wrk -t12 -c400 -d${TEST_DURATION}s "$TEST_URL" > "$RESULT_DIR/05-wrk-sustained.txt" 2>&1

    RPS=$(grep "Requests/sec" "$RESULT_DIR/05-wrk-sustained.txt" | awk '{print $2}')
    LATENCY_AVG=$(grep "Latency" "$RESULT_DIR/05-wrk-sustained.txt" | awk '{print $2}')
    echo -e "  结果: ${COLOR_GREEN}${RPS} req/s${COLOR_RESET}, 平均延迟: ${LATENCY_AVG}"
else
    echo -e "${COLOR_BLUE}[测试 5/5] wrk 测试${COLOR_RESET}"
    echo -e "  ${COLOR_YELLOW}跳过 (wrk 不可用)${COLOR_RESET}"
fi
echo ""

# 收集服务器指标
echo -e "${COLOR_YELLOW}收集服务器指标...${COLOR_RESET}"

{
    echo "=== 系统信息 ==="
    uname -a
    echo ""

    echo "=== CPU 信息 ==="
    lscpu | grep -E "^CPU\(s\)|^Model name|^CPU MHz"
    echo ""

    echo "=== 内存信息 ==="
    free -h
    echo ""

    echo "=== 系统负载 ==="
    uptime
    echo ""

    echo "=== TCP 连接统计 ==="
    if command -v ss &> /dev/null; then
        ss -s
    else
        netstat -s | grep -A 10 "Tcp:"
    fi
    echo ""

    echo "=== Docker 容器状态 ==="
    if command -v docker &> /dev/null; then
        docker stats --no-stream trojan-go trojan-nginx 2>/dev/null || echo "容器未运行"
    fi
} > "$RESULT_DIR/server-metrics.txt"

# 生成汇总报告
echo -e "${COLOR_YELLOW}生成测试报告...${COLOR_RESET}"

{
    echo "======================================"
    echo "  Trojan-Go 压力测试报告"
    echo "======================================"
    echo ""
    echo "测试时间: $(date)"
    echo "测试目标: $TEST_URL"
    echo ""

    echo "【测试结果摘要】"
    echo ""

    if [ -f "$RESULT_DIR/01-baseline-100c.txt" ]; then
        echo "1. 基准测试 (100 并发):"
        grep "Requests per second" "$RESULT_DIR/01-baseline-100c.txt"
        grep "Time per request" "$RESULT_DIR/01-baseline-100c.txt" | head -2
        grep "Failed requests" "$RESULT_DIR/01-baseline-100c.txt"
        echo ""
    fi

    if [ -f "$RESULT_DIR/02-medium-500c.txt" ]; then
        echo "2. 中等负载 (500 并发):"
        grep "Requests per second" "$RESULT_DIR/02-medium-500c.txt"
        grep "Time per request" "$RESULT_DIR/02-medium-500c.txt" | head -2
        grep "Failed requests" "$RESULT_DIR/02-medium-500c.txt"
        echo ""
    fi

    if [ -f "$RESULT_DIR/03-high-1000c.txt" ]; then
        echo "3. 高负载 (1000 并发):"
        grep "Requests per second" "$RESULT_DIR/03-high-1000c.txt"
        grep "Time per request" "$RESULT_DIR/03-high-1000c.txt" | head -2
        grep "Failed requests" "$RESULT_DIR/03-high-1000c.txt"
        echo ""
    fi

    if [ -f "$RESULT_DIR/04-extreme-5000c.txt" ]; then
        echo "4. 极限负载 (5000 并发):"
        grep "Requests per second" "$RESULT_DIR/04-extreme-5000c.txt"
        grep "Time per request" "$RESULT_DIR/04-extreme-5000c.txt" | head -2
        grep "Failed requests" "$RESULT_DIR/04-extreme-5000c.txt"
        echo ""
    fi

    if [ -f "$RESULT_DIR/05-wrk-sustained.txt" ]; then
        echo "5. wrk 持续压测:"
        cat "$RESULT_DIR/05-wrk-sustained.txt"
        echo ""
    fi

    echo ""
    echo "【详细结果】"
    echo "所有测试结果已保存到: $RESULT_DIR/"

} > "$RESULT_DIR/SUMMARY.txt"

echo ""
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}  压力测试完成${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo ""
echo -e "${COLOR_BLUE}测试结果保存在: ${COLOR_YELLOW}$RESULT_DIR/${COLOR_RESET}"
echo ""
echo -e "${COLOR_BLUE}查看摘要:${COLOR_RESET}"
echo "  cat $RESULT_DIR/SUMMARY.txt"
echo ""
echo -e "${COLOR_BLUE}查看详细结果:${COLOR_RESET}"
echo "  ls $RESULT_DIR/"
echo ""
