import { defineConfig } from '@playwright/test';
import { projects, servers } from './tests/browser/engines.mjs';

export default defineConfig({
  testDir: './tests/browser',
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  reporter: [['list'], ['json', { outputFile: 'build/javascript/browser-results.json' }]],
  outputDir: 'build/javascript/browser-traces',
  use: { baseURL: 'http://127.0.0.1:4173', trace: 'retain-on-failure' },
  projects,
  webServer: servers(),
});
