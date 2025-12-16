# 先启动 nginx（不包含trojan-go）
docker-compose up -d nginx

# 获取证书
docker-compose run --rm certbot certonly --webroot \
    --webroot-path=/var/www/certbot \
    -d your-domain.com \
    --email dengdazhen@gmail.com \
    --agree-tos \
    --no-eff-email

# 停止临时的 nginx
docker-compose down