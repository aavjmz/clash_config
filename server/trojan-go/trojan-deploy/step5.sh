# Prompt user for input
read -p "Enter proxy_pass url(https): " PROXY_URL
read -p "Enter pseudo domain(SNI/Websocket): " DOMAIN
cat nginx/conf.d/trojan.conf << 'EOF'
# HTTP 重定向
server {
    listen 80;
    listen [::]:80;
    server_name "${DOMAIN}";

    # Let's Encrypt 验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 其他请求重定向到 HTTPS
    location / {
        # return 301 https://$server_name$request_uri;
        root /var/www/html;
        proxy_ssl_server_name on;
        proxy_pass $PROXY_URL;
        proxy_set_header Accept-Encoding '';
        sub_filter "$PROXY_URL" "$DOMAIN";
        sub_filter_once off;
    }
}

# HTTPS 配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name "${DOMAIN}";

    # SSL 证书
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    # SSL 优化
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 安全头部
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;

    # Trojan-Go WebSocket 代理
    location /ws-a8f3d2c1 {
        proxy_pass http://trojan-go:8443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # 伪装网站
    location / {
        root /var/www/html;
        index index.html;
        try_files $uri $uri/ =404;
    }

    location ~ /\. {
        deny all;
    }
}
EOF