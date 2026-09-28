// Compile a Bend file of this repository with the pinned compiler, as the
// JavaScript tests need their fixtures and modules compiled.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../../', import.meta.url));

// Compile `source` into `output`, both relative to the repository root, and
// return the output's absolute path. The extension of `output` selects the
// compiler's target: `.js` for a program, `.mjs` for an ES module.
export function compile(source, output) {
  const path = join(root, output);
  mkdirSync(dirname(path), { recursive: true });
  const result = spawnSync(join(root, 'bend'), [source, '-o', path], { cwd: root, encoding: 'utf8', timeout: 60000 });
  assert.equal(result.status, 0, `${source}: ${result.stdout}\n${result.stderr}`);
  return path;
}
