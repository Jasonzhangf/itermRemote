# ItermRemote 服务器模块

本目录包含服务器端所有组件（API、WS、数据库迁移与部署脚本）。本文档仅记录**非敏感**配置与运维流程。

## 功能概览（已实现）

- 账号系统：注册/登录/JWT
- 设备状态上报：设备在线/离线 + IP 列表
- 设备列表查询：获取设备在线状态 + IP
- ICE 服务器列表下发
- 错误日志与 ICE 遥测上报

## 服务端点（非敏感）

- `POST /api/v1/register`
- `POST /api/v1/login`
- `POST /api/v1/token/refresh`
- `POST /api/v1/device/status`
- `GET  /api/v1/devices`
- `GET  /api/v1/ice/servers`
- `POST /api/v1/logs/error`
- `POST /api/v1/telemetry/ice`
- `POST /api/v1/password/change`

## 交叉编译（服务器为 x86_64）

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o api-server .
```

## 部署流程（简述）

```bash
# 1) 本地编译 api-server (x86_64)
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o api-server .

# 2) 上传到服务器 /opt/itermremote/api
scp api-server root@<server>:/opt/itermremote/api/

# 3) 重新构建镜像并启动
cd /opt/itermremote
Dockerfile 使用 api-server 二进制

docker-compose stop api-server
Docker-compose up -d --build --no-deps api-server
```

## 安全要求

- 禁止在任何 README 或文档中写入密码、密钥、JWT 或邮箱
- 服务器账号、访问凭据必须仅保存在安全渠道
