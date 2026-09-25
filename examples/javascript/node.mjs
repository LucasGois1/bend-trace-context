import { inspectTraceparent } from '../../packages/trace-context/javascript/codec.mjs';

const wire = process.argv[2] ?? '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01';
const result = inspectTraceparent(wire);
console.log(JSON.stringify(result));
if (!result.ok) process.exitCode = 1;
