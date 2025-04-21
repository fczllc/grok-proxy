const express = require('express');
const { handleChatCompletions } = require('../controllers/chatCompletions');

const router = express.Router();

// POST /v1/chat/completions 路由
router.post('/', handleChatCompletions);

module.exports = router; 