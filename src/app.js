const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const { logger } = require('./utils/logger');
const { errorHandler } = require('./middleware/errorHandler');
const { proxyKeyAuth } = require('./middleware/proxyKeyAuth');
const routes = require('./routes');

// 加载环境变量
require('dotenv').config();

const app = express();

// 基本中间件
app.use(cors());
app.use(express.json());
app.use(morgan('combined', { stream: { write: message => logger.info(message.trim()) } }));

// 代理密钥验证中间件（如果启用）
if (process.env.ENABLE_PROXY_KEY_AUTH === 'true') {
  app.use(proxyKeyAuth);
}

// 设置路由
app.use('/v1', routes);

// 错误处理中间件
app.use(errorHandler);

module.exports = app; 