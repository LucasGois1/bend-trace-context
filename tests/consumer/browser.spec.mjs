// The independent browser consumer (tests/consumer/browser), bundled from a
// pinned checkout by scripts/test-consumer.sh browser, in each engine. Its
// server renders the context it hands to the page, and its cross-origin
// calls reach the independent observer of tests/browser/observer.mjs.
import { readFileSync } from 'node:fs';
import { test, expect } from '../browser/fixtures.mjs';

const expected = readFileSync(new URL('./browser-expected.txt', import.meta.url), 'utf8').trimEnd();

test('an application bundled from a pinned checkout propagates its trace with Fetch', async ({ page }, testInfo) => {
  const key = `consumer-${testInfo.project.name}`;
  const query = new URLSearchParams([
    ['traceparent', '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01'], ['tracestate', 'congo=t61rcWkgMzE'],
    ['key', key],
  ]);
  await page.goto(`/index.html?${query}`);
  await expect(page.getByRole('status')).toHaveText(expected, { timeout: 10000 });
  const records = await (await fetch(`http://127.0.0.1:4174/observations/${key}`)).json();
  const posts = records.filter((record) => record.method === 'POST');
  const traceparents = posts.map((record) => record.rawHeaders.filter((item, index) => index % 2 === 1
    && record.rawHeaders[index - 1].toLowerCase() === 'traceparent'));
  expect(posts.map((record) => record.route)).toEqual(['allowed', 'refused']);
  expect(traceparents).toEqual([['00-0af7651916cd43dd8448eb211c80319c-a3ce929d0e0e4736-01'], []]);
  expect(await (await fetch(`http://127.0.0.1:4174/observations/${key}-strict`)).json()).toEqual([]);
});
