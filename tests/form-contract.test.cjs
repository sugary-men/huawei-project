const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');

// M2 表单工具接入契约：不依赖设备能力，只验证接口、动作集合与工具分发路径。
const stubs = name => {
  if (name === '@kit.ArkTS') return { util: { generateRandomUUID: () => 'uuid-form' } };
  if (name === '@kit.CoreFileKit') return { fileIo: {} };
  if (name === '@kit.AbilityKit') return { common: {} };
  if (name === '@kit.CryptoArchitectureKit') return { cryptoFramework: { createMd: () => ({ update() {}, digest() { return new Uint8Array(32) } }) } };
  // 其余鸿蒙 Kit 只被 IntegrationService 的字段类型或未调用路径引用，用惰性桩避免逐个维护。
  if (name.startsWith('@kit.')) return new Proxy({}, { get: () => (() => ({})) });
  throw Error(`Unexpected dependency ${name}`);
};
const standIns = {
  'services/HarmonyVoiceAdapter': { HarmonyVoiceAdapter: class { async start() {} async stop() { return '' } async cancel() {} async speak() {} async stopSpeaking() {} } },
  'services/HarmonyScheduleAdapter': { HarmonyScheduleAdapter: class {} },
  'services/LibraryService': { LibraryService: class {} },
  'services/LlmClient': { LlmClient: class {} },
  'services/OpenAiCompatibleGateway': { OpenAiCompatibleGateway: class {} },
  'services/StudentQueryEmbedder': { StudentQueryEmbedder: class { async embed() { return [] } } },
  'services/FocusIntegrationAdapter': { FocusIntegrationAdapter: class {} },
  'services/RagWorkspaceService': { RagWorkspaceService: class {} }
};
const cache = new Map();
function load(file) {
  if (standIns[file] !== undefined) return standIns[file];
  const absolute = path.resolve(root, file + '.ets');
  if (cache.has(absolute)) return cache.get(absolute);
  const result = {};
  cache.set(absolute, result);
  const compiled = ts.transpileModule(fs.readFileSync(absolute, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInNewContext(compiled, { exports: result, setTimeout, clearTimeout,
    require: name => {
      if (!name.startsWith('.')) return stubs(name);
      return load(path.relative(root, path.resolve(path.dirname(absolute), name)).split(path.sep).join('/'));
    } });
  return result;
}
const { ToolRouter } = load('services/ToolRouter');
const { WorkspaceService } = load('services/WorkspaceService');
const { FEATURE_CATALOG } = load('config/FeatureCatalog');
const integration = load('services/IntegrationService');
const IntegrationService = integration.IntegrationService;
const UnavailableModule = integration.UnavailableModule;
const { FormModuleContract } = load('services/FormModuleContract');

const json = text => JSON.parse(text);
const call = (name, args) => ({ id: 'wire', name, arguments: JSON.stringify(args) });
const state = WorkspaceService.create('forms');
const context = overrides => Object.assign({ featureId: 'forms', workspace: state, features: FEATURE_CATALOG,
  isActive: () => true, confirm: async () => true,
  module: (featureId, action, input) => IntegrationService.forms.execute(action, input) }, overrides);

class FakeForms {
  constructor() { this.calls = []; }
  async execute(action, input) {
    this.calls.push({ action: action, input: input });
    if (action === 'templates') {
      return { ok: true, message: '共 2 个模板。', items: [
        { id: 'tpl-1', title: '差旅报销单', detail: '8 个字段' },
        { id: 'tpl-2', title: '请假申请', detail: '5 个字段' }] };
    }
    if (action === 'draft') return { ok: true, message: '已生成草稿。', items: [{ id: 'draft-1', title: '差旅报销单草稿', detail: '待填写 3 项' }] };
    if (action === 'fill') return input.length > 0
      ? { ok: true, message: '已回填 1 个字段。', items: [] }
      : { ok: false, message: '请提供要回填的字段名与新值。', items: [] };
    if (action === 'export') return { ok: true, message: '已复制草稿到剪贴板。', items: [] };
    return { ok: false, message: '不支持的表单操作。', items: [] };
  }
}

(async () => {
  // 1. 契约常量：动作集合与说明
  assert.deepEqual(Array.from(FormModuleContract.actions), ['templates', 'draft', 'export', 'fill']);
  assert.equal(FormModuleContract.accepts('templates'), true);
  assert.equal(FormModuleContract.accepts('submit'), false);
  assert.equal(FormModuleContract.summary.includes('templates'), true);
  ['templates', 'draft', 'export', 'fill'].forEach(action => {
    assert.equal(FormModuleContract.describeRequiredInput(action).length > 0, true);
  });

  // 2. 注入点拒绝不合规的适配器，不会静默接受
  assert.throws(() => IntegrationService.initializeForms(undefined), /必须实现 execute/);
  assert.throws(() => IntegrationService.initializeForms({}), /必须实现 execute/);

  // 3. 未接入时经工具层返回诚实失败，且不写入产物
  IntegrationService.forms = new UnavailableModule('表单');
  let result = await ToolRouter.execute(call('run_workspace_action', { action: 'templates', input: '' }), context());
  assert.equal(result.ok, false);
  assert.ok(json(result.output).message.includes('尚未接入'));
  assert.equal(result.moduleNotice.includes('尚未接入'), true);
  assert.equal(result.workspace, undefined, 'a failed adapter must not persist a panel change');

  // 4. 注入真实适配器后，工具层按契约取到条目并落盘产物
  const forms = new FakeForms();
  IntegrationService.initializeForms(forms);
  assert.equal(IntegrationService.forms, forms);
  result = await ToolRouter.execute(call('run_workspace_action', { action: 'templates', input: '' }), context());
  assert.equal(result.ok, true);
  assert.equal(result.message, '共 2 个模板。');
  assert.equal(result.moduleItems.length, 2);
  assert.deepEqual(Array.from(result.moduleItems).map(item => item.title), ['差旅报销单', '请假申请']);
  const artifact = result.workspace.state.artifacts.find(item => item.id === 'module-forms-templates');
  assert.ok(artifact, 'the tool result becomes a workspace artifact the page can open');
  assert.ok(artifact.content.includes('差旅报销单'));
  assert.equal(result.workspace.state.summary, '共 2 个模板。');
  assert.equal(json(result.output).ok, true);
  const snapshot = json(json(result.output).workspace);
  assert.ok(snapshot.state.artifacts.some(item => item.id === 'module-forms-templates'),
    'the model-visible snapshot carries the new artifact');

  // 5. 表单动作白名单与契约一致：四个动作都放行，未知动作被拒
  for (const action of FormModuleContract.actions) {
    const applied = WorkspaceService.applyTool('run_workspace_action',
      JSON.stringify({ action: action, input: '数量=1' }), 'forms', state, FEATURE_CATALOG);
    assert.equal(applied.action, action, `${action} must be routed to the form adapter`);
    assert.equal(applied.input, '数量=1');
  }
  assert.throws(() => WorkspaceService.applyTool('run_workspace_action',
    JSON.stringify({ action: 'submit', input: '' }), 'forms', state, FEATURE_CATALOG), /不支持该业务操作/);
  result = await ToolRouter.execute(call('run_workspace_action', { action: 'submit', input: '' }), context());
  assert.equal(result.ok, false);
  assert.ok(json(result.output).message.includes('不支持该业务操作'));

  // 6. 适配器自己返回失败时，失败原因原样透传，不包装成成功
  result = await ToolRouter.execute(call('run_workspace_action', { action: 'fill', input: '' }), context());
  assert.equal(result.ok, false);
  assert.equal(result.message, '请提供要回填的字段名与新值。');
  assert.equal(result.moduleItems.length, 0);
  assert.equal(forms.calls.at(-1).action, 'fill');
  assert.equal(forms.calls.at(-1).input, '', 'the adapter receives the exact input the model supplied');

  // 7. 适配器抛异常时由路由器收口成可核对回执
  IntegrationService.initializeForms(new (class {
    async execute() { throw new Error('模板文件损坏，请重新导入。'); }
  })());
  result = await ToolRouter.execute(call('run_workspace_action', { action: 'draft', input: '' }), context());
  assert.equal(result.ok, false);
  assert.equal(json(result.output).message, '模板文件损坏，请重新导入。');
  assert.equal(result.cancelled, false);

  // 8. 回合已结束时迟到的适配器结果只报取消，不改面板
  let active = true;
  const runner = new (class {
    async execute() { active = false; return { ok: true, message: '已生成草稿。', items: [] }; }
  })();
  IntegrationService.initializeForms(runner);
  result = await ToolRouter.execute(call('run_workspace_action', { action: 'draft', input: '' }),
    context({ isActive: () => active }));
  assert.equal(result.cancelled, true, 'a late result must not be applied to the current session');
  assert.equal(result.workspace, undefined);

  // 9. 适配器自检：合规实现无问题，形状错误逐条指出
  assert.deepEqual(Array.from(await FormModuleContract.verify(new FakeForms())), []);
  const problems = Array.from(await FormModuleContract.verify(new (class {
    async execute(action) {
      if (action === 'templates') return { ok: true, message: '', items: 'not-an-array' };
      if (action === 'draft') return { ok: 'yes', message: 'ok', items: [{ id: 'a' }] };
      if (action === 'fill') throw new Error('boom');
      return { ok: true, message: '导出', items: [] };
    }
  })()));
  assert.ok(problems.some(text => text.includes('message 不能为空')));
  assert.ok(problems.some(text => text.includes('items 必须是数组')));
  assert.ok(problems.some(text => text.includes('ok 必须是布尔值')));
  assert.ok(problems.some(text => text.includes('items[0] 需要 id/title/detail')));
  assert.ok(problems.some(text => text.includes('fill：执行抛出异常')));
  const invalid = Array.from(await FormModuleContract.verify({}));
  assert.equal(invalid.length, 1);
  assert.ok(invalid[0].includes('必须实现 execute'));

  console.log('PASS: form contract actions, adapter injection, honest unavailable result, routing, artifacts, failure passthrough, late result and self-check.');
})().catch(error => { console.error(error); process.exitCode = 1; });