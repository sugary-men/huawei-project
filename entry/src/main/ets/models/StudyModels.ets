// 学习课程（M3）的本地数据模型：课表、作业与考试、学习计划、打卡。
export interface StudyCourse {
  id: string
  name: string
  weekday: number
  start: string
  end: string
  location: string
  teacher: string
}

export interface StudyTask {
  id: string
  kind: string
  course: string
  title: string
  due: string
  done: boolean
}

export interface StudyPlan {
  id: string
  title: string
  date: string
  minutes: number
  done: boolean
}

export interface StudyCheckin {
  id: string
  date: string
  minutes: number
  note: string
}

export interface StudyArchive {
  version: number
  courses: StudyCourse[]
  tasks: StudyTask[]
  plans: StudyPlan[]
  checkins: StudyCheckin[]
  updatedAt: number
}

// manage_study 工具的参数；未提供的字段表示保持原值。
export interface StudyArgs {
  action: string
  id?: string
  name?: string
  weekday?: number
  start?: string
  end?: string
  location?: string
  teacher?: string
  course?: string
  title?: string
  kind?: string
  due?: string
  minutes?: number
  note?: string
  text?: string
}

export class StudyLimits {
  static readonly courses: number = 60
  static readonly tasks: number = 200
  static readonly plans: number = 200
  static readonly checkins: number = 400
  static readonly importLines: number = 120
  static readonly textLength: number = 20000
}