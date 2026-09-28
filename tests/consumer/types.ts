// The facade's types as an application sees them, installed as the
// bend-trace-context package: the checker must accept every use below and
// refuse each line marked @ts-expect-error. tsconfig.json checks this file
// without the DOM or Node types, which these two entries do not need.
// Nothing here runs.
import * as TC from 'bend-trace-context';
import { continueOrStartRequest, extractRequest, requestFields, requestHeaders } from 'bend-trace-context/node';

declare const request: { rawHeaders: string[] };
// A source with WebCrypto's interface, as an application may write one.
const source: TC.RandomSource = { getRandomValues: (array: Uint32Array) => array };

const fields: TC.Fields = [['traceparent', '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01']];
const extraction: TC.Extraction = TC.extract(fields, { limits: TC.limits({ tracestateOutput: 1024 }) });
const kept: TC.IncomingContext | TC.OutgoingContext | null = extraction.context;
const service: TC.Service = TC.continueOrStart(extraction, { reception: 'continue', sampling: 'inherit' });
const origin: TC.Origin | null = service.origin;
const sent: TC.Sent = TC.send(service, [['content-type', 'application/json']], { policy: 'strict' });
const headers: readonly (readonly [string, string])[] = sent.fields;
const operation: string | null = sent.operation === null ? null : sent.operation.traceparent;

const local: TC.LocalContext = TC.root({ crypto: source });
const unavailable: TC.LocalContext = TC.child(local, { sampling: 'sampled', crypto: null });
const supplied: TC.LocalContext = TC.fromIds('4bf92f3577b34da6a3ce929d0e0e4736', '00f067aa0ba902b7', { sampled: true });
const own: TC.Service = TC.setState(service, 'fw529a3039', 'cHJpbWFyeQ');
const value: string | null = TC.getState(own, 'fw529a3039');
const withState: TC.OutgoingContext = TC.outgoing(local, { state: extraction.incoming });
const injection: TC.Injection = TC.inject(withState, []);
const forwarding: TC.Forwarding = extraction.incoming === null ? { ok: false, error: 'none' }
  : TC.forward(extraction.incoming, []);
const cleared: TC.FrozenFields = TC.clear(headers);
const inspection: TC.Inspection = TC.inspectTraceparent('00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01');
const generationError: TC.GenerationError = new TC.GenerationError('ExhaustedSpanId');
const reason: string = generationError.reason;

const nodeFields: Array<[string, string]> = requestFields(request);
const nodeExtraction: TC.Extraction = extractRequest(request);
const nodeService: TC.Service = continueOrStartRequest(request, { policy: 'lenient', base: null });
const outgoingHeaders: Record<string, string | string[]> = requestHeaders(sent.fields);

// @ts-expect-error: a reception is 'continue' or 'restart'.
TC.continueOrStart(extraction, { reception: 'join' });
// @ts-expect-error: a policy is 'lenient' or 'strict'.
TC.send(service, [], { policy: 'loose' });
// @ts-expect-error: fields are [name, value] pairs.
TC.extract([['traceparent']]);
// @ts-expect-error: a service is not an extraction.
TC.continueOrStart(service);
// @ts-expect-error: the state of a received context is not edited.
TC.setState(extraction.incoming, 'key', 'value');
// @ts-expect-error: handles are read-only.
local.traceId = '0af7651916cd43dd8448eb211c80319c';
// @ts-expect-error: a received request has its raw header lines.
requestFields({ headers: {} });

export { cleared, forwarding, injection, inspection, kept, nodeExtraction, nodeFields, nodeService, operation, origin,
  outgoingHeaders, reason, supplied, unavailable, value };
