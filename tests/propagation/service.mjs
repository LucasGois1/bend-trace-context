// The Node service under test for the W3C Trace Context harness and for the
// repository's own propagation checks, on node:http. It imports the
// package's JavaScript facade installed from a pinned checkout, as an
// application would, and every Trace Context decision comes from it; this
// file only routes requests and speaks the harness's protocol. Its routes
// and responses are those of service.bend:
//
// POST /test follows the harness: the body is a JSON array of actions, each
// {url, arguments}, and for each the service posts `arguments` to `url` as a
// request of its own, carrying a new child of its operation for the received
// request. The other routes change one choice for the repository's checks:
//   /test/restart             the service restarts the trace, as at a trust
//                             boundary
//   /test/stale               each request starts from the received
//                             request's context fields and x-request-id, and
//                             each later one reuses the previous one's fields
//   /test/unavailable         the entropy source is unavailable, so the
//                             service has no operation and the requests
//                             carry the lenient fallback; they start from
//                             the copied fields too
//   /test/unavailable/strict  the same source under the strict policy, which
//                             refuses the request
//   /test/unavailable/send    the service's operation comes from the host,
//                             and each child from the unavailable source, so
//                             each request carries the fallback of an
//                             operating service; under
//                             /test/unavailable/send/strict, the request is
//                             refused before any is sent
//   /test/exhausted           a source that gives only zero words, so every
//                             candidate is rejected and generation is
//                             exhausted
// The response is a JSON object with the diagnostics, which hold no received
// value.
import http from 'node:http';
import * as TC from 'bend-trace-context';
import { continueOrStartRequest, extractRequest, requestFields, requestHeaders } from 'bend-trace-context/node';

const port = 18775;
const maxBody = 1048576;

// A source whose every word is zero: every candidate identifier is all
// zero, so generation ends exhausted.
const zeros = { getRandomValues(words) { words.fill(0); return words; } };

// The fields a request to send starts from: only its content type.
const empty = () => [['content-type', 'application/json']];

// The fields a request to send starts from in the stale routes: the received
// request's context fields and x-request-id, copied as a careless
// application would copy them, with the content type.
const copied = (request) => [...empty(), ...requestFields(request)
  .filter(([name]) => ['traceparent', 'tracestate', 'x-request-id'].includes(name.toLowerCase()))];

// A whole response with its length, as service.bend sends it.
function respond(response, status, body) {
  const text = typeof body === 'string' ? body : JSON.stringify(body);
  response.writeHead(status, {
    'content-type': typeof body === 'string' ? 'text/plain' : 'application/json',
    'content-length': Buffer.byteLength(text),
  });
  response.end(text);
}

// Post one action's arguments with the fields that the package wrote.
function callback(action, fields) {
  return new Promise((resolve) => {
    let call;
    try {
      call = http.request(action.url, { method: 'POST', headers: requestHeaders(fields), timeout: 3000 },
        (answer) => {
          answer.resume();
          answer.on('end', () => resolve(answer.statusCode === 200));
          answer.on('error', () => resolve(false));
        });
    } catch {
      resolve(false);
      return;
    }
    call.on('timeout', () => call.destroy(new Error('the callback timed out')));
    call.on('error', () => resolve(false));
    call.end(JSON.stringify(action.arguments ?? []));
  });
}

// Send every action's request, each with a new child of the service's
// operation, or its fallback when the service has none. When reusing, each
// request starts from the fields the previous one was sent with.
async function callbacks(service, actions, container, { reuse = false, crypto } = {}) {
  const sent = [];
  let ok = true;
  let fields = container;
  for (const action of actions) {
    const message = TC.send(service, fields, { crypto });
    sent.push(message.show);
    ok = (typeof action?.url === 'string' && await callback(action, message.fields)) && ok;
    if (reuse) fields = message.fields;
  }
  return { sent, ok };
}

async function served(request, response, service, actions, container, options) {
  const done = await callbacks(service, actions, container, options);
  respond(response, done.ok ? 200 : 502,
    { extraction: extractRequest(request).show, service: service.show, sent: done.sent, ok: done.ok });
}

function refused(response, error) {
  if (!(error instanceof TC.GenerationError)) throw error;
  respond(response, 503, { refused: error.reason });
}

async function route(request, response, actions) {
  switch (new URL(request.url, 'http://service').pathname) {
    case '/test':
      return served(request, response, continueOrStartRequest(request), actions, empty());
    case '/test/restart':
      return served(request, response, continueOrStartRequest(request, { reception: 'restart' }), actions, empty());
    case '/test/stale':
      return served(request, response, continueOrStartRequest(request), actions, copied(request), { reuse: true });
    case '/test/unavailable':
      return served(request, response, continueOrStartRequest(request, { crypto: null }), actions, copied(request),
        { reuse: true });
    case '/test/unavailable/strict':
      try {
        const service = continueOrStartRequest(request, { policy: 'strict', crypto: null });
        return respond(response, 500, { unexpected: service.show });
      } catch (error) {
        return refused(response, error);
      }
    case '/test/unavailable/send':
      return served(request, response, continueOrStartRequest(request), actions, copied(request), { crypto: null });
    case '/test/unavailable/send/strict':
      try {
        const sent = TC.send(continueOrStartRequest(request), empty(), { policy: 'strict', crypto: null });
        return respond(response, 500, { unexpected: sent.show });
      } catch (error) {
        return refused(response, error);
      }
    case '/test/exhausted':
      return served(request, response, continueOrStartRequest(request, { crypto: zeros }), actions, copied(request),
        { reuse: true });
    default:
      return respond(response, 404, 'not found');
  }
}

function handle(request, response) {
  const chunks = [];
  let size = 0;
  request.on('data', (chunk) => {
    size += chunk.length;
    if (size <= maxBody) chunks.push(chunk);
  });
  request.on('end', () => {
    if (size > maxBody) return respond(response, 413, 'request body too large');
    let actions;
    try {
      actions = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch {
      actions = undefined;
    }
    if (!Array.isArray(actions)) return respond(response, 400, 'expected a JSON array of actions');
    route(request, response, actions).catch(() => respond(response, 500, 'service failure'));
  });
}

http.createServer(handle).listen(port, '127.0.0.1', () => console.log(`http://127.0.0.1:${port}`));
