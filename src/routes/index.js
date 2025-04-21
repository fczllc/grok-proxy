const express = require('express');
const chatCompletionsRoutes = require('./chatCompletions');

const router = express.Router();

// 聊天完成API路由
router.use('/chat/completions', chatCompletionsRoutes);

module.exports = router; 