const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const cache = new Map();
function load(file) {
  const absolute = path.resolve(root, file + '.ets');
  if (cache.has(absolute)) return cache.get(absolute);
  const result = {};
  cache.set(absolute, result);
  const compiled = ts.transpileModule(fs.readFileSync(absolute, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInNewContext(compiled, { exports: result, setTimeout, clearTimeout, setInterval, clearInterval,
    require: name => {
      if (name === '@kit.ArkTS') return { util: { generateRandomUUID: () => 'uuid-test' } };
    if (name === '@kit.CoreFileKit') return { fileIo: {} };
    if (!name.startsWith('.')) throw Error('Unexpected runtime dependency: ' + name);
      return load(path.relative(root, path.resolve(path.dirname(absolute), name)));
    } });
  return result;
}
const { AgentOrchestrator } = load('services/AgentOrchestrator');
const { AgentTurnState } = load('models/AgentTurnModels');
const { WorkspaceService } = load('services/WorkspaceService');
const { FEATURE_CATALOG } = load('config/FeatureCatalog');

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const rag = { search: async () => ({ context: '', sources: [], notice: '' }) };
const input = overrides => Object.assign({ prompt: '你好', featureId: 'home', history: [], retrievalOptions: {},
  attachments: [], attachedSources: [], workspace: WorkspaceService.create('home'), features: FEATURE_CATALOG,
  reviewContext: '' }, overrides);
const recorder = () => {
  const seen = { phases: [], deltas: [], retrieved: 0 };
  return { seen, observer: {
    onPhase: (phase, detail) => seen.phases.push(detail ? `${phase}:${detail}` : phase),
    onDelta: content => seen.deltas.push(content),
    onRetrieved: () => { seen.retrieved++ }
  } };
};
class FakeGateway {
  constructor(script) { this.name = '测试模型'; this.script = script; this.cancelled = 0 }
  cancel() { this.cancelled++ }
  async generate(request, sink) { await this.script(request, sink, this) }
}

(async () => {
  // 1. 正常回合：检索 → 连接 → 生成 → 完成
  {
    const { seen, observer } = recorder();
    const gateway = new FakeGateway(async (request, sink) => {
      assert.equal(request.featureId, 'home');
      assert.equal(request.tools.length, 15, 'the turn still exposes the full registered tool list');
      sink.onDelta('你');
      sink.onDelta('好');
    });
    const turn = new AgentOrchestrator(gateway, rag, observer, async () => '{}', { timeoutMs: 60000, intervalMs: 1000 });
    const result = await turn.run(input());
    assert.equal(result.state, AgentTurnState.complete);
    assert.equal(result.content, '你好');
    assert.equal(result.calls, 0);
    assert.equal(result.empty, false);
    assert.equal(result.notified, false);
    assert.ok(result.finishedAt >= result.startedAt);
    assert.deepEqual(seen.deltas, ['你', '你好'], 'each delta carries the accumulated answer');
    assert.deepEqual(seen.phases, [`${AgentTurnState.retrieving}:正在检索资料`, AgentTurnState.connecting,
      AgentTurnState.answering], 'in-flight phases advance once; the terminal state comes back in the result');
    assert.equal(seen.retrieved, 1);
    assert.equal(turn.isActive(), false, 'a finished turn is no longer active');
    assert.equal(turn.phase(), AgentTurnState.complete);
  }

  // 2. 模型报错 → failed，保留原因
  {
    const { seen, observer } = recorder();
    const gateway = new FakeGateway(async () => { throw new Error('上游 500') });
    const turn = new AgentOrchestrator(gateway, rag, observer, async () => '{}', { timeoutMs: 60000, intervalMs: 1000 });
    const result = await turn.run(input());
    assert.equal(result.state, AgentTurnState.failed);
    assert.equal(result.reason, '上游 500');
    assert.equal(result.empty, false);
    assert.ok(!seen.phases.some(phase => phase.startsWith(AgentTurnState.failed)),
      'an ordinary model error is reported through the result, not a second terminal phase');
  }

  // 3. 没有内容 → failed，不冒充完成
  {
    const { observer } = recorder();
    const gateway = new FakeGateway(async () => {});
    const turn = new AgentOrchestrator(gateway, rag, observer, async () => '{}', { timeoutMs: 60000, intervalMs: 1000 });
    const result = await turn.run(input());
    assert.equal(result.state, AgentTurnState.failed);
    assert.equal(result.empty, true, 'an empty answer is flagged instead of pretending to be a model error');
    assert.equal(result.timeout, false);
    assert.ok(result.reason.includes('未返回内容'));
  }

  // 3b. HTTP 层先报超时：仍按“响应超时”展示中文说明，不把英文底层错误直接给用户
  {
    const { observer } = recorder();
    const gateway = new FakeGateway(async () => { throw new Error('Operation timeout') });
    const turn = new AgentOrchestrator(gateway, rag, observer, async () => '{}', { timeoutMs: 60000, intervalMs: 1000 });
    const result = await turn.run(input());
    assert.equal(result.state, AgentTurnState.failed);
    assert.equal(result.timeout, true, 'a transport timeout is classified as a turn timeout');
    assert.equal(result.notified, false, 'the page renders it once with the friendly reason');
    assert.ok(result.reason.includes('等待 测试模型 返回超过'), 'the raw English error never reaches the bubble');
    assert.ok(!result.reason.includes('Operation timeout'));
  }

  // 4. 工具调度：阶段、次数与回填
  {
    const { seen, observer } = recorder();
    const executed = [];
    const gateway = new FakeGateway(async (request, sink) => {
      await request.executeTool({ id: 'a', name: 'read_workspace', arguments: '{}' });
      await request.executeTool({ id: 'b', name: 'update_task_panel', arguments: '{"goal":"x"}' });
      sink.onDelta('完成');
    });
    const turn = new AgentOrchestrator(gateway, rag, observer, async call => {
      executed.push(call.name);
      return JSON.stringify({ ok: true, message: 'ok' });
    }, { timeoutMs: 60000, intervalMs: 1000 });
    const result = await turn.run(input());
    assert.equal(result.state, AgentTurnState.complete);
    assert.equal(result.calls, 2);
    assert.deepEqual(executed, ['read_workspace', 'update_task_panel']);
    assert.ok(seen.phases.some(phase => phase.startsWith(`${AgentTurnState.tool}:正在执行读取任务面板`)),
      'tool phases use the registry label');
    assert.ok(seen.phases.some(phase => phase.startsWith(`${AgentTurnState.tool}:正在执行更新任务面板与产物`)));
    assert.ok(seen.phases.indexOf(AgentTurnState.answering) > seen.phases.findIndex(p => p.startsWith(AgentTurnState.tool)),
      'the turn returns to answering after a tool');
  }

  // 5. 主动停止：令牌先失效，run 立即返回 cancelled，且已上报过终态
  {
    const { seen, observer } = recorder();
    const gateway = new FakeGateway(async () => { await new Promise(() => {}) });
    let executed = false;
    const turn = new AgentOrchestrator(gateway, rag, observer, async () => { executed = true; return '{}' },
      { timeoutMs: 60000, intervalMs: 1000 });
    const pending = turn.run(input());
    await sleep(5);
    assert.equal(turn.isActive(), true);
    turn.stop('已停止生成。');
    const result = await pending;
    assert.equal(result.state, AgentTurnState.cancelled);
    assert.equal(result.reason, '已停止生成。');
    assert.equal(result.notified, true, 'stop already reported through onPhase');
    assert.equal(gateway.cancelled, 1);
    assert.ok(seen.phases.includes(`${AgentTurnState.cancelled}:已停止生成。`));
    assert.equal(executed, false);
  }

  // 6. 超时：终态只上报一次，等待超时后立即返回
  {
    const { seen, observer } = recorder();
    const gateway = new FakeGateway(async () => { await new Promise(() => {}) });
    const turn = new AgentOrchestrator(gateway, rag, observer, async () => '{}',
      { timeoutMs: 40, intervalMs: 5, graceMs: 0 });
    const result = await turn.run(input());
    assert.equal(result.state, AgentTurnState.failed);
    assert.ok(result.reason.includes('超过'), 'timeout reason names the model');
    assert.equal(result.notified, true);
    assert.equal(gateway.cancelled, 1);
    assert.ok(seen.phases.some(phase => phase.startsWith(`${AgentTurnState.failed}:等待 测试模型 返回超过`)));
  }

  // 7. 等待系统授权/用户核对期间不计入模型超时
  {
    const { observer } = recorder();
    const gateway = new FakeGateway(async (request, sink) => {
      await request.executeTool({ id: 'a', name: 'create_calendar_event', arguments: '{}' });
      sink.onDelta('已安排');
    });
    const turn = new AgentOrchestrator(gateway, rag, observer, async () => { await sleep(120); return '{"ok":true}' },
      { timeoutMs: 40, intervalMs: 5, graceMs: 0, blocksTimeout: name => name === 'create_calendar_event' });
    const result = await turn.run(input());
    assert.equal(result.state, AgentTurnState.complete, 'a slow reviewed system action must not trip the model timeout');
  }

  // 8. 不暂停超时的工具仍受截止时刻约束
  {
    const { observer } = recorder();
    const gateway = new FakeGateway(async (request, sink) => {
      await request.executeTool({ id: 'a', name: 'read_workspace', arguments: '{}' });
      sink.onDelta('完成');
    });
    const turn = new AgentOrchestrator(gateway, rag, observer, async () => { await sleep(120); return '{"ok":true}' },
      { timeoutMs: 40, intervalMs: 5, graceMs: 0, blocksTimeout: () => false });
    const result = await turn.run(input());
    assert.equal(result.state, AgentTurnState.failed);
    assert.ok(result.reason.includes('超过'));
  }

  // 9. 停止后到达的工具调用不再执行
  {
    const { observer } = recorder();
    let executed = 0;
    let turn = undefined;
    const gateway = new FakeGateway(async (request) => {
      turn.stop('已停止生成。');
      const receipt = JSON.parse(await request.executeTool({ id: 'late', name: 'read_workspace', arguments: '{}' }));
      assert.equal(receipt.status, 'cancelled', 'late tool calls are rejected without running');
      assert.equal(executed, 0);
    });
    turn = new AgentOrchestrator(gateway, rag, observer, async () => { executed++; return '{"ok":true}' },
      { timeoutMs: 60000, intervalMs: 1000 });
    const result = await turn.run(input());
    assert.equal(result.state, AgentTurnState.cancelled);
  }

  // 10. 停止后可以开始新的回合，旧令牌不会影响新回合
  {
    const { observer } = recorder();
    const gateway = new FakeGateway(async (request, sink) => { sink.onDelta('第二次') });
    const turn = new AgentOrchestrator(gateway, rag, observer, async () => '{}', { timeoutMs: 60000, intervalMs: 1000 });
    turn.stop('清理上一回合');
    const result = await turn.run(input());
    assert.equal(result.state, AgentTurnState.complete);
    assert.equal(result.content, '第二次');
    assert.equal(result.notified, false);
  }

  console.log('PASS: explicit turn state machine, phase order, tool scheduling, stop/timeout convergence, authorization suspension and late-tool rejection.');
})().catch(error => { console.error(error); process.exit(1); });