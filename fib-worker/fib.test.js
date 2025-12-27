const { fib } = require('./fib');

describe('Fibonacci calculation', () => {
  describe('Base cases', () => {
    test('fib(0) should return 1', () => {
      expect(fib(0)).toBe(1);
    });

    test('fib(1) should return 1', () => {
      expect(fib(1)).toBe(1);
    });
  });

  describe('Small indices', () => {
    test('fib(2) should return 2', () => {
      expect(fib(2)).toBe(2);
    });

    test('fib(3) should return 3', () => {
      expect(fib(3)).toBe(3);
    });

    test('fib(4) should return 5', () => {
      expect(fib(4)).toBe(5);
    });

    test('fib(5) should return 8', () => {
      expect(fib(5)).toBe(8);
    });

    test('fib(6) should return 13', () => {
      expect(fib(6)).toBe(13);
    });
  });

  describe('Larger indices', () => {
    test('fib(10) should return 89', () => {
      expect(fib(10)).toBe(89);
    });

    test('fib(15) should return 987', () => {
      expect(fib(15)).toBe(987);
    });

    test('fib(20) should return 10946', () => {
      expect(fib(20)).toBe(10946);
    });
  });

  describe('Maximum allowed index (40)', () => {
    test('fib(40) should return 165580141', () => {
      expect(fib(40)).toBe(165580141);
    });
  });

  describe('Edge cases', () => {
    test('negative index should still follow algorithm (edge case)', () => {
      // Current implementation doesn't validate negative
      // Testing actual behavior
      expect(fib(-1)).toBe(1);
    });
  });

  describe('Performance', () => {
    test('should compute fib(40) in reasonable time', () => {
      const start = Date.now();
      const result = fib(40);
      const duration = Date.now() - start;

      expect(result).toBe(165580141);
      expect(duration).toBeLessThan(10); // Should be near-instant
    });
  });
});
