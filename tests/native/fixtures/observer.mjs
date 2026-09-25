import { createServer } from 'node:http';

const port = Number(process.env.OBSERVER_PORT ?? 18774);
const server = createServer((request, response) => {
  const chunks = [];
  request.on('data', chunk => chunks.push(chunk));
  request.on('end', () => {
    const body = Buffer.concat(chunks).toString('utf8');
    console.log(`${request.method} ${request.url} ${body}`);
    if (request.url === '/redirect') {
      response.writeHead(302, { location: '/redirected' });
      response.end();
      return;
    }
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end('null');
  });
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Independent observer listening at http://127.0.0.1:${port}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
