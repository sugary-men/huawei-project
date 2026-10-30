const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets'), cache = new Map();
const files = new Map(), dirs = new Map(), descriptors = new Map(), prefs = new Map();
const plain = v => JSON.parse(JSON.stringify(v));
let sequence = 1, failWrites = false, now = Date.parse('2030-01-07T08:00:00Z'), gatewayHook;
class Clock extends Date { constructor(...args) { super(...(args.length ? args : [now])); } static now() { return now; } }
const fileIo = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 }, accessSync: p => files.has(p) || dirs.has(p),
  readTextSync(p) { if (!files.has(p)) throw Error('missing'); return files.get(p); },
  mkdirSync(p) { if (dirs.has(p)) throw Error('exists'); dirs.set(p, now / 1000); },
  rmdirSync(p) { if (!dirs.has(p)) throw Error('missing'); dirs.delete(p); }, statSync: p => ({ mtime: dirs.get(p), size: (files.get(p) || '').length }),
  openSync(p) { if (failWrites) throw Error('disk full'); const file = { fd: sequence++ }; descriptors.set(file.fd, p); return file; },
  writeSync(fd, text) { files.set(descriptors.get(fd), text); return text.length; }, fsyncSync() {}, closeSync() {},
  copyFileSync(a, b) { if (!files.has(a)) throw Error('missing source'); files.set(b, files.get(a)); },
  renameSync(a, b) { if (!files.has(a)) throw Error('missing temp'); files.set(b, files.get(a)); files.delete(a); },
  unlinkSync(p) { files.delete(p); }
};
const context = { filesDir: '/app', applicationInfo: { name: 'test.app' }, resourceManager: { async getRawFileContent() { throw Error('no raw config'); } } };
const works = new Map(); let starts = 0;
const workScheduler = { NetworkType: { NETWORK_TYPE_ANY: 0 }, obtainAllWorks: async () => [...works.values()],
  startWork(work) { starts++; works.set(work.workId, work); }, stopWork(work) { works.delete(work.workId); } };
const kits = {
  '@kit.CoreFileKit': { fileIo }, '@kit.ArkTS': { util: { generateRandomUUID: () => `uuid-${sequence++}` } },
  '@kit.BackgroundTasksKit': { workScheduler },
  '@kit.ArkData': { preferences: { removePreferencesFromCacheSync() {}, getPreferencesSync: () => ({ getSync: (k, fallback) => prefs.get(k) || fallback,
    putSync: (k, v) => prefs.set(k, v), deleteSync: k => prefs.delete(k), flushSync() {} }) } }
};
class FakeGateway {
  cancel() { this.cancelled = true; }
  async generate(request, sink) {
    if (gatewayHook) return gatewayHook(request, sink);
    assert.ok(request.tools.every(t => !['create_calendar_event', 'create_system_reminder'].includes(t.function.name)));
    assert.equal(JSON.parse(await request.executeTool({ id: 'deny', name: 'create_calendar_event', arguments: '{}' })).ok, false);
    assert.equal(JSON.parse(await request.executeTool({ id: 'deny-memo', name: 'manage_memo', arguments: '{"action":"save","title":"x","content":"x"}' })).ok, false);
    sink.onDelta('## 自动整理结果\n已生成任务输出。');
  }
}
function load(file) {
  if (file === 'services/OpenAiCompatibleGateway') return { OpenAiCompatibleGateway: FakeGateway };
  if (file === 'services/HarmonyScheduleAdapter') return { HarmonyScheduleAdapter: class { async perform() { return { ok: true, message: 'read only' }; } } };
  const absolute = path.resolve(root, file + '.ets');
  if (cache.has(absolute)) return cache.get(absolute);
  const result = {}; cache.set(absolute, result);
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(absolute, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, {
    exports: result, Date: Clock, setTimeout, clearTimeout, setInterval, clearInterval,
    require: name => {
      if (kits[name]) return kits[name];
      if (!name.startsWith('.')) throw Error('Unexpected dependency ' + name);
      return load(path.relative(root, path.resolve(path.dirname(absolute), name)).replaceAll('\\', '/'));
    }
  });
  return result;
}
const { LibraryService } = load('services/LibraryService');
const { MemoryKnowledgeRepository } = load('services/KnowledgeService');
const { RagService } = load('services/RagService');
const { AgentTaskStore } = load('services/AgentTaskStore');
const { AgentTaskService } = load('services/AgentTaskService');
const { AgentTaskRuntime } = load('services/AgentTaskRuntime');
const { LocalAgentConfigService } = load('services/LocalAgentConfigService');
const { AgentTaskManager } = load('services/AgentTaskManager');
const library = new LibraryService('/app');
const source = { id: 'attachment-one', name: '复习计划.md', kind: 'document', mimeType: 'text/plain', path: '/app/chat_attachments/attachment-one.md',
  size: 50, text: '软件工程需要明确需求分析与测试验收。'.repeat(100), truncated: false };
files.set(source.path, source.text);
library.register([source], '对话附件');
assert.equal(library.documents().length, 1);
assert.ok(library.snapshot().chunks.length > 1);
assert.equal(library.snapshot().chunks[0].sourceId, 'file:attachment-one');
library.register([source]); assert.equal(library.documents().length, 1, 'migration is idempotent');
files.delete(source.path);
assert.ok(files.has(library.documents()[0].path), 'library owns a separate copy from drafts');
const copied = library.attachment('file:attachment-one');
assert.notEqual(copied.path, library.documents()[0].path);
const citations = library.citations('file:attachment-one');
library.toggle('file:attachment-one'); assert.equal(library.snapshot().chunks.length, 0);
assert.equal(new LibraryService('/app').documents()[0].indexed, false, 'retrieval settings survive restart');
library.toggle('file:attachment-one');
library.remove('file:attachment-one');
assert.ok(files.has(copied.path), 'removing library source cannot break sent/draft attachment copies');
files.set(source.path, source.text); library.register([source]); library.registerContext(citations[0]);
assert.equal(library.documents().length, 0, 'old sessions cannot resurrect deleted library sources');

const image = { ...source, id: 'image-one', name: '图片.jpg', kind: 'image', text: '', path: '/app/chat_attachments/image-one.jpg', mimeType: 'image/jpeg' };
files.set(image.path, 'jpeg'); library.register([image]);
assert.equal(library.snapshot().chunks.length, 0);
assert.throws(() => library.toggle('file:image-one'), /图片/);
assert.equal(library.attachment('file:image-one').kind, 'image');
library.saveImageDescription('file:image-one', '图片显示一张二叉树遍历示意图，根节点标记为一。');
const imageChunk = library.snapshot().chunks.find(c => c.sourceId === 'file:image-one');
assert.equal(imageChunk.modality, 'image');
assert.equal(imageChunk.mediaPath, '/app/library_files/image-one.jpg');
assert.equal(imageChunk.mediaMimeType, 'image/jpeg');
library.toggle('file:image-one');
assert.equal(library.documents().find(d => d.id === 'file:image-one').indexed, false);
const chunk = { id: 'one', sourceId: 'original', title: '算法索引', location: '第一章', course: '数据结构',
  content: '二叉树的前序遍历先访问根节点。', vector: [1, 0], vectorModel: 'embed-v1', modality: 'table' };
const json = { ...source, id: 'index-one', name: 'index.json', path: '/app/chat_attachments/index-one.json', text: '{}', size: 1000 };
files.set(json.path, JSON.stringify({ revision: 'test', chunks: [chunk] })); library.register([json]);
assert.equal(library.documents().find(d => d.id === 'file:index-one').kind, 'index');
assert.deepEqual(plain(library.snapshot().chunks[0].vector), [1, 0]);
assert.equal(library.snapshot().chunks[0].vectorModel, 'embed-v1');
assert.equal(library.snapshot().chunks[0].modality, 'table');
assert.notEqual(library.snapshot().chunks[0].id, chunk.id);
const invalid = { ...json, id: 'bad-index', path: '/app/chat_attachments/bad-index.json' };
files.set(invalid.path, JSON.stringify({ chunks: [chunk, chunk] }));
assert.throws(() => library.register([invalid]), /重复/);
assert.ok(!library.documents().some(d => d.id === 'file:bad-index'), 'bad index import is atomic');
const base = new MemoryKnowledgeRepository(); base.replace({ revision: 'base', chunks: [chunk] });
const wrapped = new LibraryService('/base', base);
wrapped.toggle('rag:original'); assert.equal(wrapped.snapshot().chunks.length, 0);
wrapped.registerContext({ chunkId: 'one', sourceId: 'original', title: 'title', excerpt: 'must not reimport', course: '', location: '', number: 1, score: 1 });
assert.equal(wrapped.documents().length, 1, 'disabled external sources are not reimported as orphan context');
assert.equal(base.snapshot().chunks.length, 1, 'external repository remains intact');
assert.throws(() => wrapped.remove('rag:original'), /停用/);
dirs.set('/app/library.json.lock', now / 1000); assert.throws(() => library.toggle('file:index-one'), /正在保存/); dirs.delete('/app/library.json.lock');
failWrites = true; assert.throws(() => library.toggle('file:index-one')); failWrites = false;
assert.equal(new LibraryService('/app').documents().find(d => d.id === 'file:index-one').indexed, true);
const latestLibrary = files.get('/app/library.json'); files.set('/app/library.json', 'broken');
assert.ok(new LibraryService('/app').documents().length > 0, 'recover backup without discarding files'); files.set('/app/library.json', latestLibrary);
library.saveText('粘贴资料', '白鹭栈桥是联调验证词。');
const pasted = library.documents().find(d => d.origin === '文本资料');
const oldCitation = library.citations(pasted.id)[0];
library.saveText('新标题', '修改后的白鹭栈桥正文。', pasted.id);
assert.equal(library.documents().find(d => d.id === pasted.id).title, '新标题');
assert.notEqual(library.citations(pasted.id)[0].chunkId, oldCitation.chunkId, 'edited content has a new citation version');
library.registerContext(oldCitation); assert.equal(library.documents().filter(d => d.origin === '文本资料').length, 1, 'saved citations do not resurrect old text versions');
library.remove(pasted.id);

const store = new AgentTaskStore('/app');
const draft = { title: '每日整理', prompt: '汇总日历与复习资料', mode: 'daily', firstRunAt: now + 3600000, intervalMinutes: 60, weekdays: [1, 3, 5] };
assert.throws(() => AgentTaskService.validate({ ...draft, mode: 'interval', intervalMinutes: 1 }));
assert.throws(() => AgentTaskService.validate({ ...draft, mode: 'weekly', weekdays: [] }));
store.save(draft); let task = store.list()[0];
const following = AgentTaskService.next(task, task.nextRunAt);
assert.equal(new Clock(following).getHours(), new Clock(task.firstRunAt).getHours());
assert.ok(following > task.nextRunAt);
assert.equal(store.claim(task.id), undefined);
now = task.nextRunAt + 60 * 60000;
const claimed = store.claim(task.id); assert.ok(claimed);
assert.equal(new AgentTaskStore('/app').claim(task.id), undefined, 'foreground and extension cannot claim the same execution');
assert.ok(store.list()[0].nextRunAt > now, 'missed periods are coalesced instead of replaying a backlog');
store.finish(claimed, 'success', 'first result'); assert.equal(store.list()[0].runs[0].output, 'first result');
store.toggle(task.id); assert.equal(store.list()[0].enabled, false);
assert.equal(store.claim(task.id), undefined);
const manual = store.claim(task.id, true); assert.ok(manual); store.finish(manual, 'failed', 'network failed');
assert.equal(store.list()[0].enabled, false, 'manual run does not reactivate a paused schedule');
const beforeNext = store.list()[0].nextRunAt;
const stale = store.claim(task.id, true); now += 181000; store.claim(task.id);
assert.equal(store.list()[0].runId, ''); assert.equal(store.list()[0].runs[0].status, 'interrupted');
assert.equal(store.list()[0].nextRunAt, beforeNext);
store.finish(stale, 'success', 'late result'); assert.notEqual(store.list()[0].runs[0].output, 'late result', 'stale completion is ignored');
failWrites = true; assert.throws(() => store.save({ ...draft, firstRunAt: now + 3600000 })); failWrites = false;
assert.equal(new AgentTaskStore('/app').list().length, 1);

(async () => {
  const found = await new RagService(library).search('二叉树前序遍历', { course: '', topK: 4, minScore: 0, maxPerSource: 4, contextChars: 2400 });
  assert.equal(found.status, 'hit'); assert.ok(found.sources.some(s => s.title === '算法索引'));
  LocalAgentConfigService.saveRuntime(context, { baseUrl: 'https://example.invalid/v1', model: 'test', apiKey: 'private-test-value' });
  assert.equal((await LocalAgentConfigService.load(context)).model, 'test');
  await AgentTaskRuntime.register(context); assert.equal(works.size, 0, 'paused tasks do not register wakeups');
  store.toggle(task.id); await AgentTaskRuntime.register(context); await AgentTaskRuntime.register(context);
  assert.equal(starts, 1, 'registering a work item is idempotent');
  await AgentTaskRuntime.run(context, task.id, true);
  assert.equal(store.list()[0].runs[0].status, 'success');
  assert.match(store.list()[0].runs[0].output, /自动整理结果/);
  let release, entered;
  const started = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  gatewayHook = async (request, sink) => { entered(); await gate; if (!sink.isCancelled()) sink.onDelta('should be discarded'); };
  const running = AgentTaskRuntime.run(context, task.id, true); await started;
  store.remove(task.id); AgentTaskRuntime.cancel(task.id); release(); await running;
  assert.equal(store.list().length, 0, 'deleting a running task never resurrects it on completion');
  await AgentTaskRuntime.register(context); assert.equal(works.size, 0);
  LocalAgentConfigService.saveRuntime(context, { baseUrl: '', model: '', apiKey: '' });
  assert.equal((await LocalAgentConfigService.load(context)).baseUrl, '', 'clearing saved configuration does not revive bundled credentials');
  const manage = (args, active = () => true, confirm = async () => true) => AgentTaskManager.execute(context,
    { id: 'tool', name: 'manage_agent_task', arguments: JSON.stringify(args) }, active, confirm).then(JSON.parse);
  const create = { action: 'create', title: '通过对话创建', prompt: '整理我的日程', mode: 'weekly', firstRun: new Clock(now + 86400000).toISOString(), weekdays: [1] };
  assert.equal((await manage(create, () => true, async () => false)).ok, false); assert.equal(store.list().length, 0);
  assert.equal((await manage(create)).ok, true);
  const managed = store.list()[0]; assert.equal((new Clock(managed.nextRunAt).getDay() || 7), 1);
  assert.equal((await manage({ action: 'pause', id: managed.id })).ok, true);
  assert.equal((await manage({ action: 'update', id: managed.id, prompt: '只整理明日待办' })).ok, true);
  assert.equal(store.list()[0].enabled, false, 'editing a paused task must preserve the paused state');
  assert.equal((await manage({ action: 'list' })).tasks[0].prompt, '只整理明日待办');
  assert.equal((await manage({ action: 'delete', id: managed.id }, () => false)).ok, false);
  assert.equal((await manage({ action: 'delete', id: managed.id })).ok, true); assert.equal(store.list().length, 0);
  console.log('PASS: persistent unified library, owned files, RAG JSON/vector imports, deletion tombstones, retrieval toggles, atomic stores; scheduled recurrence, cross-process claims, restart/recovery, readonly execution and local API configuration.');
})().catch(error => { console.error(error); process.exitCode = 1; });
