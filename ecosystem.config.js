module.exports = {
  apps: [{
    name: 'grok-proxy',
    script: 'src/server.js',
    instances: 'max',
    exec_mode: 'cluster',
    autorestart: true,
    watch: false,
    max_memory_restart: '300M',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
    error_file: './logs/pm2-error.log',
    out_file: './logs/pm2-out.log',
    merge_logs: true,
    // 在服务器发生意外重启时，自动重启服务
    restart_delay: 4000,
    // 最大重启次数，超过则停止尝试
    max_restarts: 10,
    // 监控配置
    exp_backoff_restart_delay: 100
  }]
}; 