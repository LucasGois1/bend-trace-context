// Playwright for the independent browser consumer: BEND_BROWSER_CONSUMER
// names the directory of its bundled page, and BEND_BROWSER_EVIDENCE the
// directory for its results. scripts/test-consumer.sh browser sets both.
import { defineConfig } from '@playwright/test';
import { projects, servers } from '../browser/engines.mjs';

const page = process.env.BEND_BROWSER_CONSUMER;
const evidence = process.env.BEND_BROWSER_EVIDENCE;
if (!page || !evidence) throw new Error('Set BEND_BROWSER_CONSUMER and BEND_BROWSER_EVIDENCE.');

export default defineConfig({
  testDir: '.',
  testMatch: 'browser.spec.mjs',
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  reporter: [['list'], ['json', { outputFile: `${evidence}/browser-results.json` }]],
  outputDir: `${evidence}/browser-traces`,
  use: { baseURL: 'http://127.0.0.1:4173', trace: 'retain-on-failure' },
  projects,
  webServer: servers(page),
});
