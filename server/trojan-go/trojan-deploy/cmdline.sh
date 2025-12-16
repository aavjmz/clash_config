# 启动服务
docker compose up -d

# 停止服务
docker compose down

# 重启服务
docker compose restart

# 查看日志
docker compose logs -f trojan-go
docker compose logs -f nginx

# 更新配置后重载
docker compose restart trojan-go
docker compose restart nginx

# 手动续期证书
docker compose run --rm certbot renew

# 清理并重建
docker compose down
docker compose up -d --force-recreate