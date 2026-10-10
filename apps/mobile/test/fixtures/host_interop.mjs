// Real Host, Worker and durable Pi submissions; Flutter supplies the transport.
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { join, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const execute = promisify(execFile);

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
  const program = `import json,sys
from pathlib import Path
from research_agent.application.job_monitor import bind
root=Path(sys.argv[1])
bind(root, {'job_id':'job_fixture','node_id':None,'node_revision':None}, 'fixture_session')
path=next((root/'operations/monitors').glob('*/binding.json'))
row=json.loads(path.read_text());row['last_state']='failed';row['sequence']=1
path.write_text(json.dumps(row))
events=path.parent/'events';events.mkdir()
(events/'event_fixture.json').write_text(json.dumps({'sequence':1,'observed_at':'2026-10-09T00:00:00Z','error':'fixture execution failed'}))
deliveries=path.parent/'deliveries';deliveries.mkdir()
(deliveries/'event_fixture.json').write_text(json.dumps({'schema_version':'coragent-job-monitor-delivery/2','event_id':'event_fixture','session_id':'fixture_session','request_id':'fixture-wake','delivered':False,'error':'fixture delivery paused'}))`;
  await execute(process.env.CORAGENT_PYTHON, ['-c', program, join(workspaceRoot, 'ts_001')]);
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
