const winston = require('winston');
const path = require('path');

// 定义日志格式
const logFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  winston.format.splat(),
  winston.format.printf(({ level, message, timestamp, stack }) => {
    // API密钥敏感信息处理（脱敏）
    let sanitizedMessage = message;
    if (typeof message === 'string') {
      // 替换Bearer token
      sanitizedMessage = sanitizedMessage.replace(
        /(Bearer\s+)[a-zA-Z0-9_.-]{5}.*/g, 
        '$1*****'
      );
      // 替换x-api-key
      sanitizedMessage = sanitizedMessage.replace(
        /(x-api-key|x-proxy-key|X-API-Key|X-Proxy-Key):\s*[a-zA-Z0-9_.-]{5}.*/g, 
        '$1: *****'
      );
    }
    
    return `${timestamp} ${level}: ${sanitizedMessage}${stack ? '\n' + stack : ''}`;
  })
);

// 创建logger实例
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: logFormat,
  transports: [
    // 控制台输出
    new winston.transports.Console(),
    // 文件输出
    new winston.transports.File({ 
      filename: path.join(__dirname, '../../logs/error.log'), 
      level: 'error' 
    }),
    new winston.transports.File({ 
      filename: path.join(__dirname, '../../logs/combined.log') 
    })
  ]
});

module.exports = { logger }; 