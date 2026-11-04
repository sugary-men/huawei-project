const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');

// 内存文件系统：只为 LocalJsonStore 的原子写入路径提供最小实现。
const files = new Map();
const dirs = new Set();
const fileIo = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  accessSync: p => files.has(p) || dirs.has(p),
  statSync: () => ({ mtime: 0 }),
  readTextSync: p => { if (!files.has(p)) throw Error('ENOENT'); return files.get(p) },
  openSync: p => ({ fd: p }),
  writeSync: (fd, text) => { files.set(fd, text) },
  fsyncSync: () => {},
  closeSync: () => {},
  copyFileSync: (from, to) => { if (!files.has(from)) throw Error('ENOENT'); files.set(to, files.get(from)) },
  renameSync: (from, to) => { if (!files.has(from)) throw Error('ENOENT'); files.set(to, files.get(from)); files.delete(from) },
  mkdirSync: p => { if (dirs.has(p)) throw Error('EEXIST'); dirs.add(p) },
  rmdirSync: p => { dirs.delete(p) }
};
const stubs = name => {
  if (name === '@kit.CoreFileKit') return { fileIo };
  if (name === '@kit.ArkTS') return { util: { generateRandomUUID: () => `uuid-${files.size}-${Math.random().toString(16).slice(2, 8)}` } };
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
  vm.runInNewContext(compiled, { exports: result, Date, setTimeout, clearTimeout,
    require: name => {
      if (!name.startsWith('.')) return stubs(name);
      return load(path.relative(root, path.resolve(path.dirname(absolute), name)).split(path.sep).join('/'));
    } });
  return result;
}
const { StudyService } = load('services/StudyService');
const { StudyStore } = load('services/StudyStore');
const { StudyToolService } = load('services/StudyToolService');
const { StudyModuleAdapter } = load('services/StudyModuleAdapter');

const today = new Date(2026, 10, 4); // 2026-11-04，周三
const course = (name, weekday, start, end, location) => ({ id: `c-${name}`, name, weekday, start, end, location: location || '', teacher: '' });

// 1. 课表解析：两种行格式、去重、逐行报错
{
  const parsed = StudyService.parseTimetable([
    '数据结构 | 周一 | 08:00 | 09:40 | A101 | 王老师',
    '周一 10:00-11:40 高等数学',
    '# 注释行',
    '数据结构 | 周一 | 08:00 | 09:40 | A101 | 王老师'
  ].join('\n'));
  assert.equal(parsed.length, 2, 'duplicate rows are collapsed');
  assert.equal(parsed[0].weekday, 1);
  assert.equal(parsed[0].location, 'A101');
  assert.equal(parsed[0].teacher, '王老师');
  assert.equal(parsed[1].name, '高等数学');
  assert.equal(parsed[1].start, '10:00');
  assert.throws(() => StudyService.parseTimetable('随便写一行'), /第1行格式不正确/);
  assert.throws(() => StudyService.parseTimetable('数据结构 | 周一 | 09:40 | 08:00 | A101'), /开始时间需早于结束时间/);
  assert.throws(() => StudyService.parseTimetable('数据结构 | 周八 | 08:00 | 09:40'), /星期格式不正确/);
  assert.throws(() => StudyService.parseTimetable(''), /没有可导入的课表内容/);
  assert.equal(StudyService.weekdayOf('星期三'), 3);
  assert.equal(StudyService.weekdayOf('7'), 7);
  assert.equal(StudyService.weekdayOf('周日'), 7);
}

// 2. 存档校验：字段、范围与重复 id
{
  const empty = StudyService.empty();
  assert.equal(StudyService.validate(empty), true);
  assert.equal(StudyService.validate({ ...empty, courses: [course('课', 1, '08:00', '09:40')] }), true);
  assert.equal(StudyService.validate({ ...empty, courses: [course('课', 8, '08:00', '09:40')] }), false);
  assert.equal(StudyService.validate({ ...empty, courses: [course('课', 1, '9:00', '09:40')] }), false);
  assert.equal(StudyService.validate({ ...empty, courses: [course('课', 1, '08:00', '09:40'), course('课', 1, '08:00', '09:40')] }), false,
    'duplicate ids are rejected');
  assert.equal(StudyService.validate({ ...empty, tasks: [{ id: 't', kind: 'quiz', course: '', title: 'x', due: '2026-11-10', done: false }] }), false);
  assert.equal(StudyService.validate({ ...empty, tasks: [{ id: 't', kind: 'homework', course: '', title: 'x', due: '2026/11/10', done: false }] }), false);
  assert.throws(() => StudyService.restore({ version: 2 }), /格式不正确/);
}

// 3. 学习计划：截止前一天、当天到期排今天、超范围与逾期跳过
{
  const archive = StudyService.empty();
  archive.courses = [course('数据结构', 3, '08:00', '09:40')];
  archive.tasks = [
    { id: 't1', kind: 'homework', course: '数据结构', title: '树与图作业', due: '2026-11-06', done: false },
    { id: 't2', kind: 'exam', course: '高等数学', title: '期中考试', due: '2026-11-04', done: false },
    { id: 't3', kind: 'homework', course: '英语', title: '论文', due: '2026-11-20', done: false },
    { id: 't4', kind: 'homework', course: '物理', title: '过期作业', due: '2026-11-01', done: false },
    { id: 't5', kind: 'homework', course: '数据结构', title: '已完成', due: '2026-11-06', done: true }
  ];
  const plans = StudyService.autoPlan(archive, today);
  assert.equal(plans.length, 2, 'only tasks inside the window produce a plan');
  assert.equal(plans[0].date, '2026-11-04');
  assert.equal(plans[0].title, '复习：期中考试');
  assert.equal(plans[1].date, '2026-11-05');
  assert.equal(plans[1].title, '复习：树与图作业');
  assert.equal(plans[1].minutes, 45);
}

// 4. 今日概览与连续打卡
{
  const archive = StudyService.empty();
  archive.courses = [course('数据结构', 3, '08:00', '09:40'), course('英语', 3, '14:00', '15:40'), course('物理', 1, '08:00', '09:40')];
  archive.tasks = [{ id: 't1', kind: 'homework', course: '数据结构', title: '树与图作业', due: '2026-11-06', done: false },
    { id: 't2', kind: 'homework', course: '英语', title: '过期作业', due: '2026-11-02', done: false }];
  archive.plans = [{ id: 'p1', title: '复习：树与图作业', date: '2026-11-04', minutes: 45, done: false }];
  archive.checkins = [{ id: 'k1', date: '2026-11-04', minutes: 40, note: '' },
    { id: 'k2', date: '2026-11-03', minutes: 30, note: '' }];
  const lines = StudyService.summary(archive, today);
  assert.ok(lines[0].includes('2 节课'), 'today has two courses');
  assert.ok(lines[0].includes('数据结构'));
  assert.ok(lines[1].includes('待完成 2 项'));
  assert.ok(lines[1].includes('1 项已过截止'));
  assert.ok(lines[2].includes('复习：树与图作业 45 分钟'));
  assert.ok(lines[3].includes('40 分钟'));
  assert.ok(lines[3].includes('连续打卡 2 天'));
  assert.equal(StudyService.checkinStreak(archive, today), 2);
  assert.equal(StudyService.checkinStreak(StudyService.empty(), today), 0);
}

// 5. 本地存档：导入覆盖、增删、任务、计划、打卡与损坏文件保护
{
  files.clear(); dirs.clear();
  const store = new StudyStore('/app');
  assert.equal(store.read().courses.length, 0, 'missing archive starts empty');
  const imported = store.importTimetable('数据结构 | 周一 | 08:00 | 09:40 | A101\n英语 | 周二 | 10:00 | 11:40 | B202');
  assert.equal(imported.length, 2);
  const added = store.addCourse(course('物理', 3, '14:00', '15:40', 'C303'));
  assert.equal(store.read().courses.length, 3);
  store.removeCourse(added.id);
  assert.equal(store.read().courses.length, 2);
  assert.throws(() => store.removeCourse('missing'), /课程不存在/);

  const saved = store.saveTask({ id: 'task-fixed', kind: 'exam', course: '数据结构', title: '期末考试', due: '2026-11-12', done: false });
  assert.equal(store.read().tasks.length, 1);
  assert.equal(saved.kind, 'exam');
  const finished = store.finishTask('task-fixed', true);
  assert.equal(finished.done, true);
  assert.throws(() => store.finishTask('nope', true), /不存在/);

  store.savePlans([{ id: 'plan-a', title: '复习：期末考试', date: '2026-11-11', minutes: 45, done: false }]);
  store.savePlans([{ id: 'plan-b', title: '复习：期末考试', date: '2026-11-11', minutes: 45, done: false }]);
  assert.equal(store.read().plans.length, 1, 'regenerating the same plan replaces it instead of duplicating');
  assert.equal(store.completePlan('plan-b').done, true);

  const record = store.checkin(50, '图书馆');
  assert.equal(record.minutes, 50);
  assert.equal(store.read().checkins.length, 1);

  // 主文件损坏时回退到备份；两份都损坏才报错且不覆盖原文件
  files.set('/app/study_data.json', '{broken json');
  assert.equal(new StudyStore('/app').read().courses.length, 2, 'a broken main file falls back to the last valid backup');
  files.set('/app/study_data.json.bak', '{broken json');
  assert.throws(() => new StudyStore('/app').read(), /读取失败/);
  assert.equal(files.get('/app/study_data.json'), '{broken json', 'a failed read must not overwrite the archive');
}

// 6. 工具：概要、导入、增删、任务、计划、打卡与取消
(async () => {
  files.clear(); dirs.clear();
  const store = new StudyStore('/app');
  const call = (args) => ({ id: 'wire', name: 'manage_study', arguments: JSON.stringify(args) });
  const yes = async () => true;
  const no = async () => false;
  const run = (args, confirm = yes) => StudyToolService.execute(call(args), store, () => true, confirm).then(text => JSON.parse(text));

  assert.deepEqual(Array.from(StudyToolService.tools()).map(tool => tool.function.name), ['manage_study']);
  assert.equal(StudyToolService.handles('manage_study'), true);
  assert.equal(StudyToolService.handles('manage_memo'), false);

  let receipt = await run({ action: 'summary' });
  assert.equal(receipt.ok, true);
  assert.ok(receipt.message.includes('今天'));
  assert.equal(receipt.entries, undefined);

  receipt = await run({ action: 'timetable' });
  assert.ok(receipt.message.includes('课表为空'));

  receipt = await run({ action: 'import', text: '数据结构 | 周一 | 08:00 | 09:40 | A101\n英语 | 周三 | 10:00 | 11:40 | B202' });
  assert.equal(receipt.ok, true);
  assert.ok(receipt.message.includes('2 节课'));
  assert.equal(receipt.entries.length, 2);

  receipt = await run({ action: 'import', text: '数据结构 | 周一 | 08:00 | 09:40' }, no);
  assert.equal(receipt.ok, false, 'cancelling the confirmation keeps the old timetable');
  assert.ok(receipt.message.includes('已取消'));
  assert.equal(store.read().courses.length, 2);

  receipt = await run({ action: 'add_course', name: '物理', weekday: 3, start: '14:00', end: '15:40', location: 'C303' });
  assert.equal(receipt.ok, true);
  assert.equal(store.read().courses.length, 3);
  receipt = await run({ action: 'add_course', name: '物理', weekday: 9, start: '14:00', end: '15:40' });
  assert.equal(receipt.ok, false);
  assert.ok(receipt.message.includes('1–7'));

  receipt = await run({ action: 'timetable' });
  assert.ok(receipt.message.includes('周三'));
  assert.equal(receipt.entries.length, 3);
  const removal = store.read().courses.find(item => item.name === '物理');
  receipt = await run({ action: 'remove_course', id: removal.id });
  assert.equal(receipt.ok, true);
  assert.equal(store.read().courses.length, 2);

  receipt = await run({ action: 'save_task', title: '期中考试', kind: 'exam', course: '数据结构', due: '2026-11-08' });
  assert.equal(receipt.ok, true);
  assert.equal(store.read().tasks.length, 1);
  receipt = await run({ action: 'save_task', title: '期中考试', kind: 'homework', due: '2026-13-01' });
  assert.equal(receipt.ok, false, 'invalid due dates are rejected');
  receipt = await run({ action: 'save_task', title: '缺截止', kind: 'exam' });
  assert.equal(receipt.ok, false);

  receipt = await run({ action: 'list_tasks' });
  assert.ok(receipt.message.includes('待完成 1 项'));
  assert.equal(receipt.entries.length, 1);

  const taskId = store.read().tasks[0].id;
  receipt = await run({ action: 'finish_task', id: taskId });
  assert.equal(receipt.ok, true);
  assert.equal(store.read().tasks[0].done, true);
  receipt = await run({ action: 'finish_task', id: 'missing' });
  assert.equal(receipt.ok, false);

  // 计划：先造一个未来 7 天内的待办
  await run({ action: 'save_task', title: '实验报告', kind: 'homework', due: '2026-11-06' });
  receipt = await run({ action: 'plan' });
  assert.equal(receipt.ok, true);
  assert.ok(receipt.entries.length >= 1);
  assert.equal(store.read().plans.length, receipt.entries.length);

  receipt = await run({ action: 'checkin', minutes: 30, note: '复盘' });
  assert.equal(receipt.ok, true);
  assert.ok(receipt.message.includes('30 分钟'));
  receipt = await run({ action: 'checkin', minutes: 900 });
  assert.equal(receipt.ok, false);
  assert.ok(receipt.message.includes('1–600'));

  receipt = await run({ action: 'unknown' });
  assert.equal(receipt.ok, false);
  receipt = await StudyToolService.execute(call({ action: 'summary' }), undefined, () => true, yes).then(text => JSON.parse(text));
  assert.equal(receipt.ok, false, 'missing store is reported instead of silently succeeding');

  // 7. 学习页适配器：课表、提醒、计划、打卡共用同一份存档
  const adapter = new StudyModuleAdapter(store);
  let result = await adapter.execute('timetable', '');
  assert.equal(result.ok, true);
  assert.equal(result.items.length, 2);
  result = await adapter.execute('import', '数据结构 | 周一 | 08:00 | 09:40');
  assert.equal(result.items.length, 1);
  const saved = await adapter.execute('reminders', '');
  assert.equal(saved.ok, true);
  const planned = await adapter.execute('plan', '');
  assert.equal(planned.ok, true);
  const checked = await adapter.execute('checkin', '45');
  assert.ok(checked.message.includes('45 分钟'));
  const unavailable = await new StudyModuleAdapter(undefined).execute('timetable', '');
  assert.equal(unavailable.ok, false);

  console.log('PASS: timetable parsing, archive validation, plan generation, daily summary, atomic store, tool confirmations and page adapter.');
})().catch(error => { console.error(error); process.exitCode = 1; });