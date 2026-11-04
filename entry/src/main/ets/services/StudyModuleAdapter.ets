import { ModuleAdapter, ModuleItem, ModuleResult } from '../models/IntegrationModels'
import { StudyCourse, StudyPlan, StudyTask } from '../models/StudyModels'
import { StudyService } from './StudyService'
import { StudyStore } from './StudyStore'

// 学习助手页面的业务入口：课表、导入、提醒、计划、打卡。与对话工具共用同一份本地存档。
export class StudyModuleAdapter implements ModuleAdapter {
  private store: StudyStore | undefined

  constructor(store?: StudyStore) {
    this.store = store
  }

  private item(id: string, title: string, detail: string): ModuleItem {
    return { id: id, title: title, detail: detail }
  }

  async execute(action: string, input: string): Promise<ModuleResult> {
    const store = this.store
    if (store === undefined) return { ok: false, message: '学习课程服务尚未初始化。', items: [] }
    try {
      if (action === 'summary') {
        const lines = StudyService.summary(store.read(), new Date())
        return { ok: true, message: lines.join('\n'), items: [] }
      }
      if (action === 'timetable') {
        const archive = store.read()
        if (archive.courses.length === 0) {
          return { ok: true, message: '课表为空。可以把课表粘贴到输入框后点击“导入课表”。', items: [] }
        }
        const courses = StudyService.sortedCourses(archive)
        return { ok: true, message: `共 ${courses.length} 节课。`, items: courses.map((course: StudyCourse): ModuleItem =>
          this.item(course.id, StudyService.courseLine(course),
            `${course.location || '地点未填写'} · ${course.teacher || '教师未填写'}`)) }
      }
      if (action === 'import') {
        if (!input.trim()) return { ok: false, message: '请先把课表粘贴到输入框，再点击“导入课表”。', items: [] }
        const courses = store.importTimetable(input)
        return { ok: true, message: `已导入并覆盖为 ${courses.length} 节课。`, items: courses.map((course: StudyCourse): ModuleItem =>
          this.item(course.id, StudyService.courseLine(course), course.location || '地点未填写')) }
      }
      if (action === 'reminders') {
        const pending = StudyService.pendingTasks(store.read())
        if (pending.length === 0) return { ok: true, message: '没有待完成的作业或考试。', items: [] }
        return { ok: true, message: `待完成 ${pending.length} 项。`, items: pending.map((task: StudyTask): ModuleItem =>
          this.item(task.id, task.title, `${task.kind === 'exam' ? '考试' : '作业'} · ${task.course || '未关联课程'} · 截止 ${task.due}`)) }
      }
      if (action === 'plan') {
        const plans = StudyService.autoPlan(store.read(), new Date())
        if (plans.length === 0) return { ok: true, message: '未来 7 天没有需要安排的学习任务。', items: [] }
        store.savePlans(plans)
        return { ok: true, message: `已生成 ${plans.length} 项学习计划。`, items: plans.map((plan: StudyPlan): ModuleItem =>
          this.item(plan.id, `${plan.date} ${plan.title}`, `${plan.minutes} 分钟`)) }
      }
      if (action === 'checkin') {
        const text = input.trim()
        const minutes = /^\d{1,3}$/.test(text) ? Number(text) : 25
        if (minutes <= 0 || minutes > 600) return { ok: false, message: '打卡分钟数应为 1–600。', items: [] }
        const record = store.checkin(minutes, /^\d+$/.test(text) ? '' : text.slice(0, 200))
        const streak = StudyService.checkinStreak(store.read(), new Date())
        return { ok: true, message: `已打卡 ${record.minutes} 分钟，连续打卡 ${streak} 天。`,
          items: [this.item(record.id, `今天学习 ${record.minutes} 分钟`, record.note || `连续 ${streak} 天`)] }
      }
      return { ok: false, message: '学习课程暂不支持该操作。', items: [] }
    } catch (error) {
      return { ok: false, message: (error as Error).message || '学习课程操作失败。', items: [] }
    }
  }
}