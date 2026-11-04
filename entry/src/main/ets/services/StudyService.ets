import { StudyArchive, StudyCheckin, StudyCourse, StudyLimits, StudyPlan, StudyTask } from '../models/StudyModels'

// 学习课程的纯逻辑：解析课表文本、校验存档、生成计划、汇总今日事项。不接触文件与 UI。
export class StudyService {
  static readonly weekdays: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']

  static empty(): StudyArchive {
    return { version: 1, courses: [], tasks: [], plans: [], checkins: [], updatedAt: 0 }
  }

  static dateKey(date: Date): string {
    const month = `${date.getMonth() + 1}`.padStart(2, '0')
    const day = `${date.getDate()}`.padStart(2, '0')
    return `${date.getFullYear()}-${month}-${day}`
  }

  static weekdayIndex(date: Date): number {
    const day = date.getDay()
    return day === 0 ? 7 : day
  }

  static weekdayOf(text: string): number {
    const value = text.trim()
    for (let index = 0; index < StudyService.weekdays.length; index++) {
      if (value === StudyService.weekdays[index] || value === `星期${StudyService.weekdays[index].slice(1)}`) return index + 1
    }
    if (/^[1-7]$/.test(value)) return Number(value)
    throw new Error(`星期格式不正确：${text}，请用周一至周日或 1–7。`)
  }

  static validTime(text: string): boolean {
    if (!/^\d{1,2}:\d{2}$/.test(text)) return false
    const hour = Number(text.slice(0, text.indexOf(':')))
    const minute = Number(text.slice(text.indexOf(':') + 1))
    return hour <= 23 && minute <= 59
  }

  // 同时校验格式与真实日期：2026-13-01、2026-02-30 都要拒绝。
  static validDue(text: string): boolean {
    const match = /^(\d{4})-(\d{2})-(\d{2})(?: (\d{1,2}):(\d{2}))?$/.exec(text)
    if (match === null) return false
    const year = Number(match[1])
    const month = Number(match[2])
    const day = Number(match[3])
    if (month < 1 || month > 12 || day < 1 || day > 31) return false
    const date = new Date(year, month - 1, day)
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return false
    if (match[4] !== undefined && (Number(match[4]) > 23 || Number(match[5]) > 59)) return false
    return true
  }

  static validate(value: StudyArchive): boolean {
    if (!value || value.version !== 1 || !Array.isArray(value.courses) || !Array.isArray(value.tasks) ||
      !Array.isArray(value.plans) || !Array.isArray(value.checkins)) return false
    if (value.courses.length > StudyLimits.courses || value.tasks.length > StudyLimits.tasks ||
      value.plans.length > StudyLimits.plans || value.checkins.length > StudyLimits.checkins) return false
    const ids = new Set<string>()
    const unique = (id: string): boolean => { if (typeof id !== 'string' || !id || ids.has(id)) return false; ids.add(id); return true }
    return value.courses.every((item: StudyCourse) => unique(item.id) && typeof item.name === 'string' &&
        item.name.length > 0 && item.name.length <= 60 && Number.isInteger(item.weekday) && item.weekday >= 1 && item.weekday <= 7 &&
        StudyService.validTime(item.start) && StudyService.validTime(item.end) && item.start < item.end &&
        typeof item.location === 'string' && item.location.length <= 60 &&
        typeof item.teacher === 'string' && item.teacher.length <= 40) &&
      value.tasks.every((item: StudyTask) => unique(item.id) && (item.kind === 'homework' || item.kind === 'exam') &&
        typeof item.title === 'string' && item.title.length > 0 && item.title.length <= 120 &&
        typeof item.course === 'string' && item.course.length <= 60 && StudyService.validDue(item.due) && typeof item.done === 'boolean') &&
      value.plans.every((item: StudyPlan) => unique(item.id) && typeof item.title === 'string' && item.title.length > 0 &&
        item.title.length <= 120 && /^\d{4}-\d{2}-\d{2}$/.test(item.date) && Number.isInteger(item.minutes) &&
        item.minutes > 0 && item.minutes <= 600 && typeof item.done === 'boolean') &&
      value.checkins.every((item: StudyCheckin) => unique(item.id) && /^\d{4}-\d{2}-\d{2}$/.test(item.date) &&
        Number.isInteger(item.minutes) && item.minutes > 0 && item.minutes <= 1440 &&
        typeof item.note === 'string' && item.note.length <= 200)
  }

  static restore(value?: StudyArchive): StudyArchive {
    if (value === undefined) return StudyService.empty()
    if (!StudyService.validate(value)) throw new Error('学习课程存档格式不正确，原文件已保留。')
    return { version: 1, courses: value.courses.slice(), tasks: value.tasks.slice(),
      plans: value.plans.slice(), checkins: value.checkins.slice(), updatedAt: value.updatedAt }
  }

  // 支持两种行格式：`数据结构 | 周一 | 08:00 | 09:40 | A101 | 王老师`，或 `周一 08:00-09:40 数据结构`。
  static parseTimetable(text: string): StudyCourse[] {
    if (typeof text !== 'string' || text.length > StudyLimits.textLength) throw new Error('课表文本为空或过长。')
    const lines = text.split('\n').map((line: string) => line.trim())
      .filter((line: string) => line.length > 0 && !line.startsWith('#'))
    if (lines.length === 0) throw new Error('没有可导入的课表内容。')
    if (lines.length > StudyLimits.importLines) throw new Error(`一次最多导入 ${StudyLimits.importLines} 节课。`)
    const courses: StudyCourse[] = []
    const seen = new Set<string>()
    lines.forEach((line: string, index: number) => {
      const parts = line.split('|').map((part: string) => part.trim())
      let name = ''
      let weekday = 0
      let start = ''
      let end = ''
      let location = ''
      let teacher = ''
      if (parts.length >= 4) {
        name = parts[0]
        weekday = StudyService.weekdayOf(parts[1])
        start = parts[2]
        end = parts[3]
        location = parts.length > 4 ? parts[4] : ''
        teacher = parts.length > 5 ? parts[5] : ''
      } else {
        const match = /^(周[一二三四五六日]|星期[一二三四五六日]|[1-7])\s+(\d{1,2}:\d{2})\s*[-~—到至]\s*(\d{1,2}:\d{2})\s+(.+)$/.exec(line)
        if (match === null) throw new Error(`第${index + 1}行格式不正确，示例：数据结构 | 周一 | 08:00 | 09:40 | A101 | 王老师`)
        weekday = StudyService.weekdayOf(match[1])
        start = match[2]
        end = match[3]
        name = match[4]
      }
      if (!name || name.length > 60) throw new Error(`第${index + 1}行课程名称无效。`)
      if (!StudyService.validTime(start) || !StudyService.validTime(end) || start >= end) {
        throw new Error(`第${index + 1}行时间不正确，开始时间需早于结束时间，例如 08:00 与 09:40。`)
      }
      if (location.length > 60 || teacher.length > 40) throw new Error(`第${index + 1}行地点或教师过长。`)
      const key = `${name}|${weekday}|${start}|${end}`
      if (seen.has(key)) return
      seen.add(key)
      if (courses.length >= StudyLimits.courses) throw new Error(`最多保存 ${StudyLimits.courses} 节课，请先整理课表。`)
      courses.push({ id: `course-${index + 1}-${courses.length + 1}`, name: name, weekday: weekday,
        start: start, end: end, location: location, teacher: teacher })
    })
    if (courses.length === 0) throw new Error('没有可导入的课表内容。')
    return courses
  }

  static courseLine(course: StudyCourse): string {
    return `${StudyService.weekdays[course.weekday - 1]} ${course.start}-${course.end} ${course.name}`
  }

  static sortedCourses(archive: StudyArchive): StudyCourse[] {
    return archive.courses.slice().sort((a: StudyCourse, b: StudyCourse) => a.weekday - b.weekday || a.start.localeCompare(b.start))
  }

  static pendingTasks(archive: StudyArchive): StudyTask[] {
    return archive.tasks.filter((item: StudyTask) => !item.done).sort((a: StudyTask, b: StudyTask) => a.due.localeCompare(b.due))
  }

  static tasksToday(archive: StudyArchive, today: Date): StudyCourse[] {
    const weekday = StudyService.weekdayIndex(today)
    return StudyService.sortedCourses(archive).filter((course: StudyCourse) => course.weekday === weekday)
  }

  static addDays(dateKey: string, days: number): string {
    const year = Number(dateKey.slice(0, 4))
    const month = Number(dateKey.slice(5, 7))
    const day = Number(dateKey.slice(8, 10))
    return StudyService.dateKey(new Date(year, month - 1, day + days))
  }

  // 依据待完成作业与考试生成未来一周的学习计划：截止前一天复习 45 分钟，当天到期的排到今天。
  static autoPlan(archive: StudyArchive, today: Date): StudyPlan[] {
    const start = StudyService.dateKey(today)
    const limit = StudyService.addDays(start, 7)
    const plans: StudyPlan[] = []
    const seen = new Set<string>()
    StudyService.pendingTasks(archive).forEach((task: StudyTask) => {
      const dueDate = task.due.slice(0, 10)
      if (dueDate < start || dueDate > limit) return
      const target = dueDate === start ? start : StudyService.addDays(dueDate, -1)
      if (target < start) return
      const title = `复习：${task.title}`
      const key = `${target}|${title}`
      if (seen.has(key)) return
      seen.add(key)
      if (plans.length >= 14) return
      plans.push({ id: `plan-${plans.length + 1}`, title: title, date: target, minutes: 45, done: false })
    })
    return plans.sort((a: StudyPlan, b: StudyPlan) => a.date.localeCompare(b.date))
  }

  static checkinStreak(archive: StudyArchive, today: Date): number {
    const days = new Set<string>(archive.checkins.map((item: StudyCheckin) => item.date))
    let streak = 0
    let cursor = StudyService.dateKey(today)
    while (days.has(cursor) && streak < 365) {
      streak++
      cursor = StudyService.addDays(cursor, -1)
    }
    return streak
  }

  // 今日概览：课程、待办截止、计划与打卡，供对话与学习页共用。
  static summary(archive: StudyArchive, today: Date): string[] {
    const lines: string[] = []
    const courses = StudyService.tasksToday(archive, today)
    const weekday = StudyService.weekdays[StudyService.weekdayIndex(today) - 1]
    lines.push(courses.length === 0 ? `今天（${weekday}）没有课。`
      : `今天（${weekday}）${courses.length} 节课：${courses.map((course: StudyCourse) => `${course.start}-${course.end} ${course.name}`).join('；')}`)
    const pending = StudyService.pendingTasks(archive)
    const todayKey = StudyService.dateKey(today)
    if (pending.length === 0) {
      lines.push('没有待完成的作业或考试。')
    } else {
      const next = pending[0]
      const overdue = pending.filter((task: StudyTask) => task.due.slice(0, 10) < todayKey).length
      lines.push(`待完成 ${pending.length} 项${overdue > 0 ? `（其中 ${overdue} 项已过截止）` : ''}；最近：${next.title}（${next.due}）`)
    }
    const plans = archive.plans.filter((item: StudyPlan) => item.date === todayKey && !item.done)
    lines.push(plans.length === 0 ? '今天没有安排学习计划。'
      : `今天 ${plans.length} 项学习计划：${plans.map((item: StudyPlan) => `${item.title} ${item.minutes} 分钟`).join('；')}`)
    const minutes = archive.checkins.filter((item: StudyCheckin) => item.date === todayKey)
      .reduce((total: number, item: StudyCheckin) => total + item.minutes, 0)
    lines.push(minutes === 0 ? '今天还没有打卡。' : `今天已学习 ${minutes} 分钟，连续打卡 ${StudyService.checkinStreak(archive, today)} 天。`)
    return lines
  }
}