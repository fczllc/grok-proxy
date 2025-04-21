const { logger } = require('../utils/logger');
const { formatError } = require('../middleware/errorHandler');
const { transformOpenAIToGrok, transformGrokToOpenAI, transformStreamedGrokToOpenAI } = require('../utils/transformers');
const { extractApiKey, validateRequest } = require('../utils/requestHelpers');

/**
 * 处理聊天完成请求的控制器函数
 */
const handleChatCompletions = async (req, res, next) => {
  try {
    // 从请求中提取API密钥
    const apiKey = extractApiKey(req);
    if (!apiKey) {
      return res.status(401).json(
        formatError(401, '未提供有效的API密钥', 'authentication_error')
      );
    }
    
    // 验证请求
    const validationResult = validateRequest(req.body);
    if (!validationResult.valid) {
      return res.status(400).json(
        formatError(400, validationResult.message, 'invalid_request_error')
      );
    }
    
    // 转换请求 (OpenAI -> Grok)
    const grokRequest = transformOpenAIToGrok(req.body);
    
    // 判断是否为流式请求
    const isStreamRequest = req.body.stream === true;
    
    // 准备请求选项
    const requestOptions = {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey
      },
      body: JSON.stringify(grokRequest)
    };
    
    // 调用Grok API
    logger.info(`调用Grok API: ${isStreamRequest ? 'stream' : 'non-stream'} 请求`);
    const grokResponse = await fetch('https://api.x.ai/v1/chat/completions', requestOptions);
    
    // 处理错误响应
    if (!grokResponse.ok) {
      const errorData = await grokResponse.json();
      logger.error(`Grok API错误: ${grokResponse.status} - ${JSON.stringify(errorData)}`);
      
      // 转换并返回错误
      return res.status(grokResponse.status).json(
        formatError(
          grokResponse.status,
          errorData.error?.message || '调用Grok API时发生错误',
          errorData.error?.type || 'api_error',
          errorData.error?.code
        )
      );
    }
    
    // 处理流式响应
    if (isStreamRequest) {
      // 设置响应头
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      
      // 处理SSE流
      const reader = grokResponse.body.getReader();
      const decoder = new TextDecoder('utf-8');
      let buffer = '';
      
      // 处理每个数据块
      async function processStream() {
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) {
              // 发送最后的数据
              if (buffer.trim()) {
                const chunks = transformStreamedGrokToOpenAI(buffer);
                for (const chunk of chunks) {
                  res.write(`data: ${JSON.stringify(chunk)}\n\n`);
                }
              }
              // 结束流
              res.write('data: [DONE]\n\n');
              res.end();
              break;
            }
            
            // 解码并处理数据
            const chunk = decoder.decode(value, { stream: true });
            buffer += chunk;
            
            // 处理完整的行
            const lines = buffer.split('\n');
            buffer = lines.pop() || ''; // 保留最后一个不完整的行
            
            // 处理每一行
            for (const line of lines) {
              if (line.trim() && line.startsWith('data: ')) {
                const chunks = transformStreamedGrokToOpenAI(line);
                for (const chunk of chunks) {
                  res.write(`data: ${JSON.stringify(chunk)}\n\n`);
                }
              }
            }
          }
        } catch (err) {
          logger.error(`处理流时出错: ${err.message}`);
          res.end();
        }
      }
      
      processStream();
    } else {
      // 处理非流式响应
      const data = await grokResponse.json();
      
      // 转换响应 (Grok -> OpenAI)
      const openAIResponse = transformGrokToOpenAI(data);
      
      // 发送响应
      res.json(openAIResponse);
    }
  } catch (err) {
    next(err);
  }
};

module.exports = { handleChatCompletions }; 