/**
 * 代理密钥验证中间件
 * 用于验证请求中的X-Proxy-Key是否有效
 */

class ForbiddenError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ForbiddenError';
    this.message = message || '访问被拒绝: 无效的代理密钥';
  }
}

const proxyKeyAuth = (req, res, next) => {
  // 从环境变量获取有效的代理密钥(多个密钥用逗号分隔)
  const validProxyKeys = (process.env.VALID_PROXY_KEYS || '').split(',').filter(key => key.trim());
  
  // 如果未配置任何有效密钥，则跳过验证
  if (validProxyKeys.length === 0) {
    return next();
  }
  
  // 从请求头获取代理密钥
  const providedKey = req.headers['x-proxy-key'];
  
  // 验证代理密钥
  if (!providedKey || !validProxyKeys.includes(providedKey)) {
    return next(new ForbiddenError());
  }
  
  // 验证通过，继续处理请求
  next();
};

module.exports = { proxyKeyAuth, ForbiddenError }; 