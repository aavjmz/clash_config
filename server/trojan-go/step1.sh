#!/bin/bash#
mkdir -p trojan-deploy
cd trojan-deploy
# 创建目录结构
mkdir -p nginx/conf.d
mkdir -p nginx/html
mkdir -p nginx/ssl
mkdir -p trojan-go/config
mkdir -p trojan-go/logs
mkdir -p certbot/conf
mkdir -p certbot/www