# 恢复 nginx/conf.d/trojan.conf 的完整配置（第五步step5.sh的内容），然后：
# 生成强密码
openssl rand -base64 32

# 修改配置文件中的密码和域名
nano trojan-go/config/config.json
nano nginx/conf.d/trojan.conf

# 启动所有服务
docker-compose up -d

# 查看日志
docker-compose logs -f