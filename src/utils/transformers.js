const { logger } = require('./logger');

/**
 * 将OpenAI格式的请求转换为Grok格式
 */
const transformOpenAIToGrok = (openAIRequest) => {
  const grokRequest = {
    messages: openAIRequest.messages, // 消息格式兼容，直接传递
    model: mapModelName(openAIRequest.model) // 模型名称映射
  };
  
  // 处理和映射其他参数
  if (openAIRequest.max_tokens) grokRequest.max_tokens = openAIRequest.max_tokens;
  if (openAIRequest.temperature !== undefined) grokRequest.temperature = openAIRequest.temperature;
  if (openAIRequest.top_p !== undefined) grokRequest.top_p = openAIRequest.top_p;
  if (openAIRequest.stream !== undefined) grokRequest.stream = openAIRequest.stream;
  if (openAIRequest.frequency_penalty !== undefined) grokRequest.frequency_penalty = openAIRequest.frequency_penalty;
  if (openAIRequest.presence_penalty !== undefined) grokRequest.presence_penalty = openAIRequest.presence_penalty;
  
  // 处理停止序列
  if (openAIRequest.stop) {
    grokRequest.stop_sequences = Array.isArray(openAIRequest.stop) 
      ? openAIRequest.stop 
      : [openAIRequest.stop];
  }
  
  return grokRequest;
};

/**
 * 将Grok格式的响应转换为OpenAI格式(非流式)
 */
const transformGrokToOpenAI = (grokResponse) => {
  // 创建基本的OpenAI响应结构
  const openAIResponse = {
    id: grokResponse.id || `chatcmpl-${Date.now().toString(36)}`,
    object: 'chat.completion',
    created: grokResponse.created || Math.floor(Date.now() / 1000),
    model: grokResponse.model || 'grok-3-latest',
    choices: [],
    usage: grokResponse.usage || {
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0
    }
  };
  
  // 转换choices
  if (grokResponse.choices && Array.isArray(grokResponse.choices)) {
    openAIResponse.choices = grokResponse.choices.map(choice => {
      return {
        index: choice.index || 0,
        message: {
          role: 'assistant',
          content: choice.message?.content || ''
        },
        finish_reason: mapFinishReason(choice.finish_reason)
      };
    });
  }
  
  return openAIResponse;
};

/**
 * 将Grok流式数据转换为OpenAI格式
 */
const transformStreamedGrokToOpenAI = (dataLine) => {
  // 将数据行解析为Grok数据块
  let grokChunks = [];
  try {
    const data = dataLine.replace(/^data: /, '').trim();
    
    // 处理[DONE]信号
    if (data === '[DONE]') {
      return [{ isDone: true }];
    }
    
    // 解析JSON数据
    const grokChunk = JSON.parse(data);
    grokChunks = [grokChunk]; // 通常每行只有一个chunk
  } catch (err) {
    logger.error(`转换流数据时出错: ${err.message}`);
    logger.debug(`问题数据行: ${dataLine}`);
    return []; // 返回空数组跳过此行
  }
  
  // 转换每个Grok chunk为OpenAI格式
  return grokChunks.map(chunk => {
    // 创建类似OpenAI的chunk结构
    const openAIChunk = {
      id: chunk.id || `chatcmpl-${Date.now().toString(36)}`,
      object: 'chat.completion.chunk',
      created: chunk.created || Math.floor(Date.now() / 1000),
      model: chunk.model || 'grok-3-latest',
      choices: []
    };
    
    // 处理choices
    if (chunk.choices && Array.isArray(chunk.choices)) {
      openAIChunk.choices = chunk.choices.map(choice => {
        const openAIChoice = {
          index: choice.index || 0,
          delta: {}
        };
        
        // 处理增量内容
        if (choice.delta?.content !== undefined) {
          openAIChoice.delta.content = choice.delta.content;
        }
        
        // 第一个chunk可能包含role
        if (choice.delta?.role) {
          openAIChoice.delta.role = 'assistant'; // 强制设置为assistant
        }
        
        // 处理finish_reason
        if (choice.finish_reason) {
          openAIChoice.finish_reason = mapFinishReason(choice.finish_reason);
        }
        
        return openAIChoice;
      });
    }
    
    return openAIChunk;
  });
};

/**
 * 映射模型名称(OpenAI -> Grok)
 */
const mapModelName = (modelName) => {
  // 如果未指定模型或模型名称已经是Grok格式,直接返回
  if (!modelName || modelName.startsWith('grok-')) {
    return modelName || 'grok-3-latest';
  }
  
  // 从环境变量获取自定义模型映射
  const targetGrokModel = process.env.TARGET_GROK_MODEL || 'grok-3-latest';
  
  // 常见OpenAI模型名称映射
  const modelMap = {
    'gpt-4': targetGrokModel,
    'gpt-4-turbo': targetGrokModel,
    'gpt-4-32k': targetGrokModel,
    'gpt-3.5-turbo': targetGrokModel,
    'gpt-3.5-turbo-16k': targetGrokModel
  };
  
  return modelMap[modelName] || targetGrokModel;
};

/**
 * 映射finish_reason(Grok -> OpenAI)
 */
const mapFinishReason = (reason) => {
  if (!reason) return null;
  
  const reasonMap = {
    'stop': 'stop',
    'length': 'length',
    'cancelled': 'stop', // 映射cancelled到stop
    'error': 'stop', // 映射error到stop
    'tool_use': 'tool_calls' // 如果未来支持工具调用
  };
  
  return reasonMap[reason] || reason;
};

module.exports = {
  transformOpenAIToGrok,
  transformGrokToOpenAI,
  transformStreamedGrokToOpenAI
}; 