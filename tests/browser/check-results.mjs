// Require a Playwright JSON report of passing tests without skips, failures
// or retries: node tests/browser/check-results.mjs <report> [expected count].
import { readFileSync } from 'node:fs';

const [report, count] = process.argv.slice(2);
const { stats } = JSON.parse(readFileSync(report, 'utf8'));
const expected = count === undefined ? stats.expected > 0 : stats.expected === Number(count);
if (!expected || stats.skipped || stats.unexpected || stats.flaky) {
  throw new Error(`Browser tests must all pass without skips or retries: ${JSON.stringify(stats)}`);
}
