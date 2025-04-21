const app = require('./app');
const { logger } = require('./utils/logger');

// 从环境变量获取端口，默认为3000
const PORT = process.env.PORT || 3000;

// 启动服务器
app.listen(PORT, () => {
  logger.info(`Grok API代理服务运行在端口 ${PORT}`);
  logger.info('环境: ' + (process.env.NODE_ENV || 'development'));
}); 