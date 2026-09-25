import { test as base, expect } from '@playwright/test';

export const test = base.extend({
  runtimeEvidence: [async ({ browser, browserName }, use, testInfo) => {
    await testInfo.attach('runtime.json', {
      body: JSON.stringify({ node: process.version, browser: browserName, version: browser.version() }),
      contentType: 'application/json',
    });
    await use();
  }, { auto: true }],
});
export { expect };
