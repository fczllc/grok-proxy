# Grok API 中转服务

这是一个部署在用户自有VPS上的HTTP服务，通过Nginx作为反向代理对外提供服务。该服务作为x.ai Grok API的中转代理，旨在接收遵循OpenAI API格式的请求（例如来自Cherry Studio等客户端），将其转换为Grok API所需的格式，调用Grok API，并将Grok的响应转换回OpenAI格式返回给客户端。

## 功能特点

- 提供兼容OpenAI格式的`/v1/chat/completions`端点
- 支持API密钥验证和代理密钥访问控制
- 支持流式和非流式响应
- 自动映射常见的OpenAI模型名称到Grok模型
- 全面的错误处理和日志记录
- 支持CORS

## 系统要求

- Node.js (v18或更高版本)
- 能够访问Grok API的网络环境
- (可选) Nginx作为反向代理

## 安装步骤

1. 克隆项目到本地:

```bash
git clone <repository_url> grok-proxy
cd grok-proxy
```

2. 安装依赖:

```bash
npm install
```

3. 配置环境变量:

```bash
cp .env.example .env
# 编辑.env文件，设置必要的环境变量
```

4. 运行服务:

```bash
# 开发环境(带有自动重启)
npm run dev

# 生产环境
npm start
```

## 环境变量说明

- `PORT`: 服务监听端口 (默认: 3000)
- `NODE_ENV`: 运行环境 (development/production)
- `LOG_LEVEL`: 日志级别 (error/warn/info/debug)
- `ENABLE_PROXY_KEY_AUTH`: 是否启用代理密钥验证 (true/false)
- `VALID_PROXY_KEYS`: 有效的代理密钥，多个密钥用逗号分隔
- `TARGET_GROK_MODEL`: 默认使用的Grok模型 (默认: grok-3-latest)

## 使用方法

服务启动后，可以向`http://your-server-address:port/v1/chat/completions`发送标准的OpenAI格式请求。

### 请求示例

```bash
curl -X POST http://localhost:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_XAI_API_KEY" \
  -H "X-Proxy-Key: YOUR_PROXY_KEY" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {"role": "system", "content": "你是一个有用的助手。"},
      {"role": "user", "content": "你好，请介绍一下自己。"}
    ],
    "stream": false
  }'
```

## Nginx 配置示例

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    # 重定向HTTP到HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name your-domain.com;
    
    # SSL配置
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    
    # 速率限制
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    
    location /v1/chat/completions {
        limit_req zone=api_limit burst=20 nodelay;
        
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 流式响应需要的设置
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 300s;
    }
}
```

## 开发与贡献

欢迎提出问题或Pull Requests。在提交代码前，请确保遵循项目的代码风格和测试要求。 