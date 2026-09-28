// Playwright for the independent browser consumer: BEND_BROWSER_CONSUMER
// names the directory of its bundled page, BEND_BROWSER_QUICKSTART the
// directory of the README's browser quick start and of the JavaScript
// guide's server for it, and BEND_BROWSER_EVIDENCE the directory for the
// results. scripts/test-consumer.sh browser sets all three.
import { defineConfig } from '@playwright/test';
import { projects, servers } from '../browser/engines.mjs';

const page = process.env.BEND_BROWSER_CONSUMER;
const quickstart = process.env.BEND_BROWSER_QUICKSTART;
const evidence = process.env.BEND_BROWSER_EVIDENCE;
if (!page || !quickstart || !evidence) {
  throw new Error('Set BEND_BROWSER_CONSUMER, BEND_BROWSER_QUICKSTART and BEND_BROWSER_EVIDENCE.');
}

export default defineConfig({
  testDir: '.',
  testMatch: 'browser.spec.mjs',
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  reporter: [['list'], ['json', { outputFile: `${evidence}/browser-results.json` }]],
  outputDir: `${evidence}/browser-traces`,
  use: { baseURL: 'http://127.0.0.1:4173', trace: 'retain-on-failure' },
  projects,
  webServer: [
    ...servers(page),
    {
      command: 'node server.mjs',
      cwd: quickstart,
      env: { PORT: '4175' },
      url: 'http://127.0.0.1:4175/',
      reuseExistingServer: false,
    },
  ],
});
