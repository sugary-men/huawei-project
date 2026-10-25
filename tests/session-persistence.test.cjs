// Run with Node and a TypeScript compiler path (DevEco bundles TypeScript).
// node tests/session-persistence.test.cjs <path-to-typescript.js>
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/SessionService.ets'), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS,
  target: ts.ScriptTarget.ES2020 } }).outputText;
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'campuspilot-history-'));
const archivePath = path.join(directory, 'chat_sessions.json');
let failRename = false;
let now = Date.now();
class TestDate extends Date { static now() { return now; } }
const bridge = {
  accessSync: fs.existsSync, readTextSync: p => fs.readFileSync(p, 'utf8'),
  unlinkSync: fs.unlinkSync,
  copyFileSync: fs.copyFileSync, OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  openSync: p => ({ fd: fs.openSync(p, 'w') }),
  writeSync: (fd, value) => fs.writeSync(fd, value), fsyncSync: fs.fsyncSync,
  closeSync: file => fs.closeSync(file.fd),
  renameSync: (from, to) => { if (failRename) throw Error('simulated disk failure'); fs.renameSync(from, to); }
};
function boot() {
  const exports = {};
  vm.runInNewContext(compiled, { exports, setTimeout, clearTimeout, Date: TestDate,
    require: name => {
      if (name === '@kit.CoreFileKit') return { fileIo: bridge };
      if (name === '@kit.ArkTS') return { util: { generateRandomUUID: crypto.randomUUID } };
      throw Error(`Unexpected runtime dependency: ${name}`);
    }
  });
  const service = exports.SessionService;
  service.initialize({ filesDir: directory });
  return service;
}
const message = (role, content, status = 'complete') => ({ role, content, status, meta: 'test' });
try {
  let service = boot();
  const first = service.create('home', '新对话', []);
  now += 1000;
  const second = service.create('schedule', '新对话', []);
  assert.notEqual(first.id, second.id, 'same-title chats must have independent identities');
  const messages = Array.from({ length: 126 }, (_, i) => message(i % 2 ? 'agent' : 'user', `内容 ${i}`));
  messages[125].status = 'streaming';
  messages[125].thinkingStartedAt = Date.now() - 5000;
  messages[125].phase = 'answering';
  now += 1000;
  service.saveMessages(first.id, messages);
  const citation = { number: 1, chunkId: 'chunk', sourceId: 'source', title: '资料', location: 'p1',
    course: '课程', excerpt: '引用正文', score: 1 };
  service.saveDetails(first.id, [citation], 2);
  const attachmentDir = path.join(directory, 'chat_attachments');
  fs.mkdirSync(attachmentDir);
  const attachmentPath = `${directory}/chat_attachments/delete-test.txt`;
  fs.writeFileSync(attachmentPath, 'test attachment');
  const secondUser = message('user', '独立会话');
  secondUser.attachments = [{ id: 'test', name: 'test.txt', kind: 'document', path: attachmentPath, text: 'test', size: 4, mimeType: 'text/plain', truncated: false }];
  now += 1000;
  service.saveMessages(second.id, [secondUser, message('agent', '', 'loading')]);
  service.activate(first.id);
  messages[0].content = 'external mutation';
  assert.equal(service.loadMessages(first.id)[0].content, '内容 0', 'saved data must be isolated');
  service.flush();
  service = boot();
  assert.equal(service.current().id, first.id, 'active chat must survive process restart');
  assert.equal(service.get(first.id).messages.length, 126, 'history must not silently truncate at 100');
  assert.equal(service.get(first.id).progress, 2);
  assert.equal(service.get(first.id).context[0].excerpt, '引用正文');
  assert.equal(service.get(first.id).messages[125].status, 'stopped', 'interrupted streams must settle');
  assert.equal(service.get(first.id).messages[125].thinkingStartedAt, messages[125].thinkingStartedAt);
  assert.ok(service.get(first.id).messages[125].thinkingDurationMs >= 0, 'restored duration must stop at the last saved snapshot');
  assert.match(service.get(second.id).messages[1].content, /上次生成已中断/);
  assert.equal(service.get(second.id).featureId, 'schedule');
  assert.equal(service.list().find(s => s.id === first.id).title, '内容 0');
  const order = service.list().map(s => s.id).join(',');
  const firstUpdatedAt = service.get(first.id).updatedAt;
  now += 60000;
  service.activate(second.id);
  service.saveMessages(first.id, service.loadMessages(first.id));
  service.saveDetails(first.id, service.get(first.id).context, 2);
  service.activate(first.id);
  assert.equal(service.get(first.id).updatedAt, firstUpdatedAt, 'viewing/saving unchanged messages must not update time');
  assert.equal(service.list().map(s => s.id).join(','), order, 'switching conversations must keep chronological order');
  assert.ok(service.list().every((s, index, list) => index === 0 || list[index - 1].updatedAt >= s.updatedAt));
  const before = fs.readFileSync(archivePath, 'utf8');
  failRename = true;
  service.saveMessages(first.id, [message('user', 'new data')]);
  assert.equal(fs.readFileSync(archivePath, 'utf8'), before, 'failed writes must preserve the previous snapshot');
  assert.match(service.storageNotice, /未能写入/);
  failRename = false;
  service.flush();
  fs.writeFileSync(archivePath, '{broken');
  service = boot();
  assert.equal(service.current().id, first.id, 'corrupted primary must recover the valid backup');
  assert.equal(service.get(first.id).messages.length, 126);
  failRename = true;
  assert.equal(service.remove(first.id), false, 'failed delete writes must roll back in memory');
  assert.ok(service.get(first.id));
  failRename = false;
  assert.equal(service.remove(second.id), true);
  assert.equal(service.current().id, first.id, 'deleting an inactive conversation must preserve the active one');
  assert.equal(fs.existsSync(attachmentPath), false, 'delete owned attachment copies');
  service = boot();
  assert.equal(service.get(second.id), undefined, 'deleted conversations must stay deleted after restarting');
  fs.writeFileSync(archivePath, '{broken');
  service = boot();
  assert.equal(service.get(second.id), undefined, 'backup recovery must not resurrect deleted conversations');
  assert.equal(service.remove(first.id), true);
  assert.equal(service.current(), undefined, 'deleting the last conversation must clear the active id');
  service = boot();
  assert.equal(service.list().length, 0);
  fs.writeFileSync(archivePath, '{broken');
  fs.writeFileSync(`${archivePath}.bak`, '{also broken');
  service = boot();
  service.create('home', 'temporary', []);
  assert.equal(fs.readFileSync(archivePath, 'utf8'), '{broken', 'unreadable originals must be preserved');
  console.log('PASS: stable chronological order, unchanged-save timestamps, deletion and rollback, attachment cleanup, recovery without resurrection, full history and restart.');
} finally {
  // This directory is created exclusively for this test under the OS temporary directory.
  assert.equal(path.dirname(path.resolve(directory)), path.resolve(os.tmpdir()));
  assert.match(path.basename(directory), /^campuspilot-history-/);
  fs.rmSync(directory, { recursive: true, force: true });
}
