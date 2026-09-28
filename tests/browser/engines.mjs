// What the browser configurations share: the three engines, and the page
// server and the independent observer, started from the repository root.
// BROWSER_ROOT, when given, names the directory of the pages to serve.
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('../..', import.meta.url));

export const projects = [
  { name: 'chromium', use: { browserName: 'chromium' } },
  { name: 'firefox', use: { browserName: 'firefox' } },
  { name: 'webkit', use: { browserName: 'webkit' } },
];

export const servers = (root) => [
  {
    command: 'node tests/browser/server.mjs',
    cwd: repository,
    env: root === undefined ? {} : { BROWSER_ROOT: root },
    url: 'http://127.0.0.1:4173/index.html',
    reuseExistingServer: false,
  },
  {
    command: 'node tests/browser/observer.mjs',
    cwd: repository,
    url: 'http://127.0.0.1:4174/health',
    reuseExistingServer: false,
  },
];
