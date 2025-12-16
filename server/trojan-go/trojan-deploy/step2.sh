cat > docker-compose.yml << 'EOF'
services:
  # Nginx 服务
  nginx:
    image: nginx:alpine
    container_name: trojan-nginx
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
      - trojan-go
    networks:
      - trojan-net
    command: "/bin/sh -c 'while :; do sleep 6h & wait $${!}; nginx -s reload; done & nginx -g \"daemon off;\"'"

  # Trojan-Go 服务
  trojan-go:
    image: p4gefau1t/trojan-go:latest
    container_name: trojan-go
    restart: always
    volumes:
      - ./trojan-go/config:/etc/trojan-go:ro
      - ./trojan-go/logs:/var/log/trojan-go
      - ./certbot/conf:/etc/letsencrypt:ro
    networks:
      - trojan-net
    command: /usr/bin/trojan-go -config /etc/trojan-go/config.json

  # Certbot 证书管理（可选，用于自动续期）
  certbot:
    image: certbot/certbot
    container_name: trojan-certbot
    restart: unless-stopped
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"

networks:
  trojan-net:
    driver: bridge
EOF