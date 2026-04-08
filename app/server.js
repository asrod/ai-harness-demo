#!/usr/bin/env node
/**
 * 故意返回错误 message，供 Karate 首次运行失败；AI 修复后应改为 'world'。
 */
const http = require('http');

const PORT = Number(process.env.PORT || 3000);

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/hello') {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    // 故意错误：测试期望 "world"
    res.end(JSON.stringify({ message: 'yifeiHu' }));
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('Not Found');
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[server] listening on http://127.0.0.1:${PORT}`);
});
