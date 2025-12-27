const keys = require('./keys');
const redis = require('redis');
const { fib } = require('./fib');

const redisClient = redis.createClient({
  socket: {
    host: keys.redisHost,
    port: keys.redisPort,
    reconnectStrategy: () => 1000,
  },
});

const sub = redisClient.duplicate();

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
