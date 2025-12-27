const keys = require('./keys');
const redis = require('redis');
const http = require('http');
const { fib } = require('./fib');

const redisClient = redis.createClient({
  socket: {
    host: keys.redisHost,
    port: keys.redisPort,
    reconnectStrategy: () => 1000,
  },
});

const sub = redisClient.duplicate();

let workerHealthy = false;
let redisHealthy = false;

// Health check HTTP server
const healthServer = http.createServer((req, res) => {
  if (req.url === '/health' && req.method === 'GET') {
    const status = workerHealthy && redisHealthy ? 'healthy' : 'degraded';
    const checks = {
      worker: workerHealthy ? 'healthy' : 'unhealthy',
      redis: redisHealthy ? 'healthy' : 'unhealthy'
    };

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status, checks }));
  } else {
    res.writeHead(404);
    res.end();
  }
});

healthServer.listen(5001, () => {
  console.log('Health check server listening on port 5001');
});

(async () => {
  try {
    await redisClient.connect();
    await sub.connect();
    redisHealthy = true;

    await sub.subscribe('insert', async (message) => {
      const index = parseInt(message);
      const result = fib(index);
      await redisClient.set(`values.${index}`, result.toString());
      console.log(`Calculated fib(${index}) = ${result}`);
    });

    workerHealthy = true;
    console.log('Worker started. Waiting for jobs...');
  } catch (err) {
    console.error('Worker startup failed:', err);
    workerHealthy = false;
    redisHealthy = false;
  }
})();
