const { logger } = require('../utils/logger');

/**
 * 将错误转换为OpenAI风格的错误响应
 */
const formatError = (status, message, type = 'server_error', code = null) => {
  return {
    error: {
      message,
      type,
      code: code || String(status),
      param: null,
      status
    }
  };
};

/**
 * 错误处理中间件
 */
const errorHandler = (err, req, res, next) => {
  // 记录错误
  logger.error(`Error: ${err.message}`, { 
    stack: err.stack,
    url: req.originalUrl,
    method: req.method
  });
  
  // 默认错误响应
  let statusCode = err.statusCode || 500;
  let errorType = 'server_error';
  let errorCode = null;
  
  // 根据错误类型定制响应
  if (err.name === 'ValidationError') {
    statusCode = 400;
    errorType = 'invalid_request_error';
  } else if (err.name === 'AuthError') {
    statusCode = 401;
    errorType = 'authentication_error';
  } else if (err.name === 'ForbiddenError') {
    statusCode = 403;
    errorType = 'access_forbidden';
  } else if (err.name === 'RateLimitError') {
    statusCode = 429;
    errorType = 'rate_limit_exceeded';
  }
  
  // 构建并发送标准化的错误响应
  const errorResponse = formatError(statusCode, err.message, errorType, errorCode);
  res.status(statusCode).json(errorResponse);
};

module.exports = { errorHandler, formatError }; 