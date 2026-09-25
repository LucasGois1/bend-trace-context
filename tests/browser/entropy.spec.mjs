import { test, expect } from './fixtures.mjs';

test('the browser obtains a U32 through the shared WebCrypto bridge', async ({ page }) => {
  await page.goto('/');
  const result = await page.evaluate(() => globalThis.traceContext.readRandomU32());
  expect(result.$).toBe('Done');
  expect(Number.isInteger(result.value)).toBe(true);
  expect(result.value).toBeGreaterThanOrEqual(0);
  expect(result.value).toBeLessThanOrEqual(0xffffffff);
});

for (const exception of ['TypeMismatchError', 'QuotaExceededError']) {
  test(`a real WebCrypto ${exception} becomes a structured source failure`, async ({ page }) => {
    await page.goto('/');
    const outcome = await page.evaluate(name => {
      let observed;
      const result = globalThis.traceContext.readRandomU32({
        getRandomValues() {
          try {
            return crypto.getRandomValues(name === 'TypeMismatchError'
              ? new Float32Array(1) : new Uint8Array(65537));
          } catch (error) {
            observed = error.name;
            throw error;
          }
        },
      });
      return { observed, result };
    }, exception);
    expect(outcome).toEqual({
      observed: exception,
      result: { $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' } },
    });
  });
}

test('missing host crypto and controlled provider failures return errors without fallback', async ({ page }) => {
  await page.goto('/');
  const results = await page.evaluate(() => {
    const read = globalThis.traceContext.readRandomU32;
    const absent = Object.getOwnPropertyDescriptor(globalThis, 'crypto');
    try {
      Object.defineProperty(globalThis, 'crypto', { configurable: true, value: undefined });
      return [read(), read({ getRandomValues() { throw new Error('controlled'); } }),
        read({ getRandomValues() { return [-1]; } })];
    } finally {
      Object.defineProperty(globalThis, 'crypto', absent);
    }
  });
  expect(results).toEqual([
    { $: 'Fail', error: { $: 'Tuple', fst: 1, snd: 'unavailable' } },
    { $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' } },
    { $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' } },
  ]);
});
