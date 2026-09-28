// The Fetch page (examples/javascript/fetch.html), bundled by the official
// Bend bundler, in each engine. Its server renders the context it hands to
// the page as <meta> elements (tests/browser/server.mjs), and its
// cross-origin calls reach an independent observer on another origin that
// records their header lines and preflights (tests/browser/observer.mjs).
// Expected values follow W3C Trace Context Level 2, spec #1 and the Fetch
// standard; they are not computed by the package.
import { test, expect } from './fixtures.mjs';

const TRACE = '0af7651916cd43dd8448eb211c80319c';
const TRACEPARENT = `00-${TRACE}-b7ad6b7169203331-01`;
const PARTNER = 'http://127.0.0.1:4174';

const rendered = (...fields) => `/fetch.html?${new URLSearchParams(fields)}`;

test('a bundled page continues the context its server rendered and generates children through WebCrypto', async ({ page }) => {
  await page.goto(rendered(['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE']));
  await expect(page.locator('#operation')).toHaveText('TraceParentAccepted, StateAccepted; Continued');
  const generated = await page.evaluate(() => {
    const { root, child, service } = globalThis.traceContext;
    const operation = service.outgoing.context;
    return { root: root().traceparent, operation: operation.traceparent, child: child(operation).traceparent,
      state: service.outgoing.tracestate };
  });
  expect(generated.root).toMatch(/^00-[0-9a-f]{32}-[0-9a-f]{16}-02$/);
  expect(generated.operation).toMatch(new RegExp(`^00-${TRACE}-[0-9a-f]{16}-01$`));
  expect(generated.operation).not.toContain('b7ad6b7169203331');
  expect(generated.child).toMatch(new RegExp(`^00-${TRACE}-[0-9a-f]{16}-01$`));
  expect(generated.child).not.toBe(generated.operation);
  expect(generated.state).toBe('congo=t61rcWkgMzE');
});

// The values that a request's raw header lines hold under `name`.
const lines = (rawHeaders, name) => {
  const found = [];
  for (let index = 0; index < rawHeaders.length; index += 2) {
    if (rawHeaders[index].toLowerCase() === name) found.push(rawHeaders[index + 1]);
  }
  return found;
};

// What the observer recorded under `key`.
const observed = async (key) => (await fetch(`${PARTNER}/observations/${key}`)).json();

test('without a rendered context the page starts a trace, and repeated traceparent elements are refused', async ({ page }) => {
  await page.goto('/fetch.html');
  await expect(page.locator('#operation')).toHaveText('TraceParentAbsent, StateAbsent; Started');
  expect(await page.evaluate(() => globalThis.traceContext.service.outgoing.context.traceparent))
    .toMatch(/^00-[0-9a-f]{32}-[0-9a-f]{16}-02$/);
  await page.goto(rendered(['traceparent', TRACEPARENT], ['traceparent', TRACEPARENT], ['tracestate', 'congo=1']));
  await expect(page.locator('#operation')).toHaveText('TraceParentRejected RepeatedTraceParent, StateIgnored; Started');
});

test('a same-origin call carries a new child of the page\'s operation in place of stale fields', async ({ page }) => {
  await page.goto(rendered(['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE']));
  const call = await page.evaluate(async () => {
    const { tracedFetch, service } = globalThis.traceContext;
    const { response, sent } = await tracedFetch(service, '/api/echo', {
      method: 'POST', headers: [['TraceParent', 'stale'], ['tracestate', 'old=1'], ['x-seen', 'a']], body: '{}',
    });
    return { echo: await response.json(), show: sent.show, child: sent.operation.traceparent,
      operation: service.outgoing.context.spanId };
  });
  expect(call.show).toBe('Fresh');
  expect(lines(call.echo.rawHeaders, 'traceparent')).toEqual([call.child]);
  expect(call.child).toMatch(new RegExp(`^00-${TRACE}-[0-9a-f]{16}-01$`));
  expect(call.child).not.toContain(call.operation);
  expect(lines(call.echo.rawHeaders, 'tracestate')).toEqual(['congo=t61rcWkgMzE']);
  expect(lines(call.echo.rawHeaders, 'x-seen')).toEqual(['a']);
});

test('Fetch Headers join repeated values before the page sees them, and extraction reads what remains', async ({ page }) => {
  await page.goto(rendered(['traceparent', TRACEPARENT]));
  const seen = await page.evaluate(async ([traceparent]) => {
    const { extract, tracedFetch, service } = globalThis.traceContext;
    const repeated = new Headers();
    repeated.append('x-seen', 'a');
    repeated.append('X-Seen', 'b');
    repeated.append('traceparent', traceparent);
    repeated.append('Traceparent', traceparent);
    const states = new Headers([['traceparent', traceparent], ['tracestate', 'congo=1'], ['tracestate', 'rojo=2']]);
    const { response, sent } = await tracedFetch(service, '/api/echo', { method: 'POST', headers: repeated });
    return {
      fields: [...repeated],
      repeated: extract([...repeated]).show,
      states: extract([...states]).incoming.tracestate,
      echo: (await response.json()).rawHeaders,
      show: sent.show,
    };
  }, [TRACEPARENT]);
  expect(seen.fields).toEqual([['traceparent', `${TRACEPARENT}, ${TRACEPARENT}`], ['x-seen', 'a, b']]);
  expect(seen.repeated).toBe('TraceParentRejected RepeatedTraceParent, StateAbsent');
  expect(seen.states).toBe('congo=1,rojo=2');
  expect(seen.show).toBe('Fresh');
  expect(lines(seen.echo, 'traceparent')).toHaveLength(1);
  expect(lines(seen.echo, 'traceparent')[0]).not.toContain(',');
  expect(lines(seen.echo, 'x-seen')).toEqual(['a, b']);
});

test('an allowed cross-origin call passes a preflight that accepts the context fields', async ({ page }, testInfo) => {
  const key = `allowed-${testInfo.project.name}`;
  await page.goto(rendered(['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE']));
  const call = await page.evaluate(async ([url, partner]) => {
    const { tracedFetch, service } = globalThis.traceContext;
    // Stale context fields, and a name that Headers joins.
    const headers = new Headers([['content-type', 'application/json'], ['x-seen', 'a'], ['X-Seen', 'b'],
      ['traceparent', 'stale'], ['tracestate', 'old=1']]);
    const { response, sent } = await tracedFetch(service, url, { method: 'POST', headers, body: '{"order":1}' },
      { propagateTo: [partner] });
    return { status: response.status, body: await response.json(), child: sent.operation.traceparent };
  }, [`${PARTNER}/allowed/${key}`, PARTNER]);
  expect(call.status).toBe(200);
  expect(call.body).toEqual({ observed: true });
  const [preflight, request] = await observed(key);
  expect(preflight.method).toBe('OPTIONS');
  const requested = lines(preflight.rawHeaders, 'access-control-request-headers')[0].split(',').map((name) => name.trim());
  expect(requested).toEqual(expect.arrayContaining(['traceparent', 'tracestate']));
  expect(request.method).toBe('POST');
  expect(lines(request.rawHeaders, 'traceparent')).toEqual([call.child]);
  expect(lines(request.rawHeaders, 'tracestate')).toEqual(['congo=t61rcWkgMzE']);
  expect(lines(request.rawHeaders, 'x-seen')).toEqual(['a, b']);
  expect(request.body).toBe('{"order":1}');
});

test('a cross-origin call that is not allowed carries no context fields, so it needs no preflight for them', async ({ page }, testInfo) => {
  const key = `unlisted-${testInfo.project.name}`;
  await page.goto(rendered(['traceparent', TRACEPARENT]));
  const call = await page.evaluate(async ([url, traceparent]) => {
    const { tracedFetch, service } = globalThis.traceContext;
    const { response, sent } = await tracedFetch(service, url, {
      method: 'POST', headers: [['content-type', 'text/plain'], ['traceparent', traceparent]], body: 'order',
    });
    return { status: response.status, sent };
  }, [`${PARTNER}/refused/${key}`, TRACEPARENT]);
  expect(call).toEqual({ status: 200, sent: null });
  const records = await observed(key);
  expect(records.map((record) => record.method)).toEqual(['POST']);
  expect(lines(records[0].rawHeaders, 'traceparent')).toEqual([]);
});

test('an allowed origin whose preflight refuses the context fields fails the call before it is sent', async ({ page }, testInfo) => {
  const key = `refused-${testInfo.project.name}`;
  await page.goto(rendered(['traceparent', TRACEPARENT]));
  const failure = await page.evaluate(async ([url, partner]) => {
    const { tracedFetch, service } = globalThis.traceContext;
    try {
      await tracedFetch(service, url, { method: 'POST', headers: { 'content-type': 'text/plain' }, body: 'order' },
        { propagateTo: [partner] });
      return 'sent';
    } catch (error) {
      return error.name;
    }
  }, [`${PARTNER}/refused/${key}`, PARTNER]);
  expect(failure).toBe('TypeError');
  expect((await observed(key)).map((record) => record.method)).toEqual(['OPTIONS']);
});

test('a no-cors call carries no context fields: the browser would drop them', async ({ page }, testInfo) => {
  const key = `no-cors-${testInfo.project.name}`;
  await page.goto(rendered(['traceparent', TRACEPARENT]));
  const call = await page.evaluate(async ([url, partner]) => {
    const { tracedFetch, service } = globalThis.traceContext;
    const { response, sent } = await tracedFetch(service, url, { method: 'POST', mode: 'no-cors', body: 'order' },
      { propagateTo: [partner] });
    return { type: response.type, sent };
  }, [`${PARTNER}/allowed/${key}`, PARTNER]);
  expect(call).toEqual({ type: 'opaque', sent: null });
  // The browser itself drops the field from a plain no-cors fetch as well.
  await page.evaluate(async ([url, traceparent]) => {
    await fetch(url, { method: 'POST', mode: 'no-cors', headers: { traceparent }, body: 'plain' });
  }, [`${PARTNER}/allowed/${key}`, TRACEPARENT]);
  const records = await observed(key);
  expect(records.map((record) => record.method)).toEqual(['POST', 'POST']);
  expect(records.map((record) => lines(record.rawHeaders, 'traceparent'))).toEqual([[], []]);
});

test('Fetch Headers remove the whitespace around values and refuse line breaks', async ({ page }) => {
  await page.goto('/fetch.html');
  const seen = await page.evaluate(() => {
    const trimmed = [...new Headers([['tracestate', ' \t congo=t61rcWkgMzE \t ']])];
    let refused;
    try {
      new Headers([['traceparent', 'a\r\nb']]);
      refused = 'accepted';
    } catch (error) {
      refused = error.name;
    }
    return { trimmed, refused };
  });
  expect(seen).toEqual({ trimmed: [['tracestate', 'congo=t61rcWkgMzE']], refused: 'TypeError' });
});

test('real WebCrypto exceptions forward the rendered pair leniently, and a strict call is not sent', async ({ page }, testInfo) => {
  const key = `strict-${testInfo.project.name}`;
  const later = `cc-${TRACE}-b7ad6b7169203331-ff-future`;
  await page.goto(rendered(['traceparent', later], ['tracestate', 'congo=t61rcWkgMzE'], ['tracestate', 'rojo=00f067aa0ba902b7']));
  const outcome = await page.evaluate(async ([url, partner]) => {
    const { continueOrStart, extraction, tracedFetch, service } = globalThis.traceContext;
    const observedErrors = [];
    const refusing = { getRandomValues() {
      try {
        return crypto.getRandomValues(new Uint8Array(65537));
      } catch (error) {
        observedErrors.push(error.name);
        throw error;
      }
    } };
    const untraced = continueOrStart(extraction, { crypto: refusing });
    const lenient = await tracedFetch(untraced, '/api/echo', { method: 'POST' });
    let strict;
    try {
      await tracedFetch(service, url, { method: 'POST' }, { propagateTo: [partner], policy: 'strict', crypto: refusing });
      strict = 'sent';
    } catch (error) {
      strict = `${error.name} ${error.reason}`;
    }
    return { observedErrors, untraced: untraced.show, lenient: lenient.sent.show,
      echo: (await lenient.response.json()).rawHeaders, strict };
  }, [`${PARTNER}/allowed/${key}`, PARTNER]);
  expect(outcome.observedErrors).toEqual(['QuotaExceededError', 'QuotaExceededError']);
  expect(outcome.untraced).toBe('Untraced SourceFailure 2 source-failure');
  expect(outcome.lenient).toBe('Forwarded after SourceFailure 2 source-failure');
  expect(lines(outcome.echo, 'traceparent')).toEqual([later]);
  expect(lines(outcome.echo, 'tracestate')).toEqual(['congo=t61rcWkgMzE,rojo=00f067aa0ba902b7']);
  expect(outcome.strict).toBe('GenerationError SourceFailure 2 source-failure');
  expect(await observed(key)).toEqual([]);
});

test('a received pair is forwarded intact to another origin', async ({ page }, testInfo) => {
  const key = `forwarded-${testInfo.project.name}`;
  const later = `cc-${TRACE}-b7ad6b7169203331-ff-future`;
  await page.goto(rendered(['traceparent', later], ['tracestate', 'congo=t61rcWkgMzE'], ['tracestate', 'rojo=00f067aa0ba902b7']));
  const status = await page.evaluate(async (url) => {
    const { extraction, forward } = globalThis.traceContext;
    const forwarded = forward(extraction.incoming, [['content-type', 'text/plain']]);
    return (await fetch(url, { method: 'POST', headers: forwarded.fields, body: 'relay' })).status;
  }, `${PARTNER}/allowed/${key}`);
  expect(status).toBe(200);
  const request = (await observed(key)).find((record) => record.method === 'POST');
  expect(lines(request.rawHeaders, 'traceparent')).toEqual([later]);
  expect(lines(request.rawHeaders, 'tracestate')).toEqual(['congo=t61rcWkgMzE,rojo=00f067aa0ba902b7']);
});

test('forged values and invalid arguments are refused before any request is made', async ({ page }, testInfo) => {
  const key = `forged-${testInfo.project.name}`;
  await page.goto(rendered(['traceparent', TRACEPARENT]));
  const refused = await page.evaluate(async (url) => {
    const { tracedFetch, documentFields, service } = globalThis.traceContext;
    // A source that counts its words: an invalid header must be refused
    // before any child is generated.
    const counting = { reads: 0, getRandomValues(array) { counting.reads += 1; array[0] = 7; return array; } };
    const attempts = [
      () => tracedFetch({ ...service }, '/api/echo'),
      () => tracedFetch({ ...service }, url),
      () => tracedFetch(service, url, { headers: [['x-seen']] }),
      () => tracedFetch(service, '/api/echo', { headers: [['bad name', 'x']] }, { crypto: counting }),
      () => tracedFetch(service, url, {}, { propagateTo: ['http://127.0.0.1:4174/path'] }),
      () => tracedFetch(service, url, {}, { propagateTo: [4174] }),
      () => tracedFetch(service, url, {}, { sampling: 'always' }),
      () => tracedFetch(service, url, {}, { policy: 'strickt' }),
      () => tracedFetch(service, url, {}, { fetch: 'fetch' }),
    ];
    const names = [];
    for (const attempt of attempts) {
      try {
        await attempt();
        names.push('sent');
      } catch (error) {
        names.push(error.name);
      }
    }
    try {
      documentFields({});
    } catch (error) {
      names.push(error.name);
    }
    names.push(counting.reads);
    return names;
  }, `${PARTNER}/refused/${key}`);
  expect(refused).toEqual(['TypeError', 'TypeError', 'TypeError', 'TypeError', 'RangeError', 'TypeError', 'RangeError',
    'RangeError', 'TypeError', 'TypeError', 0]);
  expect(await observed(key)).toEqual([]);
});

test('meta names are read without regard to ASCII case, and a RegExp allows the URLs it matches', async ({ page }, testInfo) => {
  const key = `regexp-${testInfo.project.name}`;
  await page.goto('/fetch.html');
  const outcome = await page.evaluate(async ([url, other, traceparent]) => {
    const { continueOrStart, documentFields, extract, tracedFetch } = globalThis.traceContext;
    const meta = document.createElement('meta');
    meta.setAttribute('name', 'TraceParent');
    meta.setAttribute('content', traceparent);
    document.head.append(meta);
    const fields = documentFields(document);
    const service = continueOrStart(extract(fields));
    const allowed = /^http:\/\/127\.0\.0\.1:4174\/allowed\//;
    const matched = await tracedFetch(service, url, { method: 'POST', headers: { 'content-type': 'text/plain' } },
      { propagateTo: [allowed] });
    const unmatched = await tracedFetch(service, other, { method: 'POST', headers: { 'content-type': 'text/plain' } },
      { propagateTo: [allowed] });
    return { fields, service: service.show, matched: matched.sent.show, unmatched: unmatched.sent };
  }, [`${PARTNER}/allowed/${key}`, `${PARTNER}/refused/${key}`, TRACEPARENT]);
  expect(outcome).toEqual({ fields: [['traceparent', TRACEPARENT]], service: 'Continued', matched: 'Fresh', unmatched: null });
  const records = await observed(key);
  const posts = records.filter((record) => record.method === 'POST');
  expect(posts.map((record) => [record.route, lines(record.rawHeaders, 'traceparent').length])).toEqual([['allowed', 1], ['refused', 0]]);
});

test('a Request object is sent with its own fields and a new child in place of its stale ones', async ({ page }) => {
  await page.goto(rendered(['traceparent', TRACEPARENT]));
  const call = await page.evaluate(async () => {
    const { tracedFetch, service } = globalThis.traceContext;
    const request = new Request('/api/echo', { method: 'POST', headers: { 'x-seen': 'a', traceparent: 'stale' },
      body: 'x', referrerPolicy: 'no-referrer' });
    const { response, sent } = await tracedFetch(service, request);
    return { echo: await response.json(), child: sent.operation.traceparent };
  });
  expect(call.echo.method).toBe('POST');
  expect(lines(call.echo.rawHeaders, 'traceparent')).toEqual([call.child]);
  expect(lines(call.echo.rawHeaders, 'x-seen')).toEqual(['a']);
  // The Request keeps its referrer policy.
  expect(lines(call.echo.rawHeaders, 'referer')).toEqual([]);
});

test('the Fetch page\'s buttons call its APIs and show what Fetch hands over', async ({ page }) => {
  await page.goto(rendered(['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE']));
  const result = page.locator('#result');
  await page.getByRole('button', { name: 'Call the same-origin API' }).click();
  await expect(result).toHaveText('200, Fresh');
  await page.getByRole('button', { name: 'Call the partner API' }).click();
  await expect(result).toHaveText('200, Fresh');
  await page.getByRole('button', { name: 'Show what Fetch hands over' }).click();
  await expect(result).toHaveText([
    `traceparent: ${TRACEPARENT}, ${TRACEPARENT}`, 'tracestate: congo=t61rcWkgMzE', 'x-seen: a, b',
    'TraceParentRejected RepeatedTraceParent, StateIgnored',
  ].join('\n'));
});

test('a redirect that fetch follows repeats the call with the same child at the new URL', async ({ page }, testInfo) => {
  const followed = `followed-${testInfo.project.name}`;
  const blocked = `blocked-${testInfo.project.name}`;
  const refused = `redirect-refused-${testInfo.project.name}`;
  await page.goto(rendered(['traceparent', TRACEPARENT]));
  const outcome = await page.evaluate(async ([allowedUrl, blockedUrl, refusedUrl]) => {
    const { tracedFetch, service } = globalThis.traceContext;
    const via = (url) => `/api/redirect?to=${encodeURIComponent(url)}`;
    const init = { method: 'POST', headers: { 'content-type': 'text/plain' }, body: 'order' };
    const { response, sent } = await tracedFetch(service, via(allowedUrl), init);
    const attempt = async (url, extra) => {
      try {
        await tracedFetch(service, via(url), { ...init, ...extra });
        return 'sent';
      } catch (error) {
        return error.name;
      }
    };
    return { redirected: response.redirected, status: response.status, child: sent.operation.traceparent,
      error: await attempt(blockedUrl, { redirect: 'error' }), refused: await attempt(refusedUrl, {}) };
  }, [`${PARTNER}/allowed/${followed}`, `${PARTNER}/allowed/${blocked}`, `${PARTNER}/refused/${refused}`]);
  expect(outcome).toMatchObject({ redirected: true, status: 200, error: 'TypeError', refused: 'TypeError' });
  const request = (await observed(followed)).find((record) => record.method === 'POST');
  expect(lines(request.rawHeaders, 'traceparent')).toEqual([outcome.child]);
  expect(await observed(blocked)).toEqual([]);
  expect((await observed(refused)).map((record) => record.method)).toEqual(['OPTIONS']);
});

test('a RegExp in the allowlist matches on every call, and init is read once', async ({ page }, testInfo) => {
  const key = `once-${testInfo.project.name}`;
  await page.goto(rendered(['traceparent', TRACEPARENT]));
  const outcome = await page.evaluate(async ([url]) => {
    const { tracedFetch, service } = globalThis.traceContext;
    const global = /^http:\/\/127\.0\.0\.1:4174\/allowed\//g;
    const shows = [];
    for (let call = 0; call < 3; call += 1) {
      const { sent } = await tracedFetch(service, url, { method: 'POST', headers: { 'content-type': 'text/plain' } },
        { propagateTo: [global] });
      shows.push(sent === null ? 'no context' : sent.show);
    }
    let reads = 0;
    const init = { method: 'POST', get mode() { reads += 1; return reads === 1 ? 'cors' : 'no-cors'; } };
    const { sent } = await tracedFetch(service, url, init, { propagateTo: [global] });
    return { shows, reads, last: sent.show };
  }, [`${PARTNER}/allowed/${key}`]);
  expect(outcome).toEqual({ shows: ['Fresh', 'Fresh', 'Fresh'], reads: 1, last: 'Fresh' });
  const posts = (await observed(key)).filter((record) => record.method === 'POST');
  expect(posts.map((record) => lines(record.rawHeaders, 'traceparent').length)).toEqual([1, 1, 1, 1]);
});

test('each engine\'s order of header lines is recorded; the lines of one name keep their order', async ({ page }, testInfo) => {
  await page.goto('/fetch.html');
  const names = await page.evaluate(async () => {
    const response = await fetch('/api/echo', { method: 'POST',
      headers: [['x-first', '1'], ['traceparent', 'a'], ['tracestate', 'b'], ['a-last', '2']] });
    const { rawHeaders } = await response.json();
    return rawHeaders.filter((item, index) => index % 2 === 0)
      .filter((name) => ['x-first', 'traceparent', 'tracestate', 'a-last'].includes(name.toLowerCase()));
  });
  await testInfo.attach('header-order.json', { body: JSON.stringify(names), contentType: 'application/json' });
  expect([...names].map((name) => name.toLowerCase()).sort()).toEqual(['a-last', 'traceparent', 'tracestate', 'x-first']);
});

test('a page without an origin of its own sends the context fields only to allowed origins', async ({ page }) => {
  await page.goto(rendered(['traceparent', TRACEPARENT]));
  const outcome = await page.evaluate(async () => {
    const { tracedFetch, service } = globalThis.traceContext;
    Object.defineProperty(globalThis, 'origin', { configurable: true, value: 'null' });
    const { sent } = await tracedFetch(service, '/api/echo', { method: 'POST' });
    return { origin: globalThis.origin, sent };
  });
  expect(outcome).toEqual({ origin: 'null', sent: null });
});
