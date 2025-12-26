
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

app.get('/', (req, res) => {
  res.json({
    message: '🎉 Updated! Pull-based Runner Works!',
    version: process.env.VERSION || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString(),
    architecture: 'Pull-based (Polling)',
    security: 'No inbound ports required'
  });
});

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    uptime: Math.floor(process.uptime())
  });
});

app.get('/api/info', (req, res) => {
  res.json({
    app: 'Node.js CI/CD Demo',
    version: process.env.VERSION || '1.0.0',
    node: process.version,
    memory: {
      total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024) + ' MB',
      used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024) + ' MB'
    }
  });
});

app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📦 Version: ${process.env.VERSION || '1.0.0'}`);
});