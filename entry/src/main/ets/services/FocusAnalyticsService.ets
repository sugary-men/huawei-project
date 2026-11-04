import { util } from '@kit.ArkTS'
import { FocusAnalyticsArchive, FocusCategory, FocusCheckIn } from '../models/FocusAnalyticsModels'
import { LocalJsonStore } from './LocalJsonStore'

export class FocusAnalyticsService {
  private static readonly colors: string[] = ['#7FA7C9', '#89B7A0', '#D3A77E', '#A89BC5', '#C68F9E', '#8AAEB5']
  private readonly store: LocalJsonStore<FocusAnalyticsArchive>

  constructor(filesDir: string) {
    this.store = new LocalJsonStore<FocusAnalyticsArchive>(`${filesDir}/focus_analytics.json`,
      () => FocusAnalyticsService.defaults(),
      (value: FocusAnalyticsArchive) => FocusAnalyticsService.valid(value))
  }

  private static defaults(): FocusAnalyticsArchive {
    const now = Date.now()
    return {
      version: 1,
      categories: [
        { id: 'focus-study', name: '学习', color: FocusAnalyticsService.colors[0], createdAt: now },
        { id: 'focus-routine', name: '作息', color: FocusAnalyticsService.colors[1], createdAt: now },
        { id: 'focus-sport', name: '运动', color: FocusAnalyticsService.colors[2], createdAt: now }
      ],
      checkIns: []
    }
  }

  private static valid(value: FocusAnalyticsArchive): boolean {
    return value !== undefined && value !== null && value.version === 1 &&
      Array.isArray(value.categories) && value.categories.length > 0 && value.categories.length <= 8 &&
      Array.isArray(value.checkIns) && value.checkIns.length <= 5000 &&
      value.categories.every((item: FocusCategory) => typeof item.id === 'string' && item.id.length > 0 &&
        typeof item.name === 'string' && item.name.trim().length > 0 && item.name.length <= 20 &&
        typeof item.color === 'string' && item.color.length > 0 &&
        typeof item.createdAt === 'number' && Number.isFinite(item.createdAt)) &&
      value.checkIns.every((item: FocusCheckIn) => typeof item.id === 'string' && item.id.length > 0 &&
        typeof item.categoryId === 'string' && item.categoryId.length > 0 &&
        typeof item.dateKey === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(item.dateKey) &&
        typeof item.completedAt === 'number' && Number.isFinite(item.completedAt) &&
        typeof item.minutes === 'number' && Number.isFinite(item.minutes) &&
        typeof item.source === 'string')
  }

  snapshot(): FocusAnalyticsArchive {
    const value = this.store.read()
    return {
      version: value.version,
      categories: value.categories.map((item: FocusCategory): FocusCategory => ({
        id: item.id, name: item.name, color: item.color, createdAt: item.createdAt
      })),
      checkIns: value.checkIns.map((item: FocusCheckIn): FocusCheckIn => ({
        id: item.id, categoryId: item.categoryId, dateKey: item.dateKey, completedAt: item.completedAt,
        minutes: item.minutes, source: item.source
      }))
    }
  }

  addCategory(name: string): FocusAnalyticsArchive {
    const title = name.trim()
    if (!title || title.length > 20) throw new Error('类别名称需为 1 至 20 字。')
    return this.store.change((value: FocusAnalyticsArchive): FocusAnalyticsArchive => {
      if (value.categories.length >= 8) throw new Error('最多保留 8 个自律类别。')
      if (value.categories.some((item: FocusCategory) =>
        item.name.toLocaleLowerCase() === title.toLocaleLowerCase())) throw new Error('已存在同名类别。')
      value.categories.push({
        id: `focus-category-${util.generateRandomUUID()}`,
        name: title,
        color: FocusAnalyticsService.colors[value.categories.length % FocusAnalyticsService.colors.length],
        createdAt: Date.now()
      })
      return value
    })
  }

  deleteCategory(id: string): FocusAnalyticsArchive {
    return this.store.change((value: FocusAnalyticsArchive): FocusAnalyticsArchive => {
      if (value.categories.length <= 1) throw new Error('至少保留一个自律类别。')
      const index = value.categories.findIndex((item: FocusCategory) => item.id === id)
      if (index < 0) throw new Error('自律类别不存在。')
      value.categories.splice(index, 1)
      const fallback = value.categories[0].id
      value.checkIns.forEach((item: FocusCheckIn) => {
        if (item.categoryId === id) item.categoryId = fallback
      })
      return value
    })
  }

  checkIn(categoryId: string, minutes: number, source: string): FocusAnalyticsArchive {
    const safeMinutes = Math.max(1, Math.min(1440, Math.round(minutes)))
    return this.store.change((value: FocusAnalyticsArchive): FocusAnalyticsArchive => {
      if (!value.categories.some((item: FocusCategory) => item.id === categoryId)) throw new Error('请先选择自律类别。')
      const now = Date.now()
      value.checkIns.push({
        id: `focus-checkin-${util.generateRandomUUID()}`,
        categoryId: categoryId,
        dateKey: FocusAnalyticsService.dateKey(now),
        completedAt: now,
        minutes: safeMinutes,
        source: source
      })
      if (value.checkIns.length > 5000) value.checkIns.splice(0, value.checkIns.length - 5000)
      return value
    })
  }

  static dateKey(timestamp: number): string {
    const date = new Date(timestamp)
    const month = date.getMonth() + 1
    const day = date.getDate()
    return `${date.getFullYear()}-${month < 10 ? `0${month}` : `${month}`}-${day < 10 ? `0${day}` : `${day}`}`
  }
}
