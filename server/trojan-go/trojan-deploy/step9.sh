# 检查容器状态
docker-compose ps

# 查看 Nginx 日志
docker-compose logs nginx

# 查看 Trojan-Go 日志
docker-compose logs trojan-go

# 测试网站
curl -I https://your-domain.com

# 查看端口监听
sudo netstat -tlnp | grep -E '80|443'