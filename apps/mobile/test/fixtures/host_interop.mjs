// Real Host, Worker and durable Pi submissions; Flutter supplies the transport.
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { join, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const source = process.env.CORAGENT_SOURCE;
const root = resolve(process.argv[2]);
const testRoot = process.env.CORAGENT_TEST_ROOT;
const piRoot = process.env.CORAGENT_TEST_PI_RUNTIME_ROOT;
const socketRoot = join(process.env.CORAGENT_TEST_SOCKET_ROOT, 'p');
if (!source || !testRoot || relative(testRoot, root).startsWith('..') || !piRoot || !process.env.CORAGENT_PYTHON) {
  throw new Error('Set CORAGENT_SOURCE, CORAGENT_TEST_ROOT, CORAGENT_TEST_PI_RUNTIME_ROOT and CORAGENT_PYTHON');
}
const load = path => import(pathToFileURL(join(source, path)));
const { startCoRAgentHost } = await load('apps/agent/host/server.mjs');
const { createCoRAgentHarnessBackend } = await load('apps/agent/pi/backend.mjs');
const { create_workspace_initializer } = await load('apps/agent/host/workspace.mjs');
const workspaceRoot = join(root, 'projects');
const socketPath = join(socketRoot, 'host.sock');
const agentDir = join(root, 'agent');
process.env.PI_CODING_AGENT_DIR = agentDir;
process.env.PYTHONDONTWRITEBYTECODE = '1';
let host, backend, count = 0, stopping = false;
const server = createServer(async (req, res) => {
  for await (const _ of req) {} // Drain the streaming request before responding.
  count++;
  console.log(JSON.stringify({ stage: 'model-request', count }));
  res.writeHead(200, { 'Content-Type': 'text/event-stream' });
  res.write(`data: ${JSON.stringify({ id: `response-${count}`, object: 'chat.completion.chunk', created: 1,
    model: 'two', choices: [{ index: 0, delta: { role: 'assistant', content: 'Working' }, finish_reason: null }] })}\n\n`);
  // Keep the real model turn active until the phone's targeted interrupt.
});
async function stop() {
  if (stopping) return;
  stopping = true;
  await host?.close();
  await backend?.close();
  await rm(socketRoot, {recursive:true, force:true});
  server.closeAllConnections();
  await new Promise(done => server.close(done));
  process.stdin.pause();
}
process.once('SIGTERM', () => stop().then(() => process.exit(0)));
process.once('SIGINT', () => stop().then(() => process.exit(0)));
try {
  await mkdir(agentDir, { recursive: true });
  await mkdir(socketRoot, { recursive: true });
  await new Promise(done => server.listen(0, '127.0.0.1', done));
  await writeFile(join(agentDir, 'models.json'), JSON.stringify({ providers: { test: {
    baseUrl: `http://127.0.0.1:${server.address().port}/v1`, apiKey: 'fixture-only', api: 'openai-completions',
    models: ['one', 'two'].map(id => ({ id, name: id, reasoning: false, input: ['text'],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 200000, maxTokens: 4096 })),
  } } }));
  const initializer = create_workspace_initializer();
  await initializer.initialize_workspace({ workspace_root: join(workspaceRoot, 'ts_001'), workspace_id: 'ts_001', workspace_mode: 'research' });
  await initializer.admit_workspace(join(workspaceRoot, 'ts_001'));
  await writeFile(join(workspaceRoot, 'ts_001', 'inputs', 'fixture.xyz'), '2\nfixture\nC 0 0 0\nO 1.2 0 0\n');
  backend = await createCoRAgentHarnessBackend({ sourceRoot: piRoot, packageRoot: source, workspaceRoot,
    serverDirectory: socketRoot, sessionDir: join(root, 'sessions'), stateRoot: join(root, 'state'),
    model: { provider: 'test', id: 'one' } });
  await backend.createSession({ workspace_id: 'ts_001', model: { provider: 'test', id: 'one' } });
  host = await startCoRAgentHost({ socketPath, workspaceRoot, stateRoot: join(root, 'state'),
    serverId: '123e4567-e89b-42d3-a456-426614174000', sessionBackend: backend, monitorPollMs: 0 });
  console.log(JSON.stringify({ socketPath }));
  process.stdin.once('data', async () => {
    await stop();
    console.log(JSON.stringify({ delivered: count }));
  });
} catch (error) {
  await stop();
  throw error;
}
