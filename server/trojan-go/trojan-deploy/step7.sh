# 临时注释掉 nginx/conf.d/trojan.conf 中的 SSL 相关配置
cat nginx/conf.d/trojan.conf << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name your-domain.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF