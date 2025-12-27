const keys = require('./keys');
const redis = require('redis');

const redisClient = redis.createClient({
  socket: {
    host: keys.redisHost,
    port: keys.redisPort,
    reconnectStrategy: () => 1000,
  },
});

const sub = redisClient.duplicate();

function fib(index) {
  if (index < 2) return 1;
  let a = 1, b = 1;
  for (let i = 2; i <= index; i++) {
    [a, b] = [b, a + b];
  }
  return b;
}

(async () => {
  await redisClient.connect();
  await sub.connect();

  await sub.subscribe('insert', async (message) => {
    const index = parseInt(message);
    const result = fib(index);
    await redisClient.set(`values.${index}`, result.toString());
    console.log(`Calculated fib(${index}) = ${result}`);
  });

  console.log('Worker started. Waiting for jobs...');
})();
