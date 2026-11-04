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
const catalogExports = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/config/FeatureCatalog.ets'), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, { exports: catalogExports });
const etsRoot = path.join(__dirname, '../entry/src/main/ets');
const moduleCache = new Map();
function loadEts(file) {
  const absolute = path.resolve(etsRoot, file + '.ets');
  if (moduleCache.has(absolute)) return moduleCache.get(absolute);
  const result = {};
  moduleCache.set(absolute, result);
  const code = ts.transpileModule(fs.readFileSync(absolute, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInNewContext(code, { exports: result, Date: TestDate, require: name => {
    if (name === '@kit.ArkTS') return { util: { generateRandomUUID: () => 'uuid-test' } };
    if (name === '@kit.CoreFileKit') return { fileIo: {} };
    if (!name.startsWith('.')) throw Error('Unexpected runtime dependency: ' + name);
    return loadEts(path.relative(etsRoot, path.resolve(path.dirname(absolute), name)));
  } });
  return result;
}
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
  const traceExports = loadEts('services/ExecutionTraceService');
  vm.runInNewContext(compiled, { exports, setTimeout, clearTimeout, Date: TestDate,
    require: name => {
      if (name === './ExecutionTraceService') return traceExports;
      if (name === '../config/FeatureCatalog') return catalogExports;
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
  const panel = { goal: '复习计划', summary: '用户确认目标', tasks: [{ id: 'study', title: '复习图算法', detail: '周三', status: 'pending' }],
    artifacts: [{ id: 'notes', title: '学习笔记', content: '## 图遍历' }], updatedAt: now };
  const panelTime = service.get(first.id).updatedAt;
  panel.interactions = [{ id: 'message-0', source: 'message', title: '复习回执', updatedAt: now,
    values: [{ id: 'notes', label: '实际时间', kind: 'text', value: '周三17:30' }] }];
  service.saveWorkspace(first.id, 'home', panel);
  const sidebar = { workspaceSectionExpanded: true, recentSectionExpanded: false, expandedWorkspaceIds: ['home'],
    expandedHistoryIds: ['home'], showAllRecent: true, panelVisible: false };
  service.saveSidebar(sidebar);
  sidebar.expandedWorkspaceIds.push('external mutation');
  assert.deepEqual(Array.from(service.sidebar().expandedWorkspaceIds), ['home'], 'sidebar preferences must be copied');
  assert.equal(service.get(first.id).updatedAt, panelTime, 'panel edits must not reorder chat history');
  panel.goal = 'outside mutation';
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
  assert.equal(service.get(first.id).workspace.goal, '复习计划');
  assert.equal(service.sidebar().recentSectionExpanded, false);
  assert.equal(service.sidebar().panelVisible, false, 'sidebar visibility must survive restart');
  assert.equal(service.get(first.id).workspace.artifacts[0].content, '## 图遍历');
  assert.equal(service.get(first.id).workspace.interactions[0].values[0].value, '周三17:30', 'manual interaction state must survive process restart');
  assert.equal(service.get(second.id).workspace, undefined, 'panel must stay isolated per conversation');
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
  service.saveWorkspace(first.id, 'study', service.get(first.id).workspace);
  assert.equal(service.get(first.id).featureId, 'study', 'agent workspace switch must persist on the same conversation');
  assert.equal(service.get(first.id).updatedAt, firstUpdatedAt);
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
  assert.deepEqual(Array.from(service.sidebar().expandedWorkspaceIds), ['home'], 'deleting a conversation must keep folder preferences');
  fs.writeFileSync(archivePath, '{broken');
  service = boot();
  assert.equal(service.get(second.id), undefined, 'backup recovery must not resurrect deleted conversations');
  assert.equal(service.remove(first.id), true);
  assert.equal(service.current(), undefined, 'deleting the last conversation must clear the active id');
  service = boot();
  assert.equal(service.list().length, 0);
  assert.equal(service.workspaces().length, 11, 'old archives must migrate to defaults plus protected trash');
  assert.ok(service.workspaces().some(item => item.id === 'privacy'), 'existing archives must receive the new privacy workspace');
  assert.equal(service.deleteWorkspace('home'), false);
  assert.equal(service.deleteWorkspace('trash'), false);
  assert.throws(() => service.create('trash', 'invalid', []));
  const custom = service.addWorkspace('毕业设计', '论文与课题进度', '你是毕业设计规划助手。');
  assert.ok(custom.id.startsWith('workspace-'));
  assert.throws(() => service.addWorkspace('毕业设计'));
  const a = service.create(custom.id, '论文计划', [message('user', '完成论文')]);
  const b = service.create(custom.id, '开题讨论', []);
  const keptAttachment = `${directory}/chat_attachments/trash-keep.txt`;
  fs.writeFileSync(keptAttachment, 'keep');
  const withFile = message('user', '请保留附件');
  withFile.attachments = [{ id: 'keep', name: 'test.txt', kind: 'document', path: keptAttachment, text: 'keep', size: 4 }];
  service.saveMessages(a.id, [withFile]);
  service.saveWorkspace(a.id, custom.id, { ...panel, goal: '论文计划' });
  service.saveDetails(a.id, [citation], 2);
  const beforeTrash = service.get(a.id);
  const backupBeforeFailure = fs.readFileSync(`${archivePath}.bak`, 'utf8');
  failRename = true;
  assert.equal(service.deleteWorkspace(custom.id), false, 'failed bulk deletion must restore both registry and conversations');
  assert.ok(service.workspaces().some(w => w.id === custom.id));
  assert.equal(service.get(a.id).featureId, custom.id);
  assert.equal(fs.readFileSync(`${archivePath}.bak`, 'utf8'), backupBeforeFailure, 'failed deletion must preserve the last recovery copy');
  failRename = false;
  assert.equal(service.deleteWorkspace(custom.id), true);
  service = boot();
  assert.ok(!service.workspaces().some(w => w.id === custom.id), 'removed workspaces must stay removed after restart');
  for (const id of [a.id, b.id]) {
    assert.equal(service.get(id).featureId, 'trash');
    assert.equal(service.get(id).originFeatureId, custom.id);
    assert.equal(service.get(id).originFeatureName, '毕业设计');
    assert.equal(service.get(id).deletedAt, now);
  }
  assert.equal(service.get(a.id).updatedAt, beforeTrash.updatedAt, 'deletion time must not overwrite conversation time');
  assert.equal(service.get(a.id).workspace.goal, '论文计划');
  assert.equal(service.get(a.id).workspace.interactions[0].values[0].value, '周三17:30', 'trash must preserve interactive responses');
  assert.equal(service.get(a.id).context.length, 1);
  assert.ok(fs.existsSync(keptAttachment), 'workspace deletion must keep attachment files');
  service.saveMessages(a.id, [message('user', 'stale callback')]);
  service.saveDetails(a.id, [], 0);
  service.saveWorkspace(a.id, 'home', panel);
  assert.equal(service.get(a.id).messages[0].content, '请保留附件', 'trashed conversations must be read-only');
  assert.equal(service.get(a.id).context.length, 1);
  assert.equal(service.get(a.id).featureId, 'trash');
  fs.writeFileSync(archivePath, '{broken');
  service = boot();
  assert.equal(service.get(a.id).featureId, 'trash', 'backup recovery must not undo workspace deletion');
  assert.ok(!service.workspaces().some(w => w.id === custom.id));
  assert.equal(service.restore(a.id), true);
  assert.equal(service.get(a.id).featureId, 'home', 'deleted original workspace restores to assistant');
  assert.equal(service.get(a.id).deletedAt, undefined);
  assert.equal(service.get(a.id).updatedAt, beforeTrash.updatedAt);
  assert.equal(service.get(a.id).workspace.interactions[0].values[0].value, '周三17:30', 'restore to assistant must preserve interactive responses');
  assert.ok(fs.existsSync(keptAttachment));
  assert.equal(service.trash(a.id), true);
  assert.equal(service.restore(a.id), true);
  assert.equal(service.get(a.id).featureId, 'home', 'individual deletion restores to existing original workspace');
  assert.equal(service.trash(a.id), true);
  assert.equal(service.remove(a.id), true);
  assert.equal(fs.existsSync(keptAttachment), false, 'permanent deletion finally cleans orphan attachment copies');
  const failedCount = service.workspaces().length;
  failRename = true;
  assert.equal(service.addWorkspace('保存失败测试'), undefined);
  assert.equal(service.workspaces().length, failedCount);
  failRename = false;
  service.flush();
  service.saveSidebar({ ...sidebar, leftWidth: 320, rightWidth: 350, fontScale: 1.1, taskPanelVisible: false });
  service = boot();
  assert.equal(service.sidebar().leftWidth, 320);
  assert.equal(service.sidebar().rightWidth, 350);
  assert.equal(service.sidebar().fontScale, 1.1);
  assert.equal(service.sidebar().taskPanelVisible, false);
  const traceSession = service.create('home', 'execution fixture', []);
  const traceOther = service.create('home', 'another reply', []);
  const traceStart = now;
  service.saveMessages(traceSession.id, [{role:'agent',content:'partial',meta:'',status:'streaming',thinkingStartedAt:traceStart,
    thinkingLastActiveAt:traceStart,executionId:'execution-a',createdAt:traceStart}]);
  const traceOrder = service.get(traceSession.id).updatedAt;
  const traceRecord = {id:'tool-1',kind:'tool',name:'get_system_time',title:'读取时间',status:'running',startedAt:traceStart,input:'',detail:'waiting',targets:[]};
  now += 2700;
  service.activate(traceOther.id);
  service.recordExecution(traceSession.id,'execution-a',traceRecord);
  assert.equal(service.get(traceSession.id).updatedAt,traceOrder,'tool metadata does not reorder conversations');
  assert.equal(service.current().id,traceOther.id,'execution receipts cannot activate their old conversation');
  service = boot();
  const interrupted = service.get(traceSession.id).messages[0];
  assert.equal(interrupted.thinkingDurationMs,2700);
  assert.equal(interrupted.createdAt,traceStart,'message creation time survives restart');
  assert.equal(interrupted.completedAt,traceStart+2700,'interrupted reply time freezes at the last saved snapshot');
  assert.equal(interrupted.executions[0].status,'interrupted');
  now += 40000;
  service.recordExecution(traceSession.id,'execution-a',{...traceRecord,status:'success',finishedAt:traceStart+2700,detail:'real receipt'});
  assert.equal(service.get(traceSession.id).messages[0].executions.length,1);
  assert.equal(service.get(traceSession.id).messages[0].executions[0].status,'success');
  assert.equal(service.get(traceSession.id).messages[0].thinkingDurationMs,2700);
  service = boot();
  assert.equal(service.get(traceSession.id).messages[0].thinkingDurationMs,2700,'reopening and later receipts never restart elapsed time');
  assert.equal(service.get(traceSession.id).messages[0].completedAt,traceStart+2700,'late tool receipts must not change the visible answer time');
  assert.equal(service.get(traceSession.id).messages[0].executions[0].detail,'real receipt');
  service.trash(traceSession.id); service.remove(traceSession.id);
  assert.equal(service.recordExecution(traceSession.id,'execution-a',traceRecord),undefined,'late results cannot resurrect deleted messages');
  fs.writeFileSync(archivePath, '{broken');
  fs.writeFileSync(`${archivePath}.bak`, '{also broken');
  service = boot();
  service.create('home', 'temporary', []);
  assert.equal(fs.readFileSync(archivePath, 'utf8'), '{broken', 'unreadable originals must be preserved');
  console.log('PASS: history, workspace migration/creation, protected sections, transactional bulk trash, read-only archive, restore/fallback, attachment lifecycle, width persistence and restart.');
} finally {
  // This directory is created exclusively for this test under the OS temporary directory.
  assert.equal(path.dirname(path.resolve(directory)), path.resolve(os.tmpdir()));
  assert.match(path.basename(directory), /^campuspilot-history-/);
  fs.rmSync(directory, { recursive: true, force: true });
}
