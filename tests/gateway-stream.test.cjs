const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/OpenAiCompatibleGateway.ets'), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS,
  target: ts.ScriptTarget.ES2020 } }).outputText;
let wire = '';
let status = 200;
let destroyed = 0;
let sentOptions;
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
        const bytes = Buffer.from(wire);
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
const exported = {};
vm.runInNewContext(compiled, { exports: exported, Uint8Array,
  require: name => {
    if (name === '@kit.NetworkKit') return { http };
    if (name === '@kit.ArkTS') return { util: { TextDecoder: { create: () => {
      const decoder = new TextDecoder();
      return { decodeToString: (bytes, options) => decoder.decode(bytes, options) };
    } } } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info: () => {}, error: () => {} } };
    if (name === '../config/ApiConfig') return { ApiConfig: { maxHistoryMessages: 12, maxMessageChars: 4000, requestTimeoutMs: 90000 } };
    if (name === './AttachmentService') return { AttachmentService: { content: (text, attachments) => attachments.length ?
      [{ type: 'text', text: text + JSON.stringify(attachments.filter(a => a.kind === 'document')) },
        ...attachments.filter(a => a.kind === 'image').map(a => ({ type: 'image_url', image_url: { url: 'data:image/jpeg;base64,test-' + a.id } }))] : text } };
    throw Error(`Unexpected dependency ${name}`);
  }
});
const gateway = new exported.OpenAiCompatibleGateway({ baseUrl: 'https://example.invalid/v1', model: 'test', apiKey: '' });
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
  console.log('PASS: UTF-8 split SSE, analysis status, private reasoning isolation, JSON fallback, errors, cancellation.');
})().catch(error => { console.error(error); process.exitCode = 1; });
