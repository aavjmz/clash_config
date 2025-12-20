#!/bin/bash

################################################################################
# Xray Trojan 一键部署脚本
#
# 功能：
# - 自动安装 Docker 和 Docker Compose
# - 交互式配置收集（域名、密码、伪装网站等）
# - 自动申请 Let's Encrypt SSL 证书
# - 支持多用户（多个 Trojan 密码）
# - 支持反向代理真实网站作为伪装
# - 自动生成随机 WebSocket 路径
# - 健康检查和部署验证
# - Nginx 前置处理 TLS，Xray 后端处理 Trojan 协议
#
# 使用方法：
# sudo bash deploy.sh
################################################################################

set -euo pipefail  # 启用严格模式

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="/root/xray-deploy"
DOMAIN=""
EMAIL=""
PROXY_URL=""
PROXY_HOST=""
WEBSOCKET_PATH=""
PASSWORDS=()
USE_PROXY_MODE=""

# 错误处理函数
error_handler() {
    local exit_code=$1
    local line_no=$2
    echo -e "${RED}================================${NC}"
    echo -e "${RED}错误：脚本在第 ${line_no} 行失败，退出码 ${exit_code}${NC}"
    echo -e "${RED}================================${NC}"

    # 清理临时资源
    echo -e "${YELLOW}正在清理临时资源...${NC}"
    if [ -f "$DEPLOY_DIR/docker-compose.yml" ]; then
        cd "$DEPLOY_DIR"
        docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
    fi

    echo -e "${RED}部署失败，请检查错误信息并重试${NC}"
    exit "$exit_code"
}

# 设置错误捕获
trap 'error_handler $? $LINENO' ERR

# 打印带颜色的消息
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
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}║        Xray Trojan 一键部署脚本 v2.0                     ║${NC}"
    echo -e "${GREEN}║        安全 · 隐蔽 · 易用                                ║${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

################################################################################
# 模块 1: 环境检查
################################################################################

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户或 sudo 运行此脚本"
        exit 1
    fi
    print_success "Root 权限检查通过"
}

detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        print_info "检测到系统: $OS $VERSION"
    else
        print_error "无法检测系统类型"
        exit 1
    fi
}

check_ports() {
    print_info "检查端口占用..."

    local ports=(80 443)
    local occupied=()

    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
            occupied+=("$port")
        fi
    done

    if [ ${#occupied[@]} -gt 0 ]; then
        print_warning "以下端口已被占用: ${occupied[*]}"
        read -p "是否继续？这可能导致部署失败 [y/N]: " continue
        if [[ ! "$continue" =~ ^[Yy]$ ]]; then
            print_info "部署已取消"
            exit 0
        fi
    else
        print_success "端口 80 和 443 可用"
    fi
}

check_docker() {
    if command -v docker &> /dev/null && command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        print_success "Docker 已安装"
        docker --version
        docker compose version 2>/dev/null || docker-compose --version
        return 0
    else
        print_warning "Docker 未安装"
        return 1
    fi
}

################################################################################
# 模块 2: 交互式配置收集
################################################################################

validate_domain() {
    local domain=$1

    # 域名格式验证
    if [[ ! "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 1
    fi

    # DNS 解析检查
    print_info "检查域名 DNS 解析..."
    if host "$domain" &>/dev/null; then
        local resolved_ip=$(host "$domain" | grep "has address" | head -1 | awk '{print $4}')
        print_info "域名解析到: $resolved_ip"

        # 获取本机公网 IP
        local public_ip=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
        if [ -n "$public_ip" ]; then
            print_info "本机公网 IP: $public_ip"
            if [ "$resolved_ip" != "$public_ip" ]; then
                print_warning "域名未解析到本机，请确保域名已正确解析"
            fi
        fi
    else
        print_warning "域名 DNS 解析失败，请确保域名已正确解析到本服务器"
        read -p "是否继续？[y/N]: " continue
        [[ "$continue" =~ ^[Yy]$ ]] || return 1
    fi

    return 0
}

validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_url() {
    local url=$1
    if [[ ! "$url" =~ ^https?:// ]]; then
        return 1
    fi

    # 测试 URL 可访问性
    print_info "测试伪装网站 URL 可访问性..."
    if curl -sI -m 10 "$url" | head -1 | grep -q "HTTP"; then
        print_success "URL 可访问"
        return 0
    else
        print_warning "URL 似乎无法访问"
        read -p "是否继续？[y/N]: " continue
        [[ "$continue" =~ ^[Yy]$ ]] || return 1
    fi

    return 0
}

collect_configuration() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     开始收集部署配置信息               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""

    # 1. 域名配置
    while true; do
        read -p "请输入域名（已解析到本服务器）: " DOMAIN
        if validate_domain "$DOMAIN"; then
            break
        else
            print_error "域名格式无效或验证失败，请重新输入"
        fi
    done

    # 2. 邮箱配置
    while true; do
        read -p "请输入邮箱（用于 SSL 证书通知）: " EMAIL
        if validate_email "$EMAIL"; then
            break
        else
            print_error "邮箱格式无效，请重新输入"
        fi
    done

    # 3. 伪装模式选择
    echo ""
    echo "请选择伪装方式："
    echo "1) 反向代理真实网站（推荐，隐蔽性最强）"
    echo "2) 使用本地静态页面"
    while true; do
        read -p "请选择 [1-2]: " disguise_mode
        case $disguise_mode in
            1)
                USE_PROXY_MODE="yes"
                while true; do
                    read -p "请输入要反向代理的网站 URL（如 https://www.example.com）: " PROXY_URL
                    if validate_url "$PROXY_URL"; then
                        # 提取主机名
                        PROXY_HOST=$(echo "$PROXY_URL" | sed -e 's|https\?://||' -e 's|/.*||')
                        print_info "将反向代理到: $PROXY_URL"
                        print_info "目标主机名: $PROXY_HOST"
                        break
                    else
                        print_error "URL 格式无效或无法访问，请重新输入"
                    fi
                done
                break
                ;;
            2)
                USE_PROXY_MODE="no"
                print_info "将使用本地静态页面作为伪装"
                break
                ;;
            *)
                print_error "无效选择，请输入 1 或 2"
                ;;
        esac
    done

    # 4. WebSocket 路径配置
    echo ""
    echo "WebSocket 路径配置："
    echo "1) 自动生成随机路径（推荐，安全性最高）"
    echo "2) 自定义路径"
    while true; do
        read -p "请选择 [1-2]: " ws_choice
        case $ws_choice in
            1)
                WEBSOCKET_PATH="/$(openssl rand -hex 8)"
                print_info "已生成随机 WebSocket 路径: $WEBSOCKET_PATH"
                break
                ;;
            2)
                read -p "请输入 WebSocket 路径（如 /mypath）: " WEBSOCKET_PATH
                if [[ ! "$WEBSOCKET_PATH" =~ ^/ ]]; then
                    WEBSOCKET_PATH="/$WEBSOCKET_PATH"
                fi
                print_info "WebSocket 路径: $WEBSOCKET_PATH"
                break
                ;;
            *)
                print_error "无效选择，请输入 1 或 2"
                ;;
        esac
    done

    # 5. 密码配置（多用户支持）
    echo ""
    echo "Trojan 密码配置（支持多用户）："
    echo "提示：每次输入一个密码，留空结束输入。如果不输入密码，将自动生成一个强密码。"

    PASSWORDS=()
    local user_num=1
    while true; do
        read -p "用户 $user_num 的密码（留空结束）: " -s password
        echo ""

        if [ -z "$password" ]; then
            break
        fi

        PASSWORDS+=("$password")
        print_success "已添加用户 $user_num 的密码"
        ((user_num++))
    done

    # 如果没有输入密码，自动生成一个
    if [ ${#PASSWORDS[@]} -eq 0 ]; then
        local auto_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
        PASSWORDS+=("$auto_password")
        print_info "已自动生成强密码"
    fi

    # 6. 配置确认
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║     请确认配置信息                     ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
    echo -e "域名: ${GREEN}$DOMAIN${NC}"
    echo -e "邮箱: ${GREEN}$EMAIL${NC}"
    echo -e "伪装方式: ${GREEN}$([ "$USE_PROXY_MODE" = "yes" ] && echo "反向代理 $PROXY_URL" || echo "本地静态页面")${NC}"
    echo -e "WebSocket 路径: ${GREEN}$WEBSOCKET_PATH${NC}"
    echo -e "用户数量: ${GREEN}${#PASSWORDS[@]}${NC}"
    echo ""

    read -p "确认配置并开始部署？[y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "部署已取消"
        exit 0
    fi
}

################################################################################
# 模块 3: Docker 安装
################################################################################

install_docker() {
    if check_docker; then
        return 0
    fi

    print_info "开始安装 Docker..."

    if [ -f "$SCRIPT_DIR/install-docker.sh" ]; then
        bash "$SCRIPT_DIR/install-docker.sh"
    else
        print_error "未找到 install-docker.sh 脚本"
        print_info "尝试使用官方脚本安装 Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl start docker
        systemctl enable docker
    fi

    # 验证安装
    if check_docker; then
        print_success "Docker 安装成功"
    else
        print_error "Docker 安装失败"
        exit 1
    fi
}

################################################################################
# 模块 4: 目录和文件准备
################################################################################

create_directory_structure() {
    print_info "创建目录结构..."

    mkdir -p "$DEPLOY_DIR"/{nginx/{conf.d,html,ssl},xray/config,certbot/{conf,www,logs}}

    print_success "目录结构创建完成"
}

download_geodata() {
    # Xray 内置 GeoIP 和 GeoSite 数据，无需额外下载
    print_info "Xray 内置 GeoIP/GeoSite 数据，跳过下载"
    print_success "GeoData 准备完成"
}

create_default_webpage() {
    print_info "创建默认伪装网页..."

    cat > "$DEPLOY_DIR/nginx/html/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }
        .container {
            text-align: center;
            padding: 2rem;
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
            animation: fadeIn 1s ease-in;
        }
        p {
            font-size: 1.2rem;
            opacity: 0.9;
            animation: fadeIn 1.5s ease-in;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(-20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .footer {
            position: fixed;
            bottom: 20px;
            font-size: 0.9rem;
            opacity: 0.7;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome</h1>
        <p>This is a personal website.</p>
        <p>Thanks for visiting!</p>
    </div>
    <div class="footer">
        © 2025 All Rights Reserved
    </div>
</body>
</html>
EOF

    print_success "默认网页创建完成"
}

################################################################################
# 模块 5: 配置生成
################################################################################

generate_xray_config() {
    print_info "生成 Xray 配置文件..."

    # 生成 clients 数组
    local clients_json=""
    for i in "${!PASSWORDS[@]}"; do
        if [ $i -gt 0 ]; then
            clients_json+=","
        fi
        clients_json+="{\"password\":\"${PASSWORDS[$i]}\"}"
    done

    # 生成 Xray 配置
    cat > "$DEPLOY_DIR/xray/config/config.json" <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": 8443,
            "listen": "0.0.0.0",
            "protocol": "trojan",
            "settings": {
                "clients": [
                    ${clients_json}
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "${WEBSOCKET_PATH}",
                    "host": "${DOMAIN}"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ],
    "routing": {
        "rules": [
            {
                "type": "field",
                "ip": ["geoip:private"],
                "outboundTag": "block"
            }
        ]
    }
}
EOF

    print_success "Xray 配置文件生成完成"
}

generate_nginx_temp_config() {
    print_info "生成临时 Nginx 配置（用于 SSL 证书申请）..."

    cat > "$DEPLOY_DIR/nginx/conf.d/trojan.conf" <<EOF
# 临时 HTTP 配置 - 用于 Let's Encrypt 证书申请
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

    print_success "临时 Nginx 配置生成完成"
}

generate_nginx_final_config() {
    print_info "生成最终 Nginx 配置..."

    # 根据伪装模式生成 location 块
    local proxy_location_block=""

    if [ "$USE_PROXY_MODE" = "yes" ]; then
        proxy_location_block=$(cat <<PROXY_BLOCK
        # 反向代理到真实网站
        proxy_pass ${PROXY_URL};
        proxy_ssl_server_name on;
        proxy_ssl_protocols TLSv1.2 TLSv1.3;

        # 设置代理头部
        proxy_set_header Host ${PROXY_HOST};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Accept-Encoding "";

        # 重定向处理
        proxy_redirect ~^https?://${PROXY_HOST}/(.*)$ https://${DOMAIN}/\$1;

        # 替换响应中的域名引用
        sub_filter_types text/html text/css text/javascript application/javascript;
        sub_filter_once off;
        sub_filter '${PROXY_HOST}' '${DOMAIN}';
PROXY_BLOCK
)
    else
        proxy_location_block=$(cat <<LOCAL_BLOCK
        # 本地静态页面
        root /var/www/html;
        index index.html index.htm;
        try_files \$uri \$uri/ =404;
LOCAL_BLOCK
)
    fi

    # 生成完整配置
    cat > "$DEPLOY_DIR/nginx/conf.d/trojan.conf" <<EOF
# HTTP 服务 - Let's Encrypt 验证和 HTTPS 重定向
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # Let's Encrypt ACME 验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 其他请求重定向到 HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS 服务 - 主配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    # SSL 证书配置
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${DOMAIN}/chain.pem;

    # SSL 协议和密码套件优化
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;

    # SSL 会话缓存
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # 安全头部
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # 隐藏 Nginx 版本信息
    server_tokens off;

    # Xray Trojan WebSocket 代理路径
    location ${WEBSOCKET_PATH} {
        proxy_pass http://xray:8443;
        proxy_http_version 1.1;

        # WebSocket 升级头部
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # 标准代理头部
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # 超时配置
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_connect_timeout 75s;

        # 禁用缓冲
        proxy_buffering off;
    }

    # 伪装网站根路径
    location / {
${proxy_location_block}
    }

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
    }
}
EOF

    print_success "最终 Nginx 配置生成完成"
}

generate_docker_compose() {
    print_info "生成 Docker Compose 配置..."

    cat > "$DEPLOY_DIR/docker-compose.yml" <<'COMPOSE_EOF'
services:
  # Nginx 服务
  nginx:
    image: nginx:alpine
    container_name: xray-nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/html:/var/www/html:ro
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/certbot:ro
    depends_on:
      - xray
    networks:
      - xray-net
    command: "/bin/sh -c 'while :; do sleep 6h & wait $${!}; nginx -s reload; done & nginx -g \"daemon off;\"'"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost/"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true

  # Xray 服务
  xray:
    image: teddysun/xray:latest
    container_name: xray
    restart: always
    volumes:
      - ./xray/config:/etc/xray:ro
    networks:
      - xray-net
    healthcheck:
      test: ["CMD-SHELL", "netstat -tuln | grep :8443 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true

  # Certbot 证书管理
  certbot:
    image: certbot/certbot
    container_name: xray-certbot
    restart: unless-stopped
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
      - ./certbot/logs:/var/log/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do echo \"[$$(date)] Checking for certificate renewals...\"; certbot renew --non-interactive --webroot --webroot-path=/var/www/certbot --post-hook \"echo \\\"[$$(date)] Certificate renewed successfully\\\" && touch /etc/letsencrypt/renewed.flag\" 2>&1 | tee -a /var/log/letsencrypt/renew.log || true; sleep 12h & wait $${!}; done;'"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  xray-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
COMPOSE_EOF

    print_success "Docker Compose 配置生成完成"
}

################################################################################
# 模块 6: SSL 证书申请
################################################################################

obtain_ssl_certificate() {
    print_info "开始申请 SSL 证书..."

    cd "$DEPLOY_DIR"

    # 启动临时 Nginx（仅 HTTP）
    print_info "启动临时 Nginx 服务..."
    docker compose up -d nginx
    sleep 5

    # 使用 Certbot 申请证书
    print_info "运行 Certbot 申请证书..."
    docker compose run --rm --entrypoint "certbot" certbot certonly \
        --non-interactive \
        --webroot \
        --webroot-path=/var/www/certbot \
        -d "$DOMAIN" \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --force-renewal

    # 验证证书文件
    if [ -f "$DEPLOY_DIR/certbot/conf/live/$DOMAIN/fullchain.pem" ]; then
        print_success "SSL 证书申请成功"
    else
        print_error "SSL 证书申请失败"
        print_info "请检查："
        print_info "1. 域名是否正确解析到本服务器"
        print_info "2. 防火墙是否开放 80 端口"
        print_info "3. 80 端口是否被其他程序占用"
        exit 1
    fi

    # 停止临时 Nginx
    print_info "停止临时 Nginx..."
    docker compose down
}

################################################################################
# 模块 7: 最终配置和启动
################################################################################

start_services() {
    print_info "启动所有服务..."

    cd "$DEPLOY_DIR"

    # 生成最终 Nginx 配置
    generate_nginx_final_config

    # 启动所有服务
    docker compose up -d

    # 等待服务就绪
    print_info "等待服务启动..."
    sleep 10

    print_success "所有服务已启动"
}

################################################################################
# 模块 8: 健康检查
################################################################################

health_check() {
    print_info "执行健康检查..."

    local errors=0

    # 1. 检查容器状态
    print_info "检查容器状态..."
    cd "$DEPLOY_DIR"
    if docker compose ps | grep -q "Up"; then
        print_success "容器正在运行"
    else
        print_error "容器未正常运行"
        ((errors++))
    fi

    # 2. 检查端口监听
    print_info "检查端口监听..."
    sleep 3
    if netstat -tuln 2>/dev/null | grep -q ":443 " || ss -tuln 2>/dev/null | grep -q ":443 "; then
        print_success "端口 443 正在监听"
    else
        print_warning "端口 443 未监听"
        ((errors++))
    fi

    # 3. 检查 HTTPS 访问
    print_info "检查 HTTPS 访问..."
    if curl -k -I -m 10 "https://$DOMAIN" 2>&1 | grep -q "HTTP"; then
        print_success "HTTPS 访问正常"
    else
        print_warning "HTTPS 访问异常"
        ((errors++))
    fi

    # 4. 检查证书有效性
    print_info "检查 SSL 证书..."
    if echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | grep -q "Verify return code: 0"; then
        print_success "SSL 证书验证通过"
    else
        print_warning "SSL 证书验证失败（可能需要等待 DNS 传播）"
    fi

    if [ $errors -eq 0 ]; then
        print_success "健康检查通过！"
        return 0
    else
        print_warning "健康检查发现 $errors 个问题，但服务可能仍然正常"
        return 0
    fi
}

################################################################################
# 模块 9: 输出和清理
################################################################################

save_deployment_info() {
    print_info "保存部署信息..."

    local info_file="$DEPLOY_DIR/deployment-info.txt"

    cat > "$info_file" <<INFO_EOF
====================================
Xray Trojan 部署信息
====================================
部署时间: $(date '+%Y-%m-%d %H:%M:%S')

【服务器信息】
域名: ${DOMAIN}
WebSocket 路径: ${WEBSOCKET_PATH}
伪装模式: $([ "$USE_PROXY_MODE" = "yes" ] && echo "反向代理到 $PROXY_URL" || echo "本地静态页面")

【用户密码】
$(for i in "${!PASSWORDS[@]}"; do
    echo "用户 $((i+1)): ${PASSWORDS[$i]}"
done)

【客户端配置示例 - Clash】
proxies:
  - name: "Trojan-${DOMAIN}"
    type: trojan
    server: ${DOMAIN}
    port: 443
    password: ${PASSWORDS[0]}
    udp: true
    sni: ${DOMAIN}
    alpn:
      - h2
      - http/1.1
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: ${WEBSOCKET_PATH}
      headers:
        Host: ${DOMAIN}

【客户端配置示例 - Shadowrocket】
trojan://${PASSWORDS[0]}@${DOMAIN}:443?allowInsecure=0&sni=${DOMAIN}&ws=1&wspath=${WEBSOCKET_PATH}#Trojan-${DOMAIN}

【管理命令】
查看服务状态: cd ${DEPLOY_DIR} && docker compose ps
查看 Nginx 日志: cd ${DEPLOY_DIR} && docker compose logs -f nginx
查看 Xray 日志: cd ${DEPLOY_DIR} && docker compose logs -f xray
查看 Certbot 日志: cd ${DEPLOY_DIR} && docker compose logs -f certbot
重启所有服务: cd ${DEPLOY_DIR} && docker compose restart
停止所有服务: cd ${DEPLOY_DIR} && docker compose down
启动所有服务: cd ${DEPLOY_DIR} && docker compose up -d

【证书管理】
证书路径: ${DEPLOY_DIR}/certbot/conf/live/${DOMAIN}/
证书自动续期: 已配置（每12小时检查，后台运行）
续期日志: ${DEPLOY_DIR}/certbot/logs/renew.log
查看证书状态: cd ${DEPLOY_DIR} && docker compose run --rm --entrypoint "certbot certificates" certbot
手动测试续期: cd ${DEPLOY_DIR} && docker compose run --rm --entrypoint "certbot renew --non-interactive --dry-run" certbot
手动强制续期: cd ${DEPLOY_DIR} && docker compose run --rm --entrypoint "certbot renew --non-interactive --force-renewal" certbot

【配置文件位置】
Xray: ${DEPLOY_DIR}/xray/config/config.json
Nginx: ${DEPLOY_DIR}/nginx/conf.d/trojan.conf
Docker Compose: ${DEPLOY_DIR}/docker-compose.yml

====================================
INFO_EOF

    chmod 600 "$info_file"

    print_success "部署信息已保存到: $info_file"
}

display_deployment_info() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}║              部署成功！                                   ║${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BLUE}【服务器信息】${NC}"
    echo -e "域名: ${GREEN}$DOMAIN${NC}"
    echo -e "WebSocket 路径: ${GREEN}$WEBSOCKET_PATH${NC}"
    echo -e "伪装模式: ${GREEN}$([ "$USE_PROXY_MODE" = "yes" ] && echo "反向代理到 $PROXY_URL" || echo "本地静态页面")${NC}"
    echo ""

    echo -e "${BLUE}【用户密码】${NC}"
    for i in "${!PASSWORDS[@]}"; do
        echo -e "用户 $((i+1)): ${GREEN}${PASSWORDS[$i]}${NC}"
    done
    echo ""

    echo -e "${BLUE}【客户端配置示例 - Clash】${NC}"
    cat <<CLASH_EOF
proxies:
  - name: "Trojan-${DOMAIN}"
    type: trojan
    server: ${DOMAIN}
    port: 443
    password: ${PASSWORDS[0]}
    udp: true
    sni: ${DOMAIN}
    alpn:
      - h2
      - http/1.1
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: ${WEBSOCKET_PATH}
      headers:
        Host: ${DOMAIN}
CLASH_EOF
    echo ""

    echo -e "${YELLOW}提示：完整的部署信息已保存到: $DEPLOY_DIR/deployment-info.txt${NC}"
    echo ""

    echo -e "${BLUE}【常用管理命令】${NC}"
    echo -e "查看服务状态: ${GREEN}cd $DEPLOY_DIR && docker compose ps${NC}"
    echo -e "查看 Xray 日志: ${GREEN}cd $DEPLOY_DIR && docker compose logs -f xray${NC}"
    echo -e "重启服务: ${GREEN}cd $DEPLOY_DIR && docker compose restart${NC}"
    echo ""
}

cleanup_old_scripts() {
    print_info "清理旧的分步脚本..."

    local old_scripts=(
        "$SCRIPT_DIR/step1.sh"
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

    for script in "${old_scripts[@]}"; do
        if [ -f "$script" ]; then
            rm -f "$script"
        fi
    done

    print_success "旧脚本已清理"
}

################################################################################
# 主函数
################################################################################

main() {
    print_banner

    # 阶段 1: 环境检查
    print_info "========== 阶段 1/9: 环境检查 =========="
    check_root
    detect_system
    check_ports

    # 阶段 2: 配置收集
    print_info "========== 阶段 2/9: 配置收集 =========="
    collect_configuration

    # 阶段 3: Docker 安装
    print_info "========== 阶段 3/9: Docker 环境准备 =========="
    install_docker

    # 阶段 4: 目录和文件准备
    print_info "========== 阶段 4/9: 目录和文件准备 =========="
    create_directory_structure
    download_geodata
    create_default_webpage

    # 阶段 5: 配置生成
    print_info "========== 阶段 5/9: 配置文件生成 =========="
    generate_xray_config
    generate_nginx_temp_config
    generate_docker_compose

    # 阶段 6: SSL 证书申请
    print_info "========== 阶段 6/9: SSL 证书申请 =========="
    obtain_ssl_certificate

    # 阶段 7: 启动服务
    print_info "========== 阶段 7/9: 启动服务 =========="
    start_services

    # 阶段 8: 健康检查
    print_info "========== 阶段 8/9: 健康检查 =========="
    health_check

    # 阶段 9: 保存信息和清理
    print_info "========== 阶段 9/9: 保存部署信息 =========="
    save_deployment_info
    display_deployment_info
    cleanup_old_scripts

    print_success "========== 部署完成！ =========="
}

# 运行主函数
main "$@"
