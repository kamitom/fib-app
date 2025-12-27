/**
 * Calculate Fibonacci number at given index
 * @param {number} index - The index in Fibonacci sequence
 * @returns {number} The Fibonacci number at that index
 */
function fib(index) {
  if (index < 2) return 1;
  let a = 1, b = 1;
  for (let i = 2; i <= index; i++) {
    [a, b] = [b, a + b];
  }
  return b;
}

module.exports = { fib };
