// Optional cross-repository fixture. It runs the real Host and a deterministic
// Pi bridge peer; Flutter owns a local transparent WebSocket transport.
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const source = process.env.TSPI_SOURCE;
const root = process.argv[2];
if (!source || !root?.startsWith('/home/iaw/debug/tspi-test-env/')) {
  throw new Error('Set TSPI_SOURCE and provide an isolated debug directory');
}
const { startTspiHost } = await import(pathToFileURL(join(source, 'apps/app-server/tspi-host.mjs')));
const { connectHost } = await import(pathToFileURL(join(source, 'apps/app-server/tspi-host-client.mjs')));
const workspaceRoot = join(root, 'projects');
const workspace = join(workspaceRoot, 'ts_001');
const socketPath = join(root, 'host.sock');
await mkdir(workspace, { recursive: true });
await writeFile(join(workspace, 'workspace.json'), JSON.stringify({ schema_version: 'research-workspace/1' }));
const host = await startTspiHost({ socketPath, workspaceRoot, stateRoot: join(root, 'state'),
  serverId: '123e4567-e89b-42d3-a456-426614174000', bridgeToken: 'debug-bridge-token', monitorPollMs: 0 });
let count = 0;
let snapshot = { messages: [], is_streaming: false, turn_id: null, model: { provider: 'test', id: 'one' },
  pending_messages: false, streaming_message: null, online: true, read_only: false, can_prompt: true };
const bridge = await connectHost({ socketPath, onRequest: async (method, params) => {
  if (method === 'bridge/models') return { models: [{ provider: 'test', id: 'one', name: 'One' }, { provider: 'test', id: 'two', name: 'Two' }] };
  if (method === 'bridge/input') {
    count++;
    snapshot = { ...snapshot, is_streaming: true, turn_id: 'turn-1', messages: [...snapshot.messages,
      { role: 'user', content: params.text, clientMessageId: params.client_message_id, timestamp: Date.now() }] };
  } else if (method === 'bridge/interrupt') {
    snapshot = { ...snapshot, is_streaming: false, turn_id: null };
  } else if (method === 'bridge/model-select') {
    snapshot = { ...snapshot, model: { provider: params.provider, id: params.model_id } };
  } else { throw new Error(`Unexpected bridge method ${method}`); }
  await bridge.request('bridge/event', { workspace_id: 'ts_001', session_id: 'session-1', snapshot });
  return { accepted: true, state: 'submitted', client_message_id: params.client_message_id, model: snapshot.model };
} });
await bridge.request('bridge/hello', { token: 'debug-bridge-token', workspace_id: 'ts_001', session_id: 'session-1',
  cwd: workspace, version: 3, snapshot });
console.log(JSON.stringify({ socketPath }));
process.stdin.once('data', async () => {
  bridge.close();
  await host.close();
  console.log(JSON.stringify({ delivered: count }));
  process.stdin.pause();
});
