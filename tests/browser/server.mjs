// The application server of the browser tests on 127.0.0.1:4173. It serves
// the pages that the official Bend bundler built into build/browser, or into
// the directory that BROWSER_ROOT names, such as a consumer's. For an
// HTML page it renders `traceparent` and `tracestate` query parameters as
// <meta> elements, as a server that hands its context to the page does.
// /api/echo answers with the raw header lines of the request it received,
// for the page's same-origin calls, and /api/redirect?to=<url> redirects a
// call with 307 to `url`.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve } from 'node:path';

const root = resolve(process.env.BROWSER_ROOT ?? 'build/browser');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };

const attribute = (text) => text.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');

// The <meta> elements of the context fields named in the query, in order.
const metas = (url) => [...url.searchParams]
  .filter(([name]) => name === 'traceparent' || name === 'tracestate')
  .map(([name, value]) => `<meta name="${name}" content="${attribute(value)}">`)
  .join('\n    ');

createServer(async (request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1:4173');
  if (url.pathname === '/api/redirect') {
    request.resume();
    request.on('end', () => response.writeHead(307, { Location: url.searchParams.get('to') }).end());
    return;
  }
  if (url.pathname === '/api/echo') {
    request.resume();
    request.on('end', () => {
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ method: request.method, rawHeaders: request.rawHeaders }));
    });
    return;
  }
  const file = resolve(root, '.' + (url.pathname === '/' ? '/index.html' : url.pathname));
  if (!file.startsWith(root + '/')) {
    response.writeHead(403).end();
    return;
  }
  try {
    let content = await readFile(file);
    if (extname(file) === '.html') {
      content = content.toString('utf8').replace('<meta charset="utf-8">', `<meta charset="utf-8">\n    ${metas(url)}`);
    }
    response.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream' });
    response.end(content);
  } catch {
    response.writeHead(404).end();
  }
}).listen(4173, '127.0.0.1');
