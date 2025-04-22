# Grok API 中转服务部署指南

## 一键部署脚本（推荐方式）

为了简化部署过程，我们提供了一键部署脚本，该脚本会自动完成所有安装步骤，包括依赖安装、代码克隆、配置设置、服务启动和Nginx设置。

### 如何使用一键部署脚本

在Ubuntu 20.04/22.04或Debian 10/11系统上，只需运行以下命令：

```bash
# 使用curl
curl -sSL https://jcza.fczllc.top:8418/fczllc/grok-proxy/src/branch/main/deploy_grok_proxy.sh | sudo bash

# 或使用wget
wget -O - -q https://jcza.fczllc.top:8418/fczllc/grok-proxy/src/branch/main/deploy_grok_proxy.sh | sudo bash
```

### 部署过程中的交互

脚本执行过程中会提示您输入以下信息：

1. **安装目录**：存放代码的位置（默认: /var/www/grok-proxy）
2. **服务端口**：Node.js应用监听的端口（默认: 3000）
3. **代理密钥验证**：是否启用X-Proxy-Key验证（推荐启用）
4. **代理密钥**：如果启用验证，设置一个或多个逗号分隔的密钥
5. **Grok模型**：默认使用的Grok模型（通常为grok-3-latest）
6. **域名**：（可选）如果您有域名，脚本将自动配置Nginx和SSL

### 服务管理菜单

脚本安装完成后，会在系统中安装一个管理工具，您可以随时通过以下命令访问管理菜单：

```bash
sudo grok-proxy-manager menu
```

管理菜单提供以下功能：

1. **启动服务**：启动或重启Grok API代理服务
2. **停止服务**：停止正在运行的服务
3. **重启服务**：重新启动服务（配置更改后使用）
4. **查看服务状态**：显示PM2和Nginx的运行状态
5. **修改配置参数**：更改域名、端口、代理密钥等设置
6. **测试验证**：运行curl测试验证服务是否正常工作
7. **卸载服务**：完全移除服务及其配置

### 配置修改子菜单

在管理菜单选择"修改配置参数"后，您可以访问配置子菜单：

1. **修改域名**：更改或设置服务域名
2. **修改端口**：更改Node.js应用监听的端口
3. **修改代理密钥**：更新代理密钥或启用/禁用代理密钥验证
4. **修改Let's Encrypt Email**：更新用于SSL证书的邮箱地址

### 卸载服务

如需完全卸载服务，可以通过管理菜单选择"卸载服务"，或手动运行以下命令：

```bash
sudo grok-proxy-manager menu
# 然后选择选项 7
```

卸载过程会：
- 停止并删除PM2进程
- 移除Nginx配置
- 可选地删除SSL证书
- 删除安装的文件和配置

### 注意事项

1. **系统要求**：脚本设计用于Ubuntu和Debian系统，在其他系统上可能需要手动安装
2. **权限**：脚本需要sudo权限才能安装软件包和配置系统服务
3. **服务访问**：
   - 如果配置了域名，可通过 https://您的域名 访问服务
   - 如果未配置域名，可通过 http://服务器IP:端口 访问服务
4. **安全建议**：
   - 强烈建议启用代理密钥验证
   - 确保设置安全的代理密钥
   - 建议设置Nginx速率限制（脚本已自动配置）

本文档接下来将详细介绍手动部署的步骤，适用于需要更精细控制安装过程或脚本不适用的系统。

## 手动部署指南

本文档提供在Linux VPS上部署Grok API中转服务的详细步骤。

### 准备工作

#### 系统要求

- 一台可以访问互联网，特别是可以访问api.x.ai域名的VPS
- 操作系统: Ubuntu 20.04/22.04 LTS, Debian 10/11, 或CentOS 7/8 (以下步骤基于Ubuntu 22.04)
- 至少512MB RAM (推荐1GB或更多)
- 你的域名（可选，但推荐）

#### 先决条件软件

- Node.js (v18 或更高版本)
- Nginx
- Git
- PM2
- Certbot (用于HTTPS证书)

### 安装步骤

#### 1. 更新系统并安装基本工具

```bash
# 更新系统
sudo apt update
sudo apt upgrade -y

# 安装基本工具
sudo apt install -y curl wget git ufw
```

#### 2. 安装Node.js

```bash
# 安装Node.js 18.x
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# 验证安装
node -v
npm -v
```

#### 3. 安装PM2

```bash
# 全局安装PM2
sudo npm install -g pm2

# 设置PM2开机自启
pm2 startup
# 按照命令输出执行相应命令
```

#### 4. 安装Nginx

```bash
# 安装Nginx
sudo apt install -y nginx

# 启动Nginx并设置为开机自启
sudo systemctl enable nginx
sudo systemctl start nginx

# 验证Nginx是否正常运行
sudo systemctl status nginx
```

#### 5. 配置防火墙

```bash
# 允许SSH、HTTP和HTTPS流量
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https

# 启用防火墙
sudo ufw enable

# 验证防火墙状态
sudo ufw status
```

#### 6. 获取和设置项目

```bash
# 创建应用目录
mkdir -p /var/www
cd /var/www

# 克隆代码仓库
sudo git clone <repository_url> grok-proxy
cd grok-proxy

# 安装依赖
sudo npm install

# 创建日志目录
sudo mkdir -p logs
sudo chmod 755 logs

# 配置环境变量
sudo cp .env.example .env
sudo nano .env  # 或使用你喜欢的编辑器
```

编辑.env文件，设置以下值:

```
PORT=3000
NODE_ENV=production
LOG_LEVEL=info
ENABLE_PROXY_KEY_AUTH=true
VALID_PROXY_KEYS=你的密钥1,你的密钥2
TARGET_GROK_MODEL=grok-3-latest
```

#### 7. 使用PM2启动应用

```bash
# 启动应用
pm2 start ecosystem.config.js

# 保存PM2配置，以便开机自启
pm2 save
```

#### 8. 配置Nginx

```bash
# 创建Nginx配置文件
sudo cp nginx.conf.example /etc/nginx/sites-available/grok-proxy.conf
sudo nano /etc/nginx/sites-available/grok-proxy.conf
```

编辑Nginx配置文件，将`your-domain.com`修改为你的域名，并调整其他设置。

```bash
# 启用站点配置
sudo ln -s /etc/nginx/sites-available/grok-proxy.conf /etc/nginx/sites-enabled/

# 测试Nginx配置
sudo nginx -t

# 重启Nginx以应用配置
sudo systemctl restart nginx
```

#### 9. 设置HTTPS (如果有域名)

```bash
# 安装Certbot
sudo apt install -y certbot python3-certbot-nginx

# 获取SSL证书
sudo certbot --nginx -d your-domain.com

# 按照提示完成设置
```

Certbot会自动修改Nginx配置来使用SSL证书。

#### 10. 验证部署

使用以下测试请求验证服务是否正常工作:

```bash
curl -X POST https://your-domain.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_XAI_API_KEY" \
  -H "X-Proxy-Key: YOUR_PROXY_KEY" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {"role": "user", "content": "Hello world!"}
    ]
  }'
```

### 维护与监控

#### 日志查看

```bash
# 查看PM2日志
pm2 logs grok-proxy

# 查看Nginx访问日志
sudo tail -f /var/log/nginx/access.log

# 查看Nginx错误日志
sudo tail -f /var/log/nginx/error.log

# 查看应用日志
tail -f /var/www/grok-proxy/logs/combined.log
tail -f /var/www/grok-proxy/logs/error.log
```

#### 重启服务

```bash
# 重启Node.js应用
pm2 restart grok-proxy

# 重启Nginx
sudo systemctl restart nginx
```

#### 更新应用

```bash
cd /var/www/grok-proxy
sudo git pull
sudo npm install
pm2 restart grok-proxy
```

### 故障排除

#### 1. 服务无法启动

- 检查日志: `pm2 logs grok-proxy`
- 确认环境变量配置正确: `cat .env`
- 验证Node.js版本: `node -v`

#### 2. 无法访问API

- 检查Nginx配置: `sudo nginx -t`
- 验证Nginx运行状态: `sudo systemctl status nginx`
- 查看Nginx错误日志: `sudo tail -f /var/log/nginx/error.log`
- 确认防火墙设置: `sudo ufw status`

#### 3. SSL/HTTPS问题

- 验证证书状态: `sudo certbot certificates`
- 更新证书: `sudo certbot renew`
- 检查Nginx SSL配置

### 安全要求

1. 始终保持操作系统和软件包更新
2. 使用强密码和SSH密钥对进行SSH访问
3. 禁用root密码登录
4. 定期审查日志文件，查找可疑活动
5. 在Nginx层面实施速率限制
6. 定期更换代理密钥

### 资源监控

使用以下命令监控服务器资源使用情况:

```bash
# 安装监控工具
sudo apt install -y htop

# 使用htop查看系统资源使用情况
htop
``` 