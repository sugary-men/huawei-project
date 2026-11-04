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
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(absolute, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, {
    exports: result, require: name => {
      if (name === '@kit.ArkTS') return { util: { generateRandomUUID: () => 'uuid-test' } };
    if (name === '@kit.CoreFileKit') return { fileIo: {} };
    if (!name.startsWith('.')) throw Error('Unexpected runtime dependency: ' + name);
      return load(path.relative(root, path.resolve(path.dirname(absolute), name)));
    }
  });
  return result;
}
const { InteractionService: interaction } = load('services/InteractionService');
const { WorkspaceService: workspace } = load('services/WorkspaceService');
const { ChatService } = load('services/ChatService');
const document = '## 出行清单\n- [ ] 带上学生证\n- [x] 预约场地\n1. 确认时间\n2. 确认时间\n\n## 活动回执\n| 字段 | 内容 |\n| --- | --- |\n| 日期 | 待填写 |\n| 地点 | 待填写 |\n\n```md\n- [ ] 代码示例不能交互\n```\n> - [ ] 引用中的例子\n';
const layout = interaction.layout(document);
const checks = layout.controls.filter(c => c.kind === 'check');
const cells = layout.controls.filter(c => c.id.includes('-cell-'));
assert.equal(checks.length, 4, 'ordered and ordinary lists join native task checkboxes; code/quotes stay inert');
assert.equal(new Set(checks.map(c => c.id)).size, 4, 'duplicate list labels need independent identities');
assert.equal(checks[1].initialValue, 'true');
assert.equal(cells.length, 4);
assert.equal(layout.hasTables, true);
const inserted = interaction.layout(document.replace('- [ ] 带上学生证', '- [ ] 先检查天气\n- [ ] 带上学生证'));
assert.equal(inserted.controls.find(c => c.label === '带上学生证').id, checks[0].id, 'inserting before a list must not reassign saved selections');
const duplicateSections = interaction.layout('## A\n- [ ] 同一项\n## B\n- [ ] 同一项');
assert.equal(new Set(duplicateSections.controls.filter(c => c.kind === 'check').map(c => c.id)).size, 2);
const headerRename = interaction.layout(document.replace('| 字段 | 内容 |', '| 字段 | 实际结果 |'));
assert.notEqual(headerRename.controls.find(c => c.label.endsWith('日期 / 实际结果')).id,
  cells.find(c => c.label.endsWith('日期 / 内容')).id, 'renamed columns must not inherit an unrelated old value');
let records = [];
const apply = (id, source, change) => interaction.update(records, id, source, '活动清单与回执', document, change);
records = apply('message-0', 'message', { controlId: checks[0].id, value: 'true' });
const original = JSON.stringify(records);
const record = interaction.record(records, 'message-0');
assert.equal(interaction.controlValue(record, checks[0]), 'true');
assert.equal(interaction.controlValue(record, checks[1]), 'true', 'unchecked-by-user values must preserve generated initial checks');
records = apply('message-0', 'message', { controlId: checks[1].id, value: 'false' });
assert.equal(interaction.controlValue(interaction.record(records, 'message-0'), checks[1]), 'false');
assert.equal(record.values.length, 1, 'editing feedback must not mutate an old state snapshot');
const date = cells.find(c => c.label.endsWith('日期 / 内容'));
assert.equal(interaction.inputValue(interaction.empty(), date), '', 'pending placeholders must not become literal input text');
records = apply('message-0', 'message', { controlId: date.id, value: '人工填写：周三14:30' });
assert.equal(interaction.inputValue(interaction.record(records, 'message-0'), date), '人工填写：周三14:30');
records = apply('message-0', 'message', { controlId: 'decision', value: 'confirmed' });
records = apply('message-0', 'message', { controlId: 'notes', value: '用户补充：不需要交通安排' });
assert.ok(interaction.preview(document, interaction.record(records, 'message-0')).includes('人工填写：周三14:30'), 'artifact preview must show edited values rather than stale generated cells');
records = apply('artifact-plan', 'artifact', { controlId: checks[0].id, value: 'false' });
records = apply('memory-summary', 'memory', { controlId: 'decision', value: 'needs_changes' });
const revisedDocument = document.replace('- [ ] 带上学生证', '- [ ] 带上身份证');
const previousContext = JSON.parse(interaction.context(records, { 'message-0': revisedDocument }));
const previousRecord = previousContext.find(r => r.id === 'message-0');
assert.equal(previousRecord.versionStatus, 'previous', 'a confirmation must never silently authorize changed content');
assert.equal(previousRecord.values.find(v => v.id === checks[0].id).active, false, 'removed items must be identified as historical feedback');
const reconfirm = interaction.update(records, 'message-0', 'message', '新版', revisedDocument, { controlId: 'notes', value: '先核对新版' });
assert.equal(interaction.value(interaction.record(reconfirm, 'message-0'), 'decision', 'none'), 'none', 'interacting with a revised document must discard the old whole-document confirmation');
const currentContext = JSON.parse(interaction.context(reconfirm, { 'message-0': revisedDocument })).find(r => r.id === 'message-0');
assert.equal(currentContext.versionStatus, 'current');
assert.equal(interaction.controlValue(interaction.record(records, 'artifact-plan'), checks[0]), 'false');
assert.equal(interaction.controlValue(interaction.record(records, 'message-0'), checks[0]), 'true', 'message/artifact copies must not overwrite each other');
const beforeInvalid = JSON.stringify(records);
for (const change of [{ controlId: 'unknown', value: 'true' }, { controlId: checks[0].id, value: 'yes' },
  { controlId: 'decision', value: 'submitted_to_server' }, { controlId: 'notes', value: 'x'.repeat(1001) }]) {
  assert.throws(() => apply('message-0', 'message', change));
  assert.equal(JSON.stringify(records), beforeInvalid, 'invalid writes must fail atomically');
}
assert.throws(() => interaction.update(records, 'bad', 'external', 'bad', document, { controlId: 'notes', value: 'x' }));
const state = workspace.create('home');
state.interactions = records;
state.artifacts = [{ id: 'plan', title: '活动清单与回执', content: document }];
const recentHistory = Array.from({ length: 18 }, (_, i) => ({ role: i % 2 ? 'agent' : 'user', content: `最近消息${i}`, meta: '' }));
const request = ChatService.request('请进行下一步', 'home', recentHistory, { context: '', sources: [] }, [], state, async () => '{}');
assert.equal(request.history.length, 12);
assert.ok(!request.history.some(m => m.content === '最近消息0'));
assert.ok(request.systemInstruction.includes('人工填写：周三14:30'), 'older-than-context feedback must still reach the agent');
assert.ok(request.systemInstruction.includes('用户补充：不需要交通安排'));
assert.equal(request.systemInstruction.split('人工填写：周三14:30').length - 1, 1, 'do not duplicate the entire feedback ledger in initial prompt');
assert.ok(request.systemInstruction.includes('不等于提交了外部表单'));
assert.ok(request.systemInstruction.includes('优先于旧聊天里的推测'));
assert.ok(ChatService.request('继续', 'home', [], { context: '', sources: [] }, [], state).systemInstruction.includes('人工填写：周三14:30'), 'feedback must work with gateways without tools');
const updated = workspace.update(state, { goal: '模型更新了目标' });
assert.equal(JSON.stringify(updated.interactions), JSON.stringify(records), 'model panel updates must retain manual feedback');
const switched = workspace.applyTool('switch_workspace', '{"featureId":"study"}', 'home', state);
assert.deepEqual(JSON.parse(JSON.stringify(switched.state.interactions)), JSON.parse(JSON.stringify(records)), 'workspace routing must not lose response state');
const attemptedOverwrite = workspace.applyTool('update_task_panel', '{"goal":"新目标","interactions":[]}', 'home', state);
assert.equal(JSON.stringify(attemptedOverwrite.state.interactions), JSON.stringify(records), 'model cannot reset user feedback by supplying extra fields');
const restored = workspace.restore('home', JSON.parse(JSON.stringify(state)));
assert.deepEqual(JSON.parse(JSON.stringify(restored.interactions)), JSON.parse(JSON.stringify(records)));
assert.equal(workspace.restore('home', { ...state, goal: 123 }).interactions.length, 3, 'feedback recovery is independent from malformed old task state');
assert.ok(JSON.parse(workspace.snapshot('home', state)).state.interactions.length === 3, 'read_workspace also carries feedback');
records = apply('message-0', 'message', { controlId: '', value: '', reset: true });
assert.equal(interaction.record(records, 'message-0').values.length, 0);
assert.ok(interaction.record(records, 'message-0').resetAt > 0, 'reset must be explicit so stale confirmations are not reused');
records = apply('message-0', 'message', { controlId: 'notes', value: '重置后新输入' });
assert.equal(interaction.value(interaction.record(records, 'message-0'), 'notes'), '重置后新输入');
records = apply('message-0', 'message', { controlId: 'notes', value: '' });
assert.equal(interaction.value(interaction.record(records, 'message-0'), 'notes'), '', 'users can clear a field explicitly');
assert.equal(interaction.restore([null, { id: 'bad' }, ...records]).length, 3);
let bounded = [];
let rejected = false;
for (let i = 0; i < 150; i++) {
  const before = JSON.stringify(bounded);
  try { bounded = interaction.update(bounded, `message-${i}`, 'message', '容量测试', '', { controlId: 'notes', value: 'a'.repeat(1000) }); }
  catch { assert.equal(JSON.stringify(bounded), before); rejected = true; break; }
}
assert.ok(rejected, 'feedback budget must reject excess without truncating existing answers');
assert.equal(interaction.elementId('artifact:plan', date.id).includes(':'), false);
assert.equal(JSON.parse(original)[0].values[0].value, 'true');
console.log('PASS: native-control identities, old Markdown compatibility, isolated feedback, validation/atomic limits, resets, task/route preservation, restart restoration and full next-request context.');

const form = '## 基本信息\n| 项目 | 请填写 | 为什么需要 |\n| --- | --- | --- |\n| 出行日期 | ___（例：2026-11-01 周日） | 确定日期 |\n| 同行人数 | ___ 人 | 计算预算 |\n| 是否去灵隐 | □ 不去（按主线） □ 改去（走备选） | 路线 |\n| 装备（多选） | □ 水 □ 伞 | 携带物品 |\n\n已购，实付＿元。\n\n- 如果只是确认了，我会测\n- 如果已经买好票，请填写金额\n\n__加粗文字__ 与 `___`、snake__case';
const formLayout = interaction.layout(form);
const blanks = formLayout.controls.filter(c => c.id.includes('-blank-'));
const options = formLayout.controls.filter(c => c.id.includes('-option-'));
assert.equal(blanks.length, 3, 'table and prose blanks are native inputs; code, emphasis and identifiers are inert');
assert.equal(options.length, 4);
assert.equal(formLayout.controls.filter(c => c.id.startsWith('list-')).length, 0, 'explanatory bullets must not become tasks');
assert.ok(options[0].group && options[0].group === options[1].group);
assert.ok(!options[2].group && !options[3].group, 'multi-select must remain independent');
let formRecords = [];
for (const control of options) formRecords = interaction.update(formRecords, 'message-form', 'message', '填写表单', form, { controlId: control.id, value: 'true' });
let formRecord = interaction.record(formRecords, 'message-form');
assert.equal(interaction.controlValue(formRecord, options[0]), 'false');
assert.equal(interaction.controlValue(formRecord, options[1]), 'true');
assert.equal(interaction.controlValue(formRecord, options[2]), 'true');
assert.equal(interaction.controlValue(formRecord, options[3]), 'true');
formRecords = interaction.update(formRecords, 'message-form', 'message', '填写表单', form, { controlId: blanks[0].id, value: '2026-11-01' });
formRecord = interaction.record(interaction.restore(JSON.parse(JSON.stringify(formRecords))), 'message-form');
assert.equal(interaction.inputValue(formRecord, blanks[0]), '2026-11-01');
assert.ok(interaction.context(formRecords, { 'message-form': form }).includes('2026-11-01'));
console.log('PASS: inline form blanks, Unicode choices, mutually exclusive selections, independent multi-select and literal Markdown.');

const emptyReview = JSON.parse(interaction.review(form, interaction.empty('message-form')));
assert.ok(emptyReview.fields.filter(f => f.id.includes('-blank-')).every(f => f.empty && !f.userEdited), 'untouched blanks reach the agent as empty');
const filledReview = JSON.parse(interaction.review(form, formRecord));
assert.equal(filledReview.fields.find(f => f.id === blanks[0].id).value, '2026-11-01');
assert.equal(filledReview.fields.find(f => f.id === blanks[0].id).userEdited, true);
assert.ok(filledReview.fields.some(f => f.kind === 'check' && f.value === 'false'), 'unselected options remain visible to the reviewer');
assert.ok(filledReview.content.includes('___'), 'review includes source layout even when the original is outside recent history');
const reviewRequest = ChatService.request('检查我提交的表单', 'home', recentHistory, { context: '', sources: [] }, [], state, async () => '{}', undefined, JSON.stringify(filledReview));
assert.ok(reviewRequest.systemInstruction.includes('2026-11-01'));
assert.ok(reviewRequest.systemInstruction.includes('未填写或仅部分填写'));
assert.ok(reviewRequest.systemInstruction.includes('点击确认本身不代表字段齐全'));
assert.equal(reviewRequest.history.length, 12);
console.log('PASS: explicit form review carries all blank/filled/check values and full source independently of recent history.');

const manyForms = interaction.layout(Array.from({length: 200}, (_, i) => `字段${i}：___`).join('\n\n'));
assert.equal(manyForms.controls.length, 160);
assert.equal(Object.values(manyForms.inline).flat().filter(t => t.control).length, 158);
assert.equal(interaction.layout('## 清单\n- □ 水 □ 伞').controls.filter(c => c.kind === 'check').length, 2);
assert.ok(interaction.preview(form, formRecord).includes('2026-11-01'));
