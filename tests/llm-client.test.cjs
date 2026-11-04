const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');

let plan = [];
const sent = [];
const http = {
  RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 'string' },
  createHttp: () => {
    const events = {};
    return {
      on: (name, callback) => { events[name] = callback; },
      destroy: () => {},
      requestInStream: async (url, options) => {
        sent.push({ url, header: options.header, body: JSON.parse(options.extraData) });
        const step = plan.shift();
        if (step === undefined) throw new Error(`unexpected request to ${url}`);
        if (step.fail !== undefined) throw new Error(step.fail);
        (step.chunks || []).forEach(chunk => events.dataReceive(Uint8Array.from(Buffer.from(chunk)).buffer));
        if (step.errorAfter !== undefined) throw new Error(step.errorAfter);
        return step.status === undefined ? 200 : step.status;
      }
    };
  }
};
const stubs = name => {
  if (name === '@kit.NetworkKit') return { http };
  if (name === '@kit.ArkTS') return { util: { TextDecoder: { create: () => {
    const decoder = new TextDecoder();
    return { decodeToString: (bytes, options) => decoder.decode(bytes, options) };
  } } } };
  if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info: () => {}, error: () => {} } };
  throw Error(`Unexpected dependency ${name}`);
};
const attachment = { AttachmentService: { content: text => text } };
const cache = new Map();
function load(file) {
  const absolute = path.resolve(root, file + '.ets');
  if (cache.has(absolute)) return cache.get(absolute);
  const result = {};
  cache.set(absolute, result);
  const compiled = ts.transpileModule(fs.readFileSync(absolute, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInNewContext(compiled, { exports: result, Uint8Array, setTimeout, clearTimeout,
    require: name => {
      if (!name.startsWith('.')) return stubs(name);
      const id = path.relative(root, path.resolve(path.dirname(absolute), name)).split(path.sep).join('/');
      if (id === 'services/AttachmentService') return attachment;
      return load(id);
    } });
  return result;
}
const { LlmClient } = load('services/LlmClient');
const { AgentCandidates } = load('services/AgentCandidates');

const openAi = { label: '主配置', model: 'primary-model', baseUrl: 'https://primary.invalid/v1', apiKey: 'k1', kind: 'openai' };
const anthropic = { label: '备用配置', model: 'backup-model', baseUrl: 'https://backup.invalid/v1', apiKey: 'k2', kind: 'anthropic' };
const request = { systemInstruction: 'SYS', featureId: 'home', history: [], prompt: '你好', retrieval: { context: '' } };
const openAiEvent = text => `data: ${JSON.stringify({ choices: [{ delta: { content: text } }] })}\n\n`;
const anthropicEvent = text => `event: content_block_delta\ndata: ${JSON.stringify({ type: 'content_block_delta', index: 0,
  delta: { type: 'text_delta', text: text } })}\n\n`;
const sinkOf = () => {
  const seen = { text: '', notices: [], phases: [], cancelled: false };
  return { seen, target: {
    isCancelled: () => seen.cancelled,
    onDelta: text => { seen.text += text; },
    onProgress: phase => seen.phases.push(phase),
    onNotice: text => seen.notices.push(text)
  } };
};
const failure = { status: 500, chunks: [JSON.stringify({ error: { message: 'primary down' } })] };

(async () => {
  // 1. 同一配置内的重试：第一次 5xx，重试成功，不触发降级
  {
    plan = [failure, { chunks: [openAiEvent('重试成功')] }];
    sent.length = 0;
    const state = sinkOf();
    const client = new LlmClient([openAi], 1, 1);
    await client.generate(request, state.target);
    assert.equal(sent.length, 2, 'one retry before giving up');
    assert.equal(sent[0].url, sent[1].url);
    assert.equal(state.seen.text, '重试成功');
    assert.equal(state.seen.notices.length, 0, 'a retry inside the same profile is not a fallback');
  }

  // 2. 重试仍失败 → 切换到备用配置，并如实提示
  {
    plan = [failure, failure, { chunks: [anthropicEvent('备用回答')] }];
    sent.length = 0;
    const state = sinkOf();
    const client = new LlmClient([openAi, anthropic], 1, 1);
    await client.generate(request, state.target);
    assert.equal(sent.length, 3, 'primary tried twice, then the backup once');
    assert.equal(sent[2].url, 'https://backup.invalid/v1/messages', 'the backup uses its own wire format');
    assert.equal(sent[2].header['x-api-key'], 'k2');
    assert.ok(sent[2].body.system.startsWith('SYS'), 'the system instruction is carried into the backup request');
    assert.ok(sent[2].body.system.includes('home'), 'workspace context is rebuilt for the backup provider');
    assert.equal(state.seen.text, '备用回答');
    assert.equal(state.seen.notices.length, 1);
    assert.ok(state.seen.notices[0].includes('已切换到备用配置'), 'the switch is reported to the user');
    assert.ok(state.seen.notices[0].includes('备用配置'));
    assert.equal(client.name, 'backup-model', 'the gateway reports the model actually answering');
  }

  // 3. 超时不重试（一次要等满 90 秒），直接降级
  {
    plan = [{ fail: 'Operation timeout' }, { chunks: [anthropicEvent('备用接管')] }];
    sent.length = 0;
    const state = sinkOf();
    const client = new LlmClient([openAi, anthropic], 1, 1);
    await client.generate(request, state.target);
    assert.equal(sent.length, 2, 'a timeout must not be retried on the same profile');
    assert.equal(state.seen.text, '备用接管');
  }

  // 3b. 降级只作用于当前回合：下一个回合重回主配置，主配置恢复后自动用回
  {
    plan = [failure, failure, { chunks: [anthropicEvent('备用接管')] },
      { chunks: [openAiEvent('主配置恢复')] }];
    sent.length = 0;
    const state = sinkOf();
    const client = new LlmClient([openAi, anthropic], 1, 1);
    await client.generate(request, state.target);
    assert.equal(client.name, 'backup-model');
    await client.generate(request, state.target);
    assert.equal(sent.length, 4, 'the next turn starts from the primary again');
    assert.equal(sent[3].url, 'https://primary.invalid/v1/chat/completions');
    assert.equal(state.seen.text, '备用接管主配置恢复');
  }

  // 4. 已经流出内容后失败：不重试、不切换，避免同一段话被写两遍
  {
    plan = [{ chunks: [openAiEvent('部分回答')], errorAfter: 'socket hang up' }];
    sent.length = 0;
    const state = sinkOf();
    const client = new LlmClient([openAi, anthropic], 1, 1);
    await assert.rejects(client.generate(request, state.target), /socket hang up/);
    assert.equal(sent.length, 1, 'no silent retry after the user already saw text');
    assert.equal(state.seen.text, '部分回答');
    assert.equal(state.seen.notices.length, 0);
  }

  // 5. 只有一组配置时失败照实抛出
  {
    plan = [failure, failure];
    sent.length = 0;
    const client = new LlmClient([openAi], 1, 1);
    await assert.rejects(client.generate(request, sinkOf().target), /primary down/);
    assert.equal(sent.length, 2);
  }

  // 6. 没有可用配置时给出配置引导
  {
    const client = new LlmClient([]);
    await assert.rejects(client.generate(request, sinkOf().target), /配置模型 API/);
  }

  // 7. 降级链顺序：当前选中优先，其余可用配置按保存顺序跟随，不可用的被跳过
  {
    const archive = { version: 1, activeId: 'b', items: [
      { id: 'a', name: 'A', baseUrl: 'https://a.example/v1', model: 'a-model', apiKey: 'a' },
      { id: 'b', name: 'B', baseUrl: 'https://b.example/v1', model: 'b-model', apiKey: 'b', provider: 'anthropic' },
      { id: 'c', name: '', baseUrl: '', model: '', apiKey: '' },
      { id: 'd', name: 'D', baseUrl: 'https://d.example/v1', model: 'd-model', apiKey: 'd' }
    ] };
    const chain = AgentCandidates.build(archive);
    assert.deepEqual(Array.from(chain).map(item => item.model), ['b-model', 'a-model', 'd-model']);
    assert.equal(chain[0].kind, 'anthropic');
    assert.equal(chain[1].label, 'A');
    assert.equal(AgentCandidates.build({ version: 1, activeId: '', items: [] }).length, 0);
  }

  console.log('PASS: retry, fallback chain, timeout policy, no replay after streaming, single-profile failure, empty config and chain ordering.');
})().catch(error => { console.error(error); process.exitCode = 1; });