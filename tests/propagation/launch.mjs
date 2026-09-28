// Start a compiled Bend HTTP program and wait until it prints its listening
// URL, as bend-kit's HTTP server does. The returned handle stops the program
// and gives what it printed so far.
import { spawn } from 'node:child_process';

export const launch = (path, url) => new Promise((resolve, reject) => {
  const child = spawn(path, [], { stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
  child.stderr.setEncoding('utf8').on('data', chunk => { stderr += chunk; });
  const handle = { stop: () => child.kill('SIGTERM'), stdout: () => stdout };
  const timeout = setTimeout(() => reject(new Error(`${path} did not start: ${stderr}`)), 10000);
  const poll = () => {
    if (stdout.includes(url)) {
      clearTimeout(timeout);
      resolve(handle);
    } else if (child.exitCode !== null) {
      clearTimeout(timeout);
      reject(new Error(`${path} exited (${child.exitCode}): ${stderr}`));
    } else {
      setTimeout(poll, 20);
    }
  };
  poll();
});
