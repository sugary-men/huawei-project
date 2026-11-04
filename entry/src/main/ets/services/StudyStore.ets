import { util } from '@kit.ArkTS'
import { StudyArchive, StudyCheckin, StudyCourse, StudyLimits, StudyPlan, StudyTask } from '../models/StudyModels'
import { StudyService } from './StudyService'
import { LocalJsonStore } from './LocalJsonStore'

// 学习课程的本地存档：原子写入并保留备份，读取失败不覆盖原文件。
export class StudyStore {
  private store: LocalJsonStore<StudyArchive>

  constructor(filesDir: string) {
    this.store = new LocalJsonStore<StudyArchive>(`${filesDir}/study_data.json`,
      (): StudyArchive => StudyService.empty(), (value: StudyArchive): boolean => StudyService.validate(value))
  }

  read(): StudyArchive {
    return StudyService.restore(this.store.read())
  }

  importTimetable(text: string): StudyCourse[] {
    const parsed = StudyService.parseTimetable(text)
    return this.store.change((current: StudyArchive): StudyArchive => {
      const next = StudyService.restore(current)
      next.courses = parsed
      next.updatedAt = Date.now()
      return next
    }).courses
  }

  addCourse(course: StudyCourse): StudyCourse {
    const created = this.store.change((current: StudyArchive): StudyArchive => {
      const next = StudyService.restore(current)
      if (next.courses.length >= StudyLimits.courses) throw new Error(`最多保存 ${StudyLimits.courses} 节课，请先整理课表。`)
      next.courses.push(course)
      next.updatedAt = Date.now()
      return next
    })
    return created.courses.find((item: StudyCourse) => item.id === course.id) as StudyCourse
  }

  removeCourse(id: string): StudyArchive {
    return this.store.change((current: StudyArchive): StudyArchive => {
      const next = StudyService.restore(current)
      if (!next.courses.some((item: StudyCourse) => item.id === id)) throw new Error('课程不存在，请先查看课程表。')
      next.courses = next.courses.filter((item: StudyCourse) => item.id !== id)
      next.updatedAt = Date.now()
      return next
    })
  }

  saveTask(task: StudyTask): StudyTask {
    const next = this.store.change((current: StudyArchive): StudyArchive => {
      const archive = StudyService.restore(current)
      const index = archive.tasks.findIndex((item: StudyTask) => item.id === task.id)
      if (index < 0) {
        if (archive.tasks.length >= StudyLimits.tasks) throw new Error(`最多保存 ${StudyLimits.tasks} 项作业与考试，请先清理。`)
        archive.tasks.push(task)
      } else {
        archive.tasks[index] = task
      }
      archive.updatedAt = Date.now()
      return archive
    })
    return next.tasks.find((item: StudyTask) => item.id === task.id) as StudyTask
  }

  finishTask(id: string, done: boolean): StudyTask {
    const next = this.store.change((current: StudyArchive): StudyArchive => {
      const archive = StudyService.restore(current)
      const task = archive.tasks.find((item: StudyTask) => item.id === id)
      if (task === undefined) throw new Error('作业或考试不存在，请先查询。')
      task.done = done
      archive.updatedAt = Date.now()
      return archive
    })
    return next.tasks.find((item: StudyTask) => item.id === id) as StudyTask
  }

  savePlans(plans: StudyPlan[]): StudyPlan[] {
    const next = this.store.change((current: StudyArchive): StudyArchive => {
      const archive = StudyService.restore(current)
      const keys = new Set<string>(plans.map((item: StudyPlan) => `${item.date}|${item.title}`))
      archive.plans = archive.plans.filter((item: StudyPlan) => !keys.has(`${item.date}|${item.title}`))
      plans.forEach((item: StudyPlan) => {
        if (archive.plans.length < StudyLimits.plans) archive.plans.push(item)
      })
      archive.updatedAt = Date.now()
      return archive
    })
    return next.plans
  }

  completePlan(id: string): StudyPlan {
    const next = this.store.change((current: StudyArchive): StudyArchive => {
      const archive = StudyService.restore(current)
      const plan = archive.plans.find((item: StudyPlan) => item.id === id)
      if (plan === undefined) throw new Error('学习计划不存在，请先查看计划。')
      plan.done = true
      archive.updatedAt = Date.now()
      return archive
    })
    return next.plans.find((item: StudyPlan) => item.id === id) as StudyPlan
  }

  checkin(minutes: number, note: string): StudyCheckin {
    const record: StudyCheckin = { id: StudyStore.newId('checkin'), date: StudyService.dateKey(new Date()),
      minutes: minutes, note: note }
    this.store.change((current: StudyArchive): StudyArchive => {
      const archive = StudyService.restore(current)
      if (archive.checkins.length >= StudyLimits.checkins) throw new Error('打卡记录已满，请先清理旧记录。')
      archive.checkins.push(record)
      archive.updatedAt = Date.now()
      return archive
    })
    return record
  }

  static newId(prefix: string): string {
    return `${prefix}-${util.generateRandomUUID()}`
  }
}