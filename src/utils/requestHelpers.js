const { logger } = require('./logger');

/**
 * 从请求头中提取API密钥
 * 支持Authorization: Bearer <key>和x-api-key两种格式
 */
const extractApiKey = (req) => {
  const authHeader = req.headers.authorization;
  const xApiKey = req.headers['x-api-key'];
  
  if (authHeader && authHeader.startsWith('Bearer ')) {
    return authHeader.substring(7).trim();
  } else if (xApiKey) {
    return xApiKey.trim();
  }
  
  return null;
};

/**
 * 验证请求的基本结构
 */
const validateRequest = (body) => {
  // 必须有messages字段
  if (!body.messages || !Array.isArray(body.messages) || body.messages.length === 0) {
    return {
      valid: false,
      message: '请求必须包含至少一条消息的messages数组'
    };
  }
  
  // 检查消息格式
  for (const message of body.messages) {
    if (!message.role || !message.content) {
      return {
        valid: false,
        message: '每条消息必须包含role和content字段'
      };
    }
    
    // 验证角色类型
    if (!['user', 'assistant', 'system'].includes(message.role)) {
      return {
        valid: false,
        message: `不支持的消息角色: ${message.role}. 仅支持 'user', 'assistant', 'system'.`
      };
    }
  }
  
  // 验证stream参数类型(如果存在)
  if (body.stream !== undefined && typeof body.stream !== 'boolean') {
    return {
      valid: false,
      message: 'stream参数必须是布尔值'
    };
  }
  
  return { valid: true };
};

module.exports = { extractApiKey, validateRequest }; 