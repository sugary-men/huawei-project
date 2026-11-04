export interface FocusCategory {
  id: string
  name: string
  color: string
  createdAt: number
}

export interface FocusCheckIn {
  id: string
  categoryId: string
  dateKey: string
  completedAt: number
  minutes: number
  source: string
}

export interface FocusAnalyticsArchive {
  version: number
  categories: FocusCategory[]
  checkIns: FocusCheckIn[]
}
