# Prompt user for input
read -p "Enter trojan go password: " PASSWORD
read -p "Enter pseudo domain(SNI/Websocket): " DOMAIN
read -p "Enter WebSocket path: " WEBSOCKET_PATH

cat > trojan-go/config/config.json << 'EOF'
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 8443,
    "remote_addr": "trojan-nginx",
    "remote_port": 80,
    "password": [
        "${PASSWORD}"
    ],
    "log_level": 2,
    "log_file": "/var/log/trojan-go/trojan.log",
    # 已在nginx代理中配置SSL, 无需在trojan-go中再配置SSL
    # "ssl": {
    #     "cert": "/etc/letsencrypt/live/your-domain.com/fullchain.pem",
    #     "key": "/etc/letsencrypt/live/your-domain.com/privkey.pem",
    #     "sni": "${DOMAIN}",
    #     "alpn": ["http/1.1"],
    #     "fallback_addr": "trojan-nginx",
    #     "fallback_port": 80,
    #     "fingerprint": "firefox",
    #     "session_ticket": true,
    #     "reuse_session": true
    # },
    "ssl": {
        "enabled": false
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "fast_open": false
    },
    "mux": {
        "enabled": true,
        "concurrency": 8,
        "idle_timeout": 60
    },
    "websocket": {
        "enabled": true,
        "path": "${WEBSOCKET_PATH}",
        "host": "${DOMAIN}"
    },
    "router": {
        "enabled": true,
        "block": ["geoip:private"],
        "geoip": "/etc/trojan-go/geoip.dat",
        "geosite": "/etc/trojan-go/geosite.dat"
    }
}
EOF