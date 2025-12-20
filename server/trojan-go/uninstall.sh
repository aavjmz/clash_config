#!/bin/bash

################################################################################
# Trojan-Go 一键卸载脚本
#
# 功能：
# - 停止并删除所有 Docker 容器
# - 可选删除配置文件和数据
# - 可选删除 SSL 证书
# - 可选删除 Docker 镜像
# - 可选卸载 Docker 环境
# - 可选清理防火墙规则
#
# 使用方法：
# sudo bash uninstall.sh
################################################################################

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 全局变量
DEPLOY_DIR="/root/trojan-deploy"

# 打印函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 打印横幅
print_banner() {
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                                          ║${NC}"
    echo -e "${YELLOW}║        Trojan-Go 一键卸载脚本 v1.0                       ║${NC}"
    echo -e "${YELLOW}║        ⚠️  警告：此操作将删除所有相关服务                ║${NC}"
    echo -e "${YELLOW}║                                                          ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户或 sudo 运行此脚本"
        exit 1
    fi
}

# 显示当前部署信息
show_deployment_info() {
    echo -e "${BLUE}【当前部署信息】${NC}"
    echo ""

    if [ -f "$DEPLOY_DIR/deployment-info.txt" ]; then
        print_info "找到部署信息文件"
        echo ""
        cat "$DEPLOY_DIR/deployment-info.txt"
        echo ""
    else
        print_warning "未找到部署信息文件"
    fi

    if [ -d "$DEPLOY_DIR" ]; then
        print_info "部署目录: $DEPLOY_DIR"
        print_info "目录大小: $(du -sh "$DEPLOY_DIR" 2>/dev/null | cut -f1 || echo '未知')"
    else
        print_warning "未找到部署目录"
    fi

    echo ""
}

# 停止并删除容器
stop_and_remove_containers() {
    print_info "停止并删除 Docker 容器..."

    if [ -f "$DEPLOY_DIR/docker-compose.yml" ]; then
        cd "$DEPLOY_DIR"

        # 尝试使用 docker compose (V2) 或 docker-compose (V1)
        if docker compose version &> /dev/null; then
            docker compose down -v
        elif docker-compose --version &> /dev/null; then
            docker-compose down -v
        else
            print_warning "未找到 docker compose 命令，尝试手动停止容器..."
            docker stop trojan-nginx trojan-go trojan-certbot 2>/dev/null || true
            docker rm trojan-nginx trojan-go trojan-certbot 2>/dev/null || true
        fi

        print_success "容器已停止并删除"
    else
        print_warning "未找到 docker-compose.yml 文件"

        # 尝试停止可能存在的容器
        print_info "尝试停止可能存在的容器..."
        docker stop trojan-nginx trojan-go trojan-certbot 2>/dev/null || true
        docker rm trojan-nginx trojan-go trojan-certbot 2>/dev/null || true
    fi
}

# 删除配置文件
delete_config_files() {
    echo ""
    print_warning "即将删除所有配置文件和数据"
    print_info "路径: $DEPLOY_DIR"

    read -p "确认删除配置文件？[y/N]: " del_config

    if [[ "$del_config" =~ ^[Yy]$ ]]; then
        print_info "删除配置文件目录..."

        if [ -d "$DEPLOY_DIR" ]; then
            rm -rf "$DEPLOY_DIR"
            print_success "配置文件已删除"
        else
            print_warning "配置目录不存在"
        fi
    else
        print_info "保留配置文件在: $DEPLOY_DIR"
    fi
}

# 删除 SSL 证书
delete_ssl_certificates() {
    echo ""
    print_info "SSL 证书处理"
    print_info "默认保留证书，避免频繁申请触发 Let's Encrypt 速率限制"
    print_warning "Let's Encrypt 限制：每个域名每周最多申请 5 次证书"

    read -p "是否删除 SSL 证书？（默认保留）[y/N]: " del_cert

    if [[ "$del_cert" =~ ^[Yy]$ ]]; then
        if [ -d "$DEPLOY_DIR/certbot/conf" ]; then
            print_info "删除 SSL 证书..."
            rm -rf "$DEPLOY_DIR/certbot/conf"
            print_success "证书已删除"
        else
            print_warning "未找到证书目录"
        fi
    else
        print_success "保留 SSL 证书（推荐）"
        print_info "证书位置: $DEPLOY_DIR/certbot/conf"
    fi
}

# 删除 Docker 镜像
delete_docker_images() {
    echo ""
    print_warning "是否删除 Trojan-Go 相关 Docker 镜像？"
    print_info "镜像列表："
    echo "  - nginx:alpine"
    echo "  - p4gefau1t/trojan-go:latest"
    echo "  - certbot/certbot"

    read -p "删除 Docker 镜像？[y/N]: " del_images

    if [[ "$del_images" =~ ^[Yy]$ ]]; then
        print_info "删除 Docker 镜像..."

        docker rmi nginx:alpine 2>/dev/null && print_success "已删除 nginx:alpine" || print_warning "nginx:alpine 镜像不存在或删除失败"
        docker rmi p4gefau1t/trojan-go:latest 2>/dev/null && print_success "已删除 p4gefau1t/trojan-go:latest" || print_warning "trojan-go 镜像不存在或删除失败"
        docker rmi certbot/certbot 2>/dev/null && print_success "已删除 certbot/certbot" || print_warning "certbot 镜像不存在或删除失败"

        print_success "镜像清理完成"
    else
        print_info "保留 Docker 镜像"
    fi
}

# 删除 Docker 网络
delete_docker_network() {
    print_info "清理 Docker 网络..."

    if docker network ls | grep -q "trojan-net"; then
        docker network rm trojan-net 2>/dev/null && print_success "已删除 trojan-net 网络" || print_warning "网络删除失败（可能仍在使用）"
    fi
}

# 卸载 Docker
uninstall_docker() {
    echo ""
    print_error "⚠️  警告：即将卸载 Docker 环境"
    print_warning "如果您的服务器上还运行着其他 Docker 容器，请勿执行此操作！"

    read -p "确认卸载 Docker？[y/N]: " del_docker

    if [[ "$del_docker" =~ ^[Yy]$ ]]; then
        print_info "开始卸载 Docker..."

        # 停止 Docker 服务
        systemctl stop docker 2>/dev/null || true
        systemctl disable docker 2>/dev/null || true

        # 检测系统类型并卸载
        if [ -f /etc/os-release ]; then
            . /etc/os-release

            if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
                print_info "检测到 Ubuntu/Debian 系统，使用 apt 卸载..."
                apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin 2>/dev/null || true
                apt-get autoremove -y 2>/dev/null || true
                apt-get autoclean 2>/dev/null || true

            elif [ "$ID" = "centos" ] || [ "$ID" = "rhel" ] || [ "$ID" = "rocky" ] || [ "$ID" = "almalinux" ]; then
                print_info "检测到 CentOS/RHEL 系统，使用 yum 卸载..."
                yum remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin 2>/dev/null || true
                yum autoremove -y 2>/dev/null || true
            fi
        fi

        # 删除 Docker 数据目录
        print_info "删除 Docker 数据目录..."
        rm -rf /var/lib/docker
        rm -rf /var/lib/containerd
        rm -rf /etc/docker

        # 删除 Docker 用户组
        groupdel docker 2>/dev/null || true

        print_success "Docker 已卸载"
    else
        print_info "保留 Docker 环境"
    fi
}

# 清理防火墙规则
cleanup_firewall_rules() {
    echo ""
    print_warning "是否清理防火墙规则（端口 80, 443）？"

    read -p "清理防火墙规则？[y/N]: " del_fw

    if [[ "$del_fw" =~ ^[Yy]$ ]]; then
        print_info "清理防火墙规则..."

        # UFW (Ubuntu/Debian)
        if command -v ufw &> /dev/null; then
            print_info "检测到 UFW，删除规则..."
            ufw delete allow 80/tcp 2>/dev/null && print_success "已删除 UFW 规则: 80/tcp" || true
            ufw delete allow 443/tcp 2>/dev/null && print_success "已删除 UFW 规则: 443/tcp" || true
        fi

        # Firewalld (CentOS/RHEL)
        if command -v firewall-cmd &> /dev/null; then
            print_info "检测到 Firewalld，删除规则..."
            firewall-cmd --permanent --remove-service=http 2>/dev/null && print_success "已删除 Firewalld 规则: http" || true
            firewall-cmd --permanent --remove-service=https 2>/dev/null && print_success "已删除 Firewalld 规则: https" || true
            firewall-cmd --reload 2>/dev/null || true
        fi

        # iptables
        if command -v iptables &> /dev/null && [ ! -f /usr/sbin/ufw ] && [ ! -f /usr/bin/firewall-cmd ]; then
            print_info "检测到 iptables，清理规则..."
            iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null && print_success "已删除 iptables 规则: 80" || true
            iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null && print_success "已删除 iptables 规则: 443" || true
        fi

        print_success "防火墙规则清理完成"
    else
        print_info "保留防火墙规则"
    fi
}

# 清理旧的脚本文件
cleanup_old_scripts() {
    print_info "清理旧的脚本文件..."

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local old_scripts=(
        "$script_dir/step1.sh"
        "$DEPLOY_DIR/step2.sh"
        "$DEPLOY_DIR/step3.sh"
        "$DEPLOY_DIR/step4.sh"
        "$DEPLOY_DIR/step5.sh"
        "$DEPLOY_DIR/step6.sh"
        "$DEPLOY_DIR/step7.sh"
        "$DEPLOY_DIR/step7_2.sh"
        "$DEPLOY_DIR/step8.sh"
        "$DEPLOY_DIR/step9.sh"
        "$DEPLOY_DIR/cmdline.sh"
    )

    local removed_count=0
    for script in "${old_scripts[@]}"; do
        if [ -f "$script" ]; then
            rm -f "$script" 2>/dev/null && ((removed_count++)) || true
        fi
    done

    if [ $removed_count -gt 0 ]; then
        print_success "已清理 $removed_count 个旧脚本文件"
    else
        print_info "未找到旧脚本文件"
    fi
}

# 显示卸载摘要
show_uninstall_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}║              卸载完成！                                   ║${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    print_info "卸载操作已完成"
    print_info "感谢使用 Trojan-Go 一键部署脚本"
    echo ""

    if [ -d "$DEPLOY_DIR" ]; then
        print_warning "部署目录仍然存在: $DEPLOY_DIR"
        print_info "如需完全清理，请手动删除: rm -rf $DEPLOY_DIR"
    fi

    echo ""
}

################################################################################
# 主函数
################################################################################

main() {
    print_banner

    # 检查 root 权限
    check_root

    # 显示部署信息
    show_deployment_info

    # 最终确认
    echo ""
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║     ⚠️  最终确认                       ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo ""
    print_warning "即将卸载 Trojan-Go 服务"
    print_warning "此操作将停止所有容器并可能删除相关数据"
    echo ""

    read -p "确定要继续卸载吗？[y/N]: " final_confirm

    if [[ ! "$final_confirm" =~ ^[Yy]$ ]]; then
        print_info "卸载已取消"
        exit 0
    fi

    echo ""
    echo -e "${BLUE}开始卸载流程...${NC}"
    echo ""

    # 1. 停止并删除容器
    stop_and_remove_containers

    # 2. 删除 Docker 网络
    delete_docker_network

    # 3. 询问是否删除配置文件
    delete_config_files

    # 4. 询问是否删除 SSL 证书
    if [ -d "$DEPLOY_DIR" ]; then
        delete_ssl_certificates
    fi

    # 5. 询问是否删除 Docker 镜像
    delete_docker_images

    # 6. 询问是否卸载 Docker
    uninstall_docker

    # 7. 询问是否清理防火墙规则
    cleanup_firewall_rules

    # 8. 清理旧脚本
    cleanup_old_scripts

    # 9. 显示卸载摘要
    show_uninstall_summary
}

# 运行主函数
main "$@"
