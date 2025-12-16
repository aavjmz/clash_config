#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}开始安装Docker和Docker Compose...${NC}"

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用root用户或sudo运行此脚本${NC}"
    exit 1
fi

# 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo -e "${RED}无法检测系统类型${NC}"
    exit 1
fi

echo -e "${YELLOW}检测到系统: $OS $VERSION${NC}"

# 卸载旧版本
echo -e "${YELLOW}卸载旧版本Docker...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest 2>/dev/null
fi

# 安装Docker
echo -e "${YELLOW}开始安装Docker...${NC}"
curl -fsSL https://get.docker.com | sh

# 启动Docker
echo -e "${YELLOW}启动Docker服务...${NC}"
systemctl start docker
systemctl enable docker

# 验证安装
if docker --version &> /dev/null; then
    echo -e "${GREEN}Docker安装成功!${NC}"
    docker --version
else
    echo -e "${RED}Docker安装失败${NC}"
    exit 1
fi

# 配置Docker镜像加速
echo -e "${YELLOW}配置Docker镜像加速...${NC}"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl daemon-reload
systemctl restart docker

# 添加当前用户到docker组
if [ -n "$SUDO_USER" ]; then
    echo -e "${YELLOW}添加用户 $SUDO_USER 到docker组...${NC}"
    usermod -aG docker $SUDO_USER
    echo -e "${GREEN}请重新登录以使用户组生效${NC}"
fi

# 测试Docker
echo -e "${YELLOW}测试Docker...${NC}"
docker run --rm hello-world

# 检查Docker Compose
if docker compose version &> /dev/null; then
    echo -e "${GREEN}Docker Compose已安装!${NC}"
    docker compose version
else
    echo -e "${YELLOW}Docker Compose未找到，尝试安装...${NC}"
    apt-get install -y docker-compose-plugin 2>/dev/null || yum install -y docker-compose-plugin 2>/dev/null
fi

echo -e "${GREEN}======================${NC}"
echo -e "${GREEN}安装完成!${NC}"
echo -e "${GREEN}Docker版本: $(docker --version)${NC}"
echo -e "${GREEN}Docker Compose版本: $(docker compose version 2>/dev/null || echo '未安装')${NC}"
echo -e "${GREEN}======================${NC}"