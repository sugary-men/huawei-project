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
  vm.runInNewContext(compiled, { exports: result, require: name => {
    if (!name.startsWith('.')) throw Error('Unexpected runtime dependency: ' + name);
    return load(path.relative(root, path.resolve(path.dirname(absolute), name)));
  } });
  return result;
}
const { WorkspaceService: service } = load('services/WorkspaceService');
const { WORKSPACE_PROFILES: profiles, WorkspaceConfig } = load('config/WorkspaceConfig');
const { ChatService } = load('services/ChatService');
assert.equal(profiles.length, 10);
assert.equal(new Set(profiles.map(p => p.instruction)).size, 10);
for (const profile of profiles) {
  assert.ok(profile.instruction.length > 50);
  assert.ok(profile.starters.length >= 2);
  assert.equal(service.create(profile.id).tasks[0].status, 'pending');
}
let state = service.create('home');
const original = JSON.stringify(state);
const tasks = [{ id: 'review', title: '复习数据结构', detail: '周三前完成', status: 'in_progress' }];
state = service.update(state, { goal: '准备期中考试', tasks,
  artifacts: [{ id: 'plan', title: '复习计划', content: '## 第一周\n复习树与图。' }] });
assert.equal(state.tasks.length, 1);
tasks[0].title = 'outside mutation';
assert.equal(state.tasks[0].title, '复习数据结构');
assert.equal(JSON.parse(original).goal, '');
for (const patch of [{ tasks: [null] }, { tasks: [{ id: 'x', title: 'x', status: 'fake' }] },
  { tasks: [state.tasks[0], state.tasks[0]] }, { artifacts: [{ id: '', title: 'x', content: 'x' }] },
  { goal: 'x'.repeat(501) }, { tasks: new Array(13).fill(state.tasks[0]) }]) {
  const before = JSON.stringify(state);
  assert.throws(() => service.update(state, patch));
  assert.equal(JSON.stringify(state), before, 'invalid updates must not partially mutate state');
}
const read = service.applyTool('read_workspace', '{}', 'home', state);
read.state.goal = 'outside mutation';
assert.equal(state.goal, '准备期中考试');
const changed = service.applyTool('switch_workspace', '{"featureId":"study"}', 'home', state);
assert.equal(changed.featureId, 'study');
assert.equal(changed.state.artifacts[0].id, 'plan');
assert.equal(changed.state.goal, state.goal);
assert.equal(changed.state.tasks[0].title, WorkspaceConfig.profile('study').steps[0]);
assert.equal(service.restore('home', state).updatedAt, state.updatedAt, 'restoring a panel must preserve its time');
assert.equal(service.restore('home', { goal: 123 }).goal, '', 'invalid old panel should fall back safely');
for (const [name, args, feature] of [['delete_session', '{}', 'home'], ['switch_workspace', '{"featureId":"secret"}', 'home'],
  ['update_task_panel', 'null', 'home'], ['run_workspace_action', '{"action":"export"}', 'study']]) {
  assert.throws(() => service.applyTool(name, args, feature, state));
}
assert.equal(service.applyTool('run_workspace_action', '{"action":"plan","input":"test"}', 'study', state).action, 'plan');
assert.equal(new Set(service.tools().map(tool => tool.function.name)).size, 5);
const focusStart = service.applyTool('focus_lock', '{"action":"start","durationMinutes":25}', 'focus', state);
assert.equal(focusStart.action, 'start');
assert.deepEqual(JSON.parse(focusStart.input), { durationMinutes: 25, useWhitelist: true });
assert.equal(service.applyTool('focus_lock', '{"action":"stop"}', 'focus', state).action, 'stop');
assert.equal(service.applyTool('focus_lock', '{"action":"status"}', 'focus', state).action, 'status');
assert.throws(() => service.applyTool('focus_lock', '{"action":"start","durationMinutes":0}', 'focus', state), /1-1440/);
assert.throws(() => service.applyTool('focus_lock', '{"action":"start","durationMinutes":25}', 'home', state), /自律魔方/);
const request = ChatService.request('请继续', 'study', [], { context: '', sources: [] }, [], state, async () => '{}');
assert.ok(request.systemInstruction.includes('课程资料与学习计划助手'));
assert.ok(request.systemInstruction.includes('准备期中考试'));
assert.ok(request.systemInstruction.includes('周三前完成'));
assert.ok(request.systemInstruction.includes('人工修改'));
assert.equal(request.tools.length, 15);
assert.ok(request.tools.some(tool => tool.function.name === 'manage_agent_task'));
assert.ok(request.tools.some(tool => tool.function.name === 'create_calendar_event'));
assert.ok(request.tools.some(tool => tool.function.name === 'create_system_reminder'));
assert.equal(ChatService.request('hello', 'home', [], { context: '' }).tools, undefined, 'old integrations need no tools');
const dynamic = [{ id: 'home', name: '智能助理' }, { id: 'custom', name: '毕业设计', description: '论文课题与答辩', prompt: '帮助整理论文与答辩材料。' }, { id: 'trash', name: '回收站' }];
assert.deepEqual(Array.from(service.tools(dynamic)[2].function.parameters.properties.featureId.enum), ['home', 'custom']);
assert.equal(JSON.parse(service.snapshot('home', state, dynamic)).workspaces.length, 2);
assert.equal(service.applyTool('switch_workspace', '{"featureId":"custom"}', 'home', state, dynamic).featureId, 'custom');
assert.throws(() => service.applyTool('switch_workspace', '{"featureId":"study"}', 'home', state, dynamic), /不存在/);
assert.throws(() => service.applyTool('switch_workspace', '{"featureId":"trash"}', 'home', state, dynamic));
assert.throws(() => service.applyTool('update_task_panel', '{"goal":"test"}', 'trash', state, dynamic));
assert.throws(() => service.applyTool('create_workspace', '{"name":"new"}', 'home', state, dynamic));
assert.equal(WorkspaceConfig.profile('custom', dynamic).instruction, '帮助整理论文与答辩材料。');
assert.equal(service.restore('custom', undefined, dynamic).tasks[0].title, '明确目标与要求');
const classification = ChatService.request('论文计划', 'home', [], { context: '', sources: [] }, [], state, async () => '{}', dynamic);
assert.ok(classification.systemInstruction.includes('主动调用 switch_workspace'));
assert.ok(classification.systemInstruction.includes('没有合适分区时归入或保留在智能助理 home'));
assert.ok(classification.systemInstruction.includes('论文课题与答辩'));
assert.ok(!JSON.parse(service.snapshot('home', state, dynamic)).workspaces.some(w => w.id === 'trash'));
console.log('PASS: nine workspace presets, validated atomic panel changes, workspace switching, artifact preservation and contextual requests.');
