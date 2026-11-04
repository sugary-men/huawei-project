const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
let wire = '';
let status = 200;
let lastRequest;
const http = {
  RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 'string' },
  createHttp: () => {
    const events = {};
    return {
      on: (name, callback) => { events[name] = callback; },
      destroy: () => {},
      requestInStream: async (url, options) => {
        lastRequest = { url, options, body: JSON.parse(options.extraData) };
        const bytes = Buffer.from(wire);
        for (let i = 0; i < bytes.length; i += 5) events.dataReceive(Uint8Array.from(bytes.subarray(i, i + 5)).buffer);
        return status;
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
      return load(path.relative(root, path.resolve(path.dirname(absolute), name)).split(path.sep).join('/'));
    } });
  return result;
}
const { AnthropicProvider } = load('services/providers/AnthropicProvider');
const { ProviderFactory } = load('services/ProviderFactory');

const sse = payload => `event: ${payload.type}\ndata: ${JSON.stringify(payload)}\n\n`;
const delta = (index, deltaPayload) => sse({ type: 'content_block_delta', index, delta: deltaPayload });
const settings = { baseUrl: 'https://api.anthropic.invalid/v1', model: 'claude-test', apiKey: 'test-key' };
const tools = [{ type: 'function', function: { name: 'read_workspace', description: '读取面板',
  parameters: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] } } }];
const sink = () => {
  const seen = { text: '', analyzing: 0 };
  return { seen, target: { isCancelled: () => false, onDelta: value => { seen.text += value; },
    onAnalyzing: () => { seen.analyzing++; } } };
};

(async () => {
  // 1. 请求线格式：URL、鉴权头、system 与工具 schema 都按 Messages API 组织
  {
    const provider = new AnthropicProvider(settings);
    const state = sink();
    wire = delta(0, { type: 'text_delta', text: '你好' }) + sse({ type: 'message_stop' });
    const turn = await provider.complete('SYS', [{ role: 'user', content: 'hi' }], tools, state.target);
    assert.equal(lastRequest.url, 'https://api.anthropic.invalid/v1/messages');
    assert.equal(lastRequest.options.header['x-api-key'], 'test-key');
    assert.equal(lastRequest.options.header['anthropic-version'], '2023-06-01');
    assert.equal(lastRequest.body.system, 'SYS');
    assert.equal(lastRequest.body.max_tokens, 4096);
    assert.equal(lastRequest.body.stream, true);
    assert.deepEqual(lastRequest.body.messages, [{ role: 'user', content: [{ type: 'text', text: 'hi' }] }]);
    assert.equal(lastRequest.body.tools[0].name, 'read_workspace');
    assert.equal(lastRequest.body.tools[0].input_schema.properties.id.type, 'string');
    assert.equal(lastRequest.body.tools[0].function, undefined, 'Anthropic tools have no nested function object');
    assert.equal(turn.content, '你好');
    assert.equal(state.seen.text, '你好');
    assert.equal(turn.calls.length, 0);
  }

  // 2. 工具调用：content_block_start + input_json_delta 累积成 JSON 参数
  {
    const provider = new AnthropicProvider(settings);
    const state = sink();
    wire = sse({ type: 'content_block_start', index: 1, content_block: { type: 'tool_use', id: 'toolu_1', name: 'read_workspace' } }) +
      delta(1, { type: 'input_json_delta', partial_json: '{"id":' }) +
      delta(1, { type: 'input_json_delta', partial_json: '"panel"}' }) +
      sse({ type: 'message_stop' });
    const turn = await provider.complete('SYS', [{ role: 'user', content: 'go' }], tools, state.target);
    assert.equal(turn.calls.length, 1);
    assert.equal(turn.calls[0].id, 'toolu_1');
    assert.equal(turn.calls[0].name, 'read_workspace');
    assert.equal(turn.calls[0].arguments, '{"id":"panel"}');
  }

  // 3. 助手工具调用与工具结果按 tool_use / tool_result 块回传，连续结果合并成一条 user 消息
  {
    const provider = new AnthropicProvider(settings);
    const state = sink();
    wire = delta(0, { type: 'text_delta', text: '完成' }) + sse({ type: 'message_stop' });
    const messages = [
      { role: 'user', content: 'go' },
      { role: 'assistant', content: '', toolCalls: [{ id: 'toolu_1', name: 'read_workspace', arguments: '{"id":"panel"}' }] },
      { role: 'tool', content: '{"ok":true}', toolCallId: 'toolu_1' },
      { role: 'tool', content: '{"ok":false}', toolCallId: 'toolu_2' }
    ];
    await provider.complete('SYS', messages, tools, state.target);
    const sent = lastRequest.body.messages;
    assert.deepEqual(sent[1].content[0], { type: 'tool_use', id: 'toolu_1', name: 'read_workspace', input: { id: 'panel' } });
    assert.equal(sent[2].role, 'user');
    assert.equal(sent[2].content.length, 2, 'consecutive tool results belong to one user message');
    assert.deepEqual(sent[2].content[0], { type: 'tool_result', tool_use_id: 'toolu_1', content: '{"ok":true}' });
    assert.deepEqual(sent[2].content[1], { type: 'tool_result', tool_use_id: 'toolu_2', content: '{"ok":false}' });
  }

  // 4. 思考增量只上报“正在分析”，不进正文
  {
    const provider = new AnthropicProvider(settings);
    const state = sink();
    wire = delta(0, { type: 'thinking_delta', thinking: 'internal' }) + delta(0, { type: 'text_delta', text: '正文' }) + sse({ type: 'message_stop' });
    const turn = await provider.complete('SYS', [{ role: 'user', content: 'go' }], tools, state.target);
    assert.equal(state.seen.analyzing, 1);
    assert.equal(turn.content, '正文');
    assert.equal(state.seen.text.includes('internal'), false);
  }

  // 5. 非流式 JSON 兼容
  {
    const provider = new AnthropicProvider(settings);
    const state = sink();
    wire = JSON.stringify({ content: [{ type: 'text', text: 'JSON 回答' },
      { type: 'tool_use', id: 'toolu_json', name: 'read_workspace', input: { id: 'x' } }] });
    const turn = await provider.complete('SYS', [{ role: 'user', content: 'go' }], tools, state.target);
    assert.equal(turn.content, 'JSON 回答');
    assert.equal(turn.calls[0].id, 'toolu_json');
    assert.equal(turn.calls[0].arguments, '{"id":"x"}');
  }

  // 6. HTTP 与流内错误照实抛出
  {
    const provider = new AnthropicProvider(settings);
    const state = sink();
    status = 500;
    wire = JSON.stringify({ error: { type: 'api_error', message: 'upstream failed' } });
    await assert.rejects(provider.complete('SYS', [{ role: 'user', content: 'go' }], tools, state.target), /upstream failed/);
    status = 200;
    wire = sse({ type: 'error', error: { type: 'overloaded_error', message: 'overloaded' } });
    await assert.rejects(provider.complete('SYS', [{ role: 'user', content: 'go' }], tools, state.target), /overloaded/);
    wire = sse({ type: 'message_stop' });
    await assert.rejects(provider.complete('SYS', [{ role: 'user', content: 'go' }], tools, state.target), /没有返回回答内容/);
  }

  // 7. 服务商判定：显式优先，其次按地址推断
  assert.equal(ProviderFactory.kindFor('https://api.anthropic.com/v1', ''), 'anthropic');
  assert.equal(ProviderFactory.kindFor('https://proxy.example.com/v1/messages', ''), 'anthropic');
  assert.equal(ProviderFactory.kindFor('https://api.deepseek.com/v1', ''), 'openai');
  assert.equal(ProviderFactory.kindFor('https://api.deepseek.com/v1', 'anthropic'), 'anthropic');
  assert.equal(ProviderFactory.kindFor('https://api.anthropic.com/v1', 'openai'), 'openai');
  assert.equal(new (load('services/providers/OpenAiProvider').OpenAiProvider)({ baseUrl: 'https://a.example/v1', model: 'm', apiKey: '' }).kind, 'openai');

  console.log('PASS: Anthropic wire format, tool_use/tool_result blocks, thinking isolation, JSON fallback, errors and provider detection.');
})().catch(error => { console.error(error); process.exitCode = 1; });