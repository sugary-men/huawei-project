import { AgentToolCall, AgentToolDefinition } from '../models/WorkspaceModels'
import { StudyArgs, StudyArchive, StudyCheckin, StudyCourse, StudyPlan, StudyTask } from '../models/StudyModels'
import { StudyService } from './StudyService'
import { StudyStore } from './StudyStore'

interface StudyEntry {
  id: string
  title: string
}

interface StudyReceipt {
  ok: boolean
  message: string
  entries?: StudyEntry[]
}

// 学习课程工具：课表、作业与考试、学习计划、打卡。写入前由页面展示内容核对。
export class StudyToolService {
  static tools(): AgentToolDefinition[] {
    return JSON.parse(`[
      {"type":"function","function":{"name":"manage_study","description":"管理本机学习数据，不联网。action=summary 今日概览；timetable 查看课表；import 用 text 导入课表（每行“数据结构 | 周一 | 08:00 | 09:40 | A101 | 王老师”或“周一 08:00-09:40 数据结构”）；add_course 按 name/weekday/start/end 新增一节课；remove_course 按 id 删除；list_tasks 查看待完成作业与考试；save_task 新建或按 id 修改（kind=homework/exam，due 为 2026-11-10 或 2026-11-10 18:00）；finish_task 按 id 标记完成；plan 依据待办生成未来 7 天复习计划；checkin 记录今日学习分钟数。写入前应用会展示内容供核对，只有真实回执才能说已保存。","parameters":{"type":"object","properties":{
        "action":{"type":"string","enum":["summary","timetable","import","add_course","remove_course","list_tasks","save_task","finish_task","plan","checkin"]},
        "id":{"type":"string"},"name":{"type":"string"},"weekday":{"type":"number"},"start":{"type":"string"},"end":{"type":"string"},
        "location":{"type":"string"},"teacher":{"type":"string"},"course":{"type":"string"},"title":{"type":"string"},
        "kind":{"type":"string","enum":["homework","exam"]},"due":{"type":"string"},"minutes":{"type":"number"},
        "note":{"type":"string"},"text":{"type":"string"}
      },"required":["action"],"additionalProperties":false}}}
    ]`) as AgentToolDefinition[]
  }

  static handles(name: string): boolean {
    return StudyToolService.tools().some((tool: AgentToolDefinition) => tool.function.name === name)
  }

  static execute(call: AgentToolCall, store: StudyStore | undefined, active: () => boolean,
    confirm: (title: string, detail: string) => Promise<boolean>): Promise<string> {
    return Promise.resolve(StudyToolService.run(call, store, active, confirm))
  }

  private static async run(call: AgentToolCall, store: StudyStore | undefined, active: () => boolean,
    confirm: (title: string, detail: string) => Promise<boolean>): Promise<string> {
    try {
      if (store === undefined) return StudyToolService.receipt(false, '学习课程服务尚未初始化。')
      if (call.arguments.length > 20000) return StudyToolService.receipt(false, '工具参数过长。')
      const args = JSON.parse(call.arguments) as StudyArgs
      if (args === null || typeof args !== 'object' || Array.isArray(args)) return StudyToolService.receipt(false, '参数必须是对象。')
      const text = (value?: string): string => value === undefined ? '' : String(value).trim()
      const needsId = (): string => {
        const id = text(args.id)
        if (!id) throw new Error('请先查询并使用真实 id。')
        return id
      }

      if (args.action === 'summary') {
        const lines = StudyService.summary(store.read(), new Date())
        return StudyToolService.receipt(true, lines.join('\n'))
      }
      if (args.action === 'timetable') {
        const archive = store.read()
        if (archive.courses.length === 0) return StudyToolService.receipt(true, '课表为空，可以说“导入课表”并粘贴内容。')
        const courses = StudyService.sortedCourses(archive)
        return StudyToolService.receipt(true, StudyToolService.courseText(courses),
          courses.map((course: StudyCourse): StudyEntry => ({ id: course.id, title: StudyService.courseLine(course) })))
      }
      if (args.action === 'import') {
        const body = text(args.text)
        if (!body) throw new Error('请提供要导入的课表文本。')
        const parsed = StudyService.parseTimetable(body)
        if (!await StudyToolService.confirm(active, confirm, '导入课表',
          `${parsed.length} 节课将覆盖当前课表：\n${parsed.slice(0, 8).map((course: StudyCourse) => StudyService.courseLine(course)).join('\n')}`)) {
          return StudyToolService.receipt(false, '已取消导入，原课表保持不变。')
        }
        const courses = store.importTimetable(body)
        return StudyToolService.receipt(true, `已导入并覆盖为 ${courses.length} 节课。`,
          courses.map((course: StudyCourse): StudyEntry => ({ id: course.id, title: StudyService.courseLine(course) })))
      }
      if (args.action === 'add_course') {
        const name = text(args.name)
        if (!name) throw new Error('请提供课程名称。')
        const weekday = args.weekday === undefined ? 0 : args.weekday
        const start = text(args.start)
        const end = text(args.end)
        if (!Number.isInteger(weekday) || weekday < 1 || weekday > 7) throw new Error('上课星期应为 1–7（周一至周日）。')
        if (!StudyService.validTime(start) || !StudyService.validTime(end) || start >= end) throw new Error('上课时间不正确，例如 08:00 与 09:40。')
        const course: StudyCourse = { id: StudyStore.newId('course'), name: name.slice(0, 60), weekday: weekday,
          start: start, end: end, location: text(args.location).slice(0, 60), teacher: text(args.teacher).slice(0, 40) }
        if (!await StudyToolService.confirm(active, confirm, '新增课程', StudyService.courseLine(course))) {
          return StudyToolService.receipt(false, '已取消新增课程。')
        }
        if (!active()) return StudyToolService.receipt(false, '生成已停止。')
        const saved = store.addCourse(course)
        return StudyToolService.receipt(true, `已新增课程：${StudyService.courseLine(saved)}。`,
          [{ id: saved.id, title: StudyService.courseLine(saved) }])
      }
      if (args.action === 'remove_course') {
        const id = needsId()
        const course = store.read().courses.find((item: StudyCourse) => item.id === id)
        if (course === undefined) throw new Error('课程不存在，请先查看课程表。')
        if (!await StudyToolService.confirm(active, confirm, '删除课程', StudyService.courseLine(course))) {
          return StudyToolService.receipt(false, '已保留该课程。')
        }
        if (!active()) return StudyToolService.receipt(false, '生成已停止。')
        store.removeCourse(id)
        return StudyToolService.receipt(true, `已删除课程：${StudyService.courseLine(course)}。`)
      }
      if (args.action === 'list_tasks') {
        const archive = store.read()
        const pending = StudyService.pendingTasks(archive)
        if (pending.length === 0) return StudyToolService.receipt(true, '没有待完成的作业或考试。')
        return StudyToolService.receipt(true,
          `待完成 ${pending.length} 项：\n${pending.map((task: StudyTask) => `· ${task.title}（${task.course || '未关联课程'}，截止 ${task.due}）`).join('\n')}`,
          pending.map((task: StudyTask): StudyEntry => ({ id: task.id, title: `${task.title}（${task.due}）` })))
      }
      if (args.action === 'save_task') {
        const title = text(args.title)
        if (!title) throw new Error('请提供作业或考试名称。')
        const kind = text(args.kind) || 'homework'
        if (kind !== 'homework' && kind !== 'exam') throw new Error('kind 只能是 homework 或 exam。')
        const due = text(args.due)
        if (!StudyService.validDue(due)) throw new Error('截止时间格式应为 2026-11-10 或 2026-11-10 18:00。')
        const existing = text(args.id) ? store.read().tasks.find((item: StudyTask) => item.id === args.id) : undefined
        const task: StudyTask = { id: existing === undefined ? StudyStore.newId('task') : existing.id,
          kind: kind, course: text(args.course).slice(0, 60), title: title.slice(0, 120), due: due,
          done: existing === undefined ? false : existing.done }
        const detail = `${kind === 'exam' ? '考试' : '作业'}：${task.title}\n课程：${task.course || '未填写'}\n截止：${task.due}`
        if (!await StudyToolService.confirm(active, confirm, existing === undefined ? '新增作业或考试' : '修改作业或考试', detail)) {
          return StudyToolService.receipt(false, '已取消保存。')
        }
        if (!active()) return StudyToolService.receipt(false, '生成已停止。')
        store.saveTask(task)
        return StudyToolService.receipt(true, `已保存${kind === 'exam' ? '考试' : '作业'}：${task.title}（截止 ${task.due}）。`,
          [{ id: task.id, title: task.title }])
      }
      if (args.action === 'finish_task') {
        const id = needsId()
        const task = store.read().tasks.find((item: StudyTask) => item.id === id)
        if (task === undefined) throw new Error('作业或考试不存在，请先查询。')
        if (!await StudyToolService.confirm(active, confirm, '标记完成', `${task.title}\n截止：${task.due}`)) {
          return StudyToolService.receipt(false, '已保留未完成状态。')
        }
        if (!active()) return StudyToolService.receipt(false, '生成已停止。')
        store.finishTask(id, true)
        return StudyToolService.receipt(true, `已标记完成：${task.title}。`, [{ id: task.id, title: task.title }])
      }
      if (args.action === 'plan') {
        const archive = store.read()
        const plans = StudyService.autoPlan(archive, new Date())
        if (plans.length === 0) return StudyToolService.receipt(true, '未来 7 天没有需要安排的学习任务。')
        const detail = plans.slice(0, 8).map((plan: StudyPlan) => `${plan.date} ${plan.title} ${plan.minutes} 分钟`).join('\n')
        if (!await StudyToolService.confirm(active, confirm, '生成学习计划', detail)) {
          return StudyToolService.receipt(false, '已取消生成计划。')
        }
        if (!active()) return StudyToolService.receipt(false, '生成已停止。')
        store.savePlans(plans)
        return StudyToolService.receipt(true, `已生成 ${plans.length} 项学习计划。`,
          plans.map((plan: StudyPlan): StudyEntry => ({ id: plan.id, title: `${plan.date} ${plan.title}` })))
      }
      if (args.action === 'checkin') {
        const minutes = args.minutes === undefined ? 25 : args.minutes
        if (!Number.isInteger(minutes) || minutes <= 0 || minutes > 600) throw new Error('打卡分钟数应为 1–600 的整数。')
        if (!await StudyToolService.confirm(active, confirm, '学习打卡', `记录今天学习 ${minutes} 分钟${text(args.note) ? `\n备注：${text(args.note)}` : ''}`)) {
          return StudyToolService.receipt(false, '已取消打卡。')
        }
        if (!active()) return StudyToolService.receipt(false, '生成已停止。')
        const record: StudyCheckin = store.checkin(minutes, text(args.note).slice(0, 200))
        const archive = store.read()
        const streak = StudyService.checkinStreak(archive, new Date())
        return StudyToolService.receipt(true, `已打卡 ${record.minutes} 分钟，连续打卡 ${streak} 天。`)
      }
      return StudyToolService.receipt(false, `不支持的学习操作：${args.action}`)
    } catch (error) {
      return StudyToolService.receipt(false, (error as Error).message || '学习课程操作失败。')
    }
  }

  // 课表文本：每周分段列出，便于模型直接读出。
  private static courseText(courses: StudyCourse[]): string {
    const groups: string[] = []
    for (let day = 1; day <= 7; day++) {
      const items = courses.filter((course: StudyCourse) => course.weekday === day)
      if (items.length === 0) continue
      groups.push(`${StudyService.weekdays[day - 1]}：${items.map((course: StudyCourse) =>
        `${course.start}-${course.end} ${course.name}${course.location ? `（${course.location}）` : ''}`).join('；')}`)
    }
    return `共 ${courses.length} 节课。\n${groups.join('\n')}`
  }

  private static async confirm(active: () => boolean, confirm: (title: string, detail: string) => Promise<boolean>,
    title: string, detail: string): Promise<boolean> {
    if (!active()) return false
    return await confirm(title, detail)
  }

  private static receipt(ok: boolean, message: string, entries?: StudyEntry[]): string {
    if (entries === undefined) return JSON.stringify({ ok: ok, message: message } as StudyReceipt)
    return JSON.stringify({ ok: ok, message: message, entries: entries } as StudyReceipt)
  }
}