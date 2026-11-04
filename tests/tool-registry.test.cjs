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
    if (name === '@kit.ArkTS') return { util: { generateRandomUUID: () => 'uuid-test' } };
    if (name === '@kit.CoreFileKit') return { fileIo: {} };
    if (!name.startsWith('.')) throw Error('Unexpected runtime dependency: ' + name);
    return load(path.relative(root, path.resolve(path.dirname(absolute), name)));
  } });
  return result;
}
const { ToolRegistry } = load('services/ToolRegistry');
const { ToolRouter } = load('services/ToolRouter');
const { ToolValidator } = load('services/ToolValidator');
const { WorkspaceService } = load('services/WorkspaceService');
const { ScheduleService } = load('services/ScheduleService');
const { AgentTaskService } = load('services/AgentTaskService');
const { StudyToolService } = load('services/StudyToolService');
const { ChatService } = load('services/ChatService');
const { FEATURE_CATALOG } = load('config/FeatureCatalog');

const WORKSPACE = ['read_workspace', 'update_task_panel', 'switch_workspace', 'run_workspace_action', 'focus_lock'];
const SCHEDULE = ['get_system_time', 'query_calendar_events', 'create_calendar_event', 'update_calendar_event',
  'delete_calendar_event', 'create_system_reminder', 'list_system_reminders', 'cancel_system_reminder', 'manage_memo'];
const ALL = WORKSPACE.concat(SCHEDULE, ['manage_agent_task', 'manage_study']);
const call = (name, args) => ({ id: 'wire-id', name, arguments: JSON.stringify(args) });
const json = text => JSON.parse(text);

// 单一登记处：定义、展示名、分类与限制必须和三个服务实际提供的工具完全一致。
const descriptors = ToolRegistry.descriptors();
assert.deepEqual(Array.from(descriptors).map(item => item.name), ALL);
assert.equal(new Set(descriptors.map(item => item.name)).size, 16);
assert.equal(ToolRegistry.category('manage_study'), 'study');
assert.equal(ToolRegistry.label('manage_study'), '管理学习课程');
const provided = WorkspaceService.tools().concat(ScheduleService.tools(), AgentTaskService.tools(), StudyToolService.tools());
assert.deepEqual(Array.from(ToolRegistry.definitions()).map(tool => tool.function.name), Array.from(provided).map(tool => tool.function.name),
  'registry definitions must not drift from the services that own them');
for (const item of descriptors) {
  assert.ok(item.label.length > 0 && item.label !== '工具请求', `${item.name} needs a registry label`);
  assert.ok(['workspace', 'schedule', 'agentTask', 'study'].includes(item.category));
  assert.ok(item.argumentLimit >= 12000);
  assert.equal(item.definition.type, 'function');
  assert.equal(typeof item.definition.function.parameters, 'object');
}
assert.equal(new Set(descriptors.map(item => item.label)).size, 16, 'labels must stay distinguishable in the execution timeline');
assert.equal(ToolRegistry.label('manage_memo'), '管理备忘录');
assert.equal(ToolRegistry.label('not_a_tool'), '工具请求');
assert.equal(ToolRegistry.handles('create_system_reminder'), true);
assert.equal(ToolRegistry.handles('create_workspace'), false);
assert.equal(ToolRegistry.category('manage_agent_task'), 'agentTask');
for (const name of SCHEDULE.concat(['manage_agent_task'])) assert.equal(ToolRegistry.blocksTimeout(name), true, `${name} must suspend the model timeout`);
for (const name of WORKSPACE.filter(item => item !== 'focus_lock')) assert.equal(ToolRegistry.blocksTimeout(name), false);
// 专注锁会拉起系统授权页与应用选择器，属于必须暂停模型超时的等待。
assert.equal(ToolRegistry.blocksTimeout('focus_lock'), true);

// 后台定时任务只能读：清单由登记表决定，运行时不再另写一份。
assert.deepEqual(Array.from(ToolRegistry.backgroundTools()).map(tool => tool.function.name),
  ['get_system_time', 'query_calendar_events', 'list_system_reminders', 'manage_memo', 'manage_study']);
assert.ok(!ToolRegistry.backgroundTools().some(tool => ['create_calendar_event', 'delete_calendar_event',
  'create_system_reminder', 'cancel_system_reminder', 'manage_agent_task', 'update_task_panel'].includes(tool.function.name)),
  'background tasks must never receive writing tools');

// 动态工作区继续只暴露现存分区，回收站不进枚举。
const dynamic = [{ id: 'home', name: '智能助理' }, { id: 'custom', name: '毕业设计', description: '论文课题', prompt: '帮助整理论文。' },
  { id: 'trash', name: '回收站' }];
assert.deepEqual(Array.from(ToolRegistry.descriptor('switch_workspace', dynamic).definition.function.parameters.properties.featureId.enum),
  ['home', 'custom']);
assert.equal(ToolRegistry.descriptors(dynamic).length, 16);

// 对话请求里的工具清单来自注册表，且与旧行为一致（16 个）。
const request = ChatService.request('继续', 'home', [], { context: '' }, [], undefined, async () => '{}');
assert.deepEqual(Array.from(request.tools).map(tool => tool.function.name), ALL);
assert.equal(ChatService.request('继续', 'home', [], { context: '' }).tools, undefined, 'integrations without a tool executor still get no tools');

// 统一校验：未知字段、类型、枚举、必填、嵌套结构与超长参数都在进入业务逻辑前被拒绝。
const switchTool = ToolRegistry.descriptor('switch_workspace');
assert.equal(json(JSON.stringify(ToolValidator.validate(switchTool, '{"featureId":"study"}'))).featureId, 'study');
for (const [raw, pattern] of [['{"featureId":"study","extra":1}', /不支持的字段：extra/], ['{"featureId":3}', /featureId类型不正确/],
  ['{"featureId":"trash"}', /featureId取值不正确/], ['{}', /缺少字段：featureId/], ['null', /参数必须是对象/], ['[]', /参数必须是对象/],
  ['{bad', /不是有效的 JSON/], ['x'.repeat(40001), /参数过长/]]) {
  assert.throws(() => ToolValidator.validate(switchTool, raw), pattern, `validator must reject ${raw.slice(0, 40)}`);
}
const panelTool = ToolRegistry.descriptor('update_task_panel');
assert.throws(() => ToolValidator.validate(panelTool, '{"tasks":[{"id":"a","title":"A"}]}'), /缺少字段：status/);
assert.throws(() => ToolValidator.validate(panelTool, '{"tasks":[{"id":"a","title":"A","status":"done"}]}'), /status取值不正确/);
assert.throws(() => ToolValidator.validate(panelTool, '{"tasks":"nope"}'), /tasks必须为数组/);
assert.equal(json(JSON.stringify(ToolValidator.validate(panelTool,
  '{"goal":"备考","tasks":[{"id":"a","title":"A","status":"pending"}]}'))).tasks.length, 1);
const memoEnum = ToolValidator.validate(ToolRegistry.descriptor('manage_memo'), '{"action":"list"}');
assert.equal(json(JSON.stringify(memoEnum)).action, 'list');
assert.throws(() => ToolValidator.validate(ToolRegistry.descriptor('manage_memo'), '{"action":"drop"}'), /action取值不正确/);

const empty = WorkspaceService.create('home');
const context = overrides => Object.assign({ featureId: 'home', workspace: empty, features: FEATURE_CATALOG,
  isActive: () => true, confirm: async () => true }, overrides);

(async () => {
  // 统一分发：未知工具、会话失效、读取、写入与失败回执。
  let result = await ToolRouter.execute(call('delete_session', {}), context());
  assert.equal(result.ok, false);
  assert.equal(json(result.output).message, '不支持的工具。');

  result = await ToolRouter.execute(call('read_workspace', {}), context({ isActive: () => false }));
  assert.equal(result.cancelled, true);
  assert.equal(json(result.output).status, 'cancelled', 'a switched conversation reports cancellation, not success');

  result = await ToolRouter.execute(call('read_workspace', {}), context());
  assert.equal(result.ok, true);
  assert.equal(result.workspace, undefined, 'reading the panel must not make the page persist it');
  assert.equal(json(result.output).message, '已读取当前任务面板。');
  assert.ok(json(result.output).workspace.includes('"featureId":"home"'));

  const panel = call('update_task_panel', { goal: '准备期中考试', tasks: [{ id: 'review', title: '复习数据结构', detail: '周三前', status: 'in_progress' }] });
  result = await ToolRouter.execute(panel, context());
  assert.equal(result.ok, true);
  assert.equal(result.workspace.state.tasks.length, 1);
  assert.equal(result.workspace.state.tasks[0].status, 'in_progress');
  assert.ok(json(result.output).workspace.includes('准备期中考试'));
  assert.equal(empty.goal, '', 'router results must not mutate the page state in place');

  result = await ToolRouter.execute(call('update_task_panel', { nope: 1 }), context());
  assert.equal(result.ok, false);
  assert.equal(json(result.output).message, '不支持的字段：nope');

  result = await ToolRouter.execute(call('update_task_panel', {}), context());
  assert.equal(result.ok, false);
  assert.ok(json(result.output).message.includes('没有提供任务面板更新内容'), 'semantic validation still belongs to the workspace service');

  result = await ToolRouter.execute(call('switch_workspace', { featureId: 'study' }), context());
  assert.equal(result.ok, true);
  assert.equal(result.workspace.featureId, 'study');
  assert.equal(result.workspace.state.tasks[0].title, WorkspaceService.create('study').tasks[0].title);

  result = await ToolRouter.execute(call('update_task_panel', { goal: 'x' }), context({ featureId: 'trash' }));
  assert.equal(result.ok, false);
  assert.ok(json(result.output).message.includes('请先恢复会话'), 'read-only trash conversations cannot write the panel');

  // 系统工具：注入的能力负责真实执行，路由只归一化回执并保留原有字段。
  result = await ToolRouter.execute(call('create_calendar_event', { title: '复习', start: '2026-10-28T19:00:00+08:00', end: '2026-10-28T20:00:00+08:00' }),
    context({ schedule: async () => JSON.stringify({ ok: true, status: 'created', message: '已创建日程',
      entries: [{ title: '复习', calendarId: 1, eventId: 2 }] }) }));
  assert.equal(result.ok, true);
  assert.equal(result.message, '已创建日程');
  assert.equal(result.moduleNotice, '已创建日程', 'real system receipts still surface as the page notice');
  assert.equal(json(result.output).entries[0].eventId, 2, 'native fields must survive normalization');

  result = await ToolRouter.execute(call('delete_calendar_event', { calendarId: 1, eventId: 2 }),
    context({ schedule: async () => JSON.stringify({ ok: false, status: 'cancelled', message: '你取消了本次日历操作，没有写入。' }) }));
  assert.equal(result.ok, false);
  assert.equal(result.cancelled, true);
  assert.equal(result.moduleNotice, '你取消了本次日历操作，没有写入。');

  result = await ToolRouter.execute(call('get_system_time', {}), context());
  assert.equal(result.ok, false);
  assert.equal(json(result.output).message, '系统日程服务尚未初始化。');

  result = await ToolRouter.execute(call('create_calendar_event', { title: '复习', start: 'bad', end: 'bad' }),
    context({ schedule: async inner => { ScheduleService.validate(inner.name, inner.arguments); return JSON.stringify({ ok: true, message: 'ok' }) } }));
  assert.equal(result.ok, false, 'an injected capability that rejects bad input becomes a failure receipt');
  assert.ok(json(result.output).message.includes('ISO8601'), 'the real time validation error survives the router');

  // Agent 定时任务走同一分发器。
  result = await ToolRouter.execute(call('manage_agent_task', { action: 'list' }),
    context({ agentTask: async () => JSON.stringify({ ok: true, message: '已读取Agent定时任务。', tasks: [{ id: 't1', title: '晨报' }] }) }));
  assert.equal(result.ok, true);
  assert.equal(json(result.output).tasks[0].title, '晨报');
  assert.equal(result.moduleNotice, undefined, 'agent task receipts are not schedule notices');

  // 业务适配器：成功时写入摘要与产物，失败时如实返回且不改面板。
  const study = WorkspaceService.create('study');
  result = await ToolRouter.execute(call('run_workspace_action', { action: 'plan', input: '本周' }), context({
    featureId: 'study', workspace: study,
    module: async () => ({ ok: true, message: '已生成学习时间块', items: [{ id: 'b1', title: '时间块', detail: '周三 19:00 复习' }] }) }));
  assert.equal(result.ok, true);
  assert.equal(result.moduleNotice, '已生成学习时间块');
  assert.equal(result.moduleItems.length, 1);
  const artifact = result.workspace.state.artifacts.find(item => item.id === 'module-study-plan');
  assert.ok(artifact && artifact.content.includes('周三 19:00 复习'), 'successful module results are saved as an artifact');
  assert.ok(result.workspace.state.summary.includes('已生成学习时间块'));
  assert.ok(json(result.output).workspace.includes('module-study-plan'));

  result = await ToolRouter.execute(call('run_workspace_action', { action: 'plan', input: '本周' }), context({
    featureId: 'study', workspace: study, module: async () => ({ ok: false, message: '学习课程服务尚未接入。', items: [] }) }));
  assert.equal(result.ok, false);
  assert.equal(result.workspace, undefined, 'a failed module must not rewrite the panel');
  assert.deepEqual(Array.from(result.moduleItems), []);
  assert.equal(json(result.output).message, '学习课程服务尚未接入。');

  result = await ToolRouter.execute(call('run_workspace_action', { action: 'export', input: 'x' }), context({ featureId: 'study' }));
  assert.equal(result.ok, false, 'unsupported actions stay rejected by the owning service');
  assert.ok(json(result.output).message.includes('当前工作区不支持该业务操作'));

  result = await ToolRouter.execute(call('run_workspace_action', { action: 'plan', input: 'x' }), context({
    featureId: 'study', module: async () => { throw new Error('适配器异常'); } }));
  assert.equal(result.ok, false);
  assert.equal(json(result.output).message, '适配器异常', 'thrown adapters become a truthful failure receipt');

  // 取消发生在业务结果返回之后：不能把迟到结果写进新会话。
  let live = true;
  result = await ToolRouter.execute(call('run_workspace_action', { action: 'plan', input: 'x' }), context({
    featureId: 'study', isActive: () => live,
    module: async () => { live = false; return { ok: true, message: '已生成', items: [] } } }));
  assert.equal(result.cancelled, true);
  assert.equal(result.workspace, undefined);

  // 超长回执保留结论与截断说明，不把成功说成失败，也不撑爆上下文。
  result = await ToolRouter.execute(call('query_calendar_events', { start: '2026-10-28T00:00:00+08:00', end: '2026-10-29T00:00:00+08:00' }),
    context({ schedule: async () => JSON.stringify({ ok: true, message: 'x'.repeat(30000) }) }));
  assert.equal(result.ok, true);
  assert.ok(result.output.length < 4000, 'oversized receipts are capped before returning to the model');
  assert.ok(json(result.output).message.includes('已省略其余内容'));
  assert.equal(json(result.output).ok, true);

  // 模型收到无法解析的回执时按失败处理，不冒充成功。
  result = await ToolRouter.execute(call('list_system_reminders', {}), context({ schedule: async () => 'not json' }));
  assert.equal(result.ok, false);
  assert.ok(json(result.output).message.includes('无法识别'));

  console.log('PASS: single tool registry, schema validation, unified routing, injected native capabilities, artifact receipts, cancellation and context-safe output caps.');
})().catch(error => { console.error(error); process.exit(1); });