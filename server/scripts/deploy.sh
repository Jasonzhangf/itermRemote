#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== ItermRemote Server 一键部署 ==="
echo "$(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装"
    echo "请先安装 Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose 未安装"
    echo "请先安装 Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "✓ Docker 版本: $(docker --version)"
echo "✓ Docker Compose 版本: $(docker-compose --version)"
echo ""

# 生成环境配置
ENV_FILE="$PROJECT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "生成环境配置文件..."
    cat > "$ENV_FILE" << ENVEOF
# 数据库配置
DB_USER=itermremote
DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')

# Redis 配置
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')

# JWT 密钥（生产环境请修改）
JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')

# 环境
ENVIRONMENT=production
LOG_LEVEL=info
ENVEOF
    echo "✓ 环境配置已生成: $ENV_FILE"
else
    echo "✓ 环境配置已存在: $ENV_FILE"
fi

echo ""
echo "启动服务..."
cd "$PROJECT_DIR"
docker-compose down 2>/dev/null || true
docker-compose up --build -d

echo ""
echo "等待服务就绪..."
sleep 5

# 健康检查
echo ""
echo "=== 健康检查 ==="
API_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health 2>/dev/null || echo "000")
WS_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/ws/health 2>/dev/null || echo "000")

if [ "$API_HEALTH" = "200" ]; then
    echo "✓ API Server: http://localhost:8080"
else
    echo "⚠ API Server 未就绪 (HTTP $API_HEALTH)"
fi

if [ "$WS_HEALTH" = "200" ]; then
    echo "✓ WebSocket Server: ws://localhost:8081/ws/connect"
else
    echo "⚠ WebSocket Server 未就绪 (HTTP $WS_HEALTH)"
fi

echo ""
echo "=== 部署完成 ==="
echo ""
echo "API 接口:"
echo "  - 健康检查: GET http://localhost:8080/api/health"
echo "  - 注册: POST http://localhost:8080/api/v1/register"
echo "  - 登录: POST http://localhost:8080/api/v1/login"
echo ""
echo "WebSocket:"
echo "  - 连接: ws://localhost:8081/ws/connect?token=<jwt_token>"
echo ""
echo "日志查看:"
echo "  docker-compose logs -f api-server"
echo "  docker-compose logs -f ws-server"
echo ""
echo "停止服务: docker-compose down"
