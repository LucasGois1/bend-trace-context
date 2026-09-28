// An independent observer on another origin, 127.0.0.1:4174, for the
// browser pages' cross-origin calls. It records the method and the raw
// header lines of every request, preflights included, as they arrive, under
// the key in its path, and gives them back to the tests at
// /observations/<key>. Its CORS answers differ by route:
//   /allowed/<key>  the preflight allows the context fields, and the call
//                   may read the response
//   /refused/<key>  the preflight allows no request header, so a call
//                   carrying the context fields is refused by the browser;
//                   a CORS-simple call without them needs no preflight and
//                   succeeds
import { createServer } from 'node:http';

const page = 'http://127.0.0.1:4173';
const observations = new Map();

createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1:4174');
  const [, route, key] = url.pathname.split('/');
  if (route === 'health') {
    response.writeHead(200).end('ok');
    return;
  }
  if (route === 'observations') {
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(observations.get(key) ?? []));
    return;
  }
  const chunks = [];
  request.on('data', (chunk) => chunks.push(chunk));
  request.on('end', () => {
    observations.set(key, [...(observations.get(key) ?? []), {
      route, method: request.method, rawHeaders: request.rawHeaders, body: Buffer.concat(chunks).toString(),
    }]);
    const cors = { 'Access-Control-Allow-Origin': page };
    if (request.method === 'OPTIONS') {
      if (route === 'allowed') {
        cors['Access-Control-Allow-Methods'] = 'POST';
        cors['Access-Control-Allow-Headers'] = 'content-type, traceparent, tracestate, x-seen';
      }
      response.writeHead(204, cors).end();
      return;
    }
    response.writeHead(200, { ...cors, 'Content-Type': 'application/json' });
    response.end('{"observed":true}');
  });
}).listen(4174, '127.0.0.1');
