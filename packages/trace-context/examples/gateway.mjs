// A gateway that takes part in the traces of the requests it handles, on
// node:http, through the package's JavaScript facade. For each request it
// extracts the context from the request's raw header lines and gives itself
// an operation of its own: a child of the request's context, or a root when
// the request has none. It then calls the downstream service with a new
// child of that operation among the call's headers, and returns the
// downstream response. It extracts first, rather than calling
// continueOrStartRequest, so that its log can say why it continued or
// started a trace: an absent or a rejected traceparent, or a discarded state.
//
// Tracing never fails a request here (the lenient policy). When no
// identifier can be generated, the call downstream forwards the received
// context unchanged or carries none, and the log line says why. A downstream
// that cannot be reached gives 502. The log holds the request's method and
// path and the package's diagnostics, which include no received context
// value: the gateway never logs header values.
//
// Run it from the repository root:
//   node packages/trace-context/examples/gateway.mjs
// It listens on 127.0.0.1:18777 and calls http://127.0.0.1:18776/downstream.
import http from 'node:http';
import * as TC from '../javascript/index.mjs';
import { extractRequest, requestHeaders } from '../javascript/node.mjs';

const downstream = 'http://127.0.0.1:18776/downstream';

function reply(response, status, type, body) {
  if (response.headersSent) {
    response.destroy();
    return;
  }
  response.writeHead(status, { 'content-type': type });
  response.end(body);
}

function handle(request, response) {
  const extraction = extractRequest(request);
  const service = TC.continueOrStart(extraction);
  const sent = TC.send(service, [['content-type', 'application/json']]);
  console.log(`${request.method} ${request.url}: ${extraction.show}; ${service.show}, downstream ${sent.show}`);
  const call = http.request(downstream, { method: 'POST', headers: requestHeaders(sent.fields), timeout: 3000 },
    (answer) => {
      const body = [];
      answer.on('data', (chunk) => body.push(chunk));
      answer.on('end', () => reply(response, answer.statusCode, 'application/json', Buffer.concat(body)));
      answer.on('error', () => reply(response, 502, 'text/plain', 'downstream unavailable'));
    });
  call.on('timeout', () => call.destroy(new Error('the downstream call timed out')));
  call.on('error', () => reply(response, 502, 'text/plain', 'downstream unavailable'));
  request.pipe(call);
}

http.createServer(handle).listen(18777, '127.0.0.1', () => console.log('http://127.0.0.1:18777'));
