// The independent browser consumer (tests/consumer/browser), bundled from a
// pinned checkout by scripts/test-consumer.sh browser, in each engine. Its
// server renders the context it hands to the page, and its cross-origin
// calls reach the independent observer of tests/browser/observer.mjs. The
// README's browser quick start runs too, served by the JavaScript guide's
// server on 127.0.0.1:4175.
import { readFileSync } from 'node:fs';
import { test, expect } from '../browser/fixtures.mjs';

const expected = readFileSync(new URL('./browser-expected.txt', import.meta.url), 'utf8').trimEnd();
// What the README shows that its browser quick start logs.
const quickstartExpected = readFileSync(process.env.BEND_QUICKSTART_EXPECTED, 'utf8').trimEnd();

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

test('the README\'s page continues the context that the guide\'s server rendered into it', async ({ page }) => {
  const logged = [];
  page.on('console', (message) => { if (message.type() === 'log') logged.push(message.text()); });
  const call = page.waitForRequest((request) => request.url().endsWith('/api/orders'));
  await page.goto('http://127.0.0.1:4175/');
  // The server's operation for the page request, and the page's request.
  const [, trace, span] = (await page.locator('meta[name="traceparent"]').getAttribute('content')).split('-');
  const sent = (await (await call).allHeaders()).traceparent.split('-');
  expect(sent[1]).toBe(trace);
  expect(sent[2]).not.toBe(span);
  await expect.poll(() => logged.join('\n'), { timeout: 10000 }).toBe(quickstartExpected);
});
