const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
let wire = '';
let status = 200;
let destroyed = 0;
let sentOptions;
let responses = [];
const sentBodies = [];
const http = {
  RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 'string' },
  createHttp: () => {
    const events = {};
    return {
      on: (name, callback) => { events[name] = callback; },
      destroy: () => { destroyed++; },
      requestInStream: async (url, options) => {
        assert.equal(url, 'https://example.invalid/v1/chat/completions');
        sentOptions = options;
        sentBodies.push(JSON.parse(options.extraData));
        const bytes = Buffer.from(responses.length ? responses.shift() : wire);
        // Force UTF-8 and SSE frames to cross arbitrary byte boundaries.
        for (let i = 0; i < bytes.length; i += 7) {
          const part = bytes.subarray(i, i + 7);
          events.dataReceive(Uint8Array.from(part).buffer);
        }
        return status;
      }
    };
  }
};
const attachment = { AttachmentService: { content: (text, attachments) => attachments.length ?
  [{ type: 'text', text: text + JSON.stringify(attachments.filter(a => a.kind === 'document')) },
    ...attachments.filter(a => a.kind === 'image').map(a => ({ type: 'image_url', image_url: { url: 'data:image/jpeg;base64,test-' + a.id } }))] : text } };
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
      const id = path.relative(root, path.resolve(path.dirname(absolute), name)).split(path.sep).join('/');
      if (id === 'services/AttachmentService') return attachment;
      return load(id);
    } });
  return result;
}
const gateway = new (load('services/OpenAiCompatibleGateway').OpenAiCompatibleGateway)({ baseUrl: 'https://example.invalid/v1', model: 'test', apiKey: '' });
const request = { systemInstruction: 'test', featureId: 'home', history: [], prompt: 'test', retrieval: { context: '' } };
const event = delta => `data: ${JSON.stringify({ choices: [{ delta }] })}\r\n\r\n`;
(async () => {
  let content = '';
  const phases = [];
  wire = event({ reasoning_content: 'synthetic-internal-reasoning' }) + event({ reasoning_content: 'more' }) +
    event({ content: '<summary>先列计划。</summary>\n' }) + event({ content: '## 中文标题\n**正文**' }) + 'data: [DONE]\n\n';
  await gateway.generate(request, { isCancelled: () => false, onDelta: value => { content += value; }, onProgress: value => phases.push(value) });
  assert.equal(content, '<summary>先列计划。</summary>\n## 中文标题\n**正文**');
  assert.deepEqual(phases, ['analyzing']);
  assert.equal(content.includes('synthetic-internal-reasoning'), false);
  assert.equal(JSON.parse(sentOptions.extraData).stream, true);
  assert.equal(destroyed, 1);
  wire = JSON.stringify({ choices: [{ message: { content: '普通 JSON 回答' } }] });
  content = '';
  await gateway.generate(request, { isCancelled: () => false, onDelta: value => { content += value; } });
  assert.equal(content, '普通 JSON 回答');
  status = 401;
  wire = JSON.stringify({ error: { message: 'invalid test credential' } });
  await assert.rejects(gateway.generate(request, { isCancelled: () => false, onDelta: () => {} }), /invalid test credential/);
  status = 200;
  wire = event({ reasoning_content: 'synthetic only' }) + 'data: [DONE]\n';
  await assert.rejects(gateway.generate(request, { isCancelled: () => false, onDelta: () => {} }), /没有返回回答内容/);
  let cancelledContent = '';
  await gateway.generate(request, { isCancelled: () => true, onDelta: value => { cancelledContent += value; } });
  assert.equal(cancelledContent, '');
  const calls = [];
  const toolRequest = { ...request, tools: [{ type: 'function', function: { name: 'update_task_panel',
    description: 'test', parameters: { type: 'object', properties: {} } } }], executeTool: async call => {
      calls.push(JSON.parse(JSON.stringify(call)));
      return JSON.stringify({ ok: true, message: '已保存' });
    } };
  responses = [event({ tool_calls: [{ index: 0, id: 'call_1', type: 'function', function: {
    name: 'update_task_panel', arguments: '{"goal":"学习' } }] }) + event({ tool_calls: [{ index: 0,
      function: { arguments: '目标"}' } }] }) + 'data: [DONE]\n', event({ content: '面板已更新。' }) + 'data: [DONE]\n'];
  content = '';
  await gateway.generate(toolRequest, { isCancelled: () => false, onDelta: v => { content += v; } });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].arguments, '{"goal":"学习目标"}');
  assert.equal(calls[0].name, 'update_task_panel');
  assert.match(content, /面板已更新/);
  const followup = sentBodies.at(-1);
  assert.equal(followup.messages.at(-1).role, 'tool');
  assert.equal(followup.messages.at(-1).tool_call_id, 'call_1');
  assert.equal(followup.messages.at(-2).tool_calls[0].function.arguments, calls[0].arguments);
  assert.equal(followup.tools[0].function.name, 'update_task_panel');
  responses = [JSON.stringify({ choices: [{ message: { content: null, tool_calls: [{ id: 'json_call', type: 'function',
    function: { name: 'update_task_panel', arguments: '{}' } }] } }] }), event({ content: 'JSON工具成功' })];
  await gateway.generate(toolRequest, { isCancelled: () => false, onDelta: () => {} });
  assert.equal(calls.at(-1).id, 'json_call');
  const callOrder = [];
  responses = [event({ tool_calls: [
    { index: 1, id: 'second', function: { name: 'read_workspace', arguments: '{}' } },
    { index: 0, id: 'first', function: { name: 'read_workspace', arguments: '{}' } }
  ] }), event({ content: '多工具完成' })];
  await gateway.generate({ ...toolRequest, executeTool: async call => { callOrder.push(call.id); return '{}'; } },
    { isCancelled: () => false, onDelta: () => {} });
  assert.deepEqual(callOrder, ['first', 'second'], 'tool indices must determine execution order');
  let stopped = false;
  const beforeRequests = sentBodies.length;
  responses = [event({ tool_calls: [{ index: 0, id: 'cancel_call', function: { name: 'read_workspace', arguments: '{}' } }] })];
  await gateway.generate({ ...toolRequest, executeTool: async () => { stopped = true; return '{}'; } },
    { isCancelled: () => stopped, onDelta: () => {} });
  assert.equal(sentBodies.length, beforeRequests + 1, 'cancel after a tool must prevent another request');
  responses = Array.from({ length: 5 }, () => event({ tool_calls: [{ index: 0, id: 'loop_call', function: { name: 'read_workspace', arguments: '{}' } }] }));
  await assert.rejects(gateway.generate(toolRequest, { isCancelled: () => false, onDelta: () => {} }), /不可用的工具/);
  assert.equal(sentBodies.at(-1).tools, undefined, 'last round must request a final answer without tools');
  responses = [];
  console.log('PASS: split UTF-8/SSE, reasoning isolation, JSON fallback, errors, streamed tools, tool results, cancellation and bounded rounds.');
})().catch(error => { console.error(error); process.exitCode = 1; });