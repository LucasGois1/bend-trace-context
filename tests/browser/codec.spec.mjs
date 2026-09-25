import { test, expect } from './fixtures.mjs';

test('an application page uses the officially bundled Bend codec', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Inspect traceparent' }).click();
  await expect(page.getByRole('status')).toHaveText(JSON.stringify({
    ok: true,
    traceparent: '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
    sampled: true,
  }));
});

test('browser callers cannot pass foreign proof objects or malformed wire data', async ({ page }) => {
  await page.goto('/');
  await page.getByLabel('Traceparent').fill('00-00000000000000000000000000000000-b7ad6b7169203331-01');
  await page.getByRole('button', { name: 'Inspect traceparent' }).click();
  await expect(page.getByRole('status')).toHaveText(JSON.stringify({ ok: false, error: 'ZeroTraceId' }));
  const results = await page.evaluate(() => [null, undefined, 42, [],
    { $: 'TraceParentV00', evidence: null }, new String('forged'),
    { toString() { throw new Error('must not coerce'); } },
  ].map(value => globalThis.traceContext.inspectTraceparent(value)));
  expect(results).toEqual(Array(7).fill({ ok: false, error: 'InvalidInputType' }));
});
