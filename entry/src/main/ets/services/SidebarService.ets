import { FeatureDefinition } from '../models/AppModels'
import { UiTheme } from '../config/UiTheme'
import { PanelResizeResult, SidebarPreferences, SidebarView, SidebarWorkspaceGroup } from '../models/SidebarModels'
import { SessionSummary } from './SessionService'

export class SidebarService {
  static readonly workspacePreviewCount: number = 3
  static readonly recentPreviewCount: number = 8

  static panelMinimum(side: string, fontScale: number = 0.9): number {
    const scale = Number.isFinite(fontScale) ? Math.max(1, Math.min(1.3, fontScale)) : 1
    return Math.round((side === 'left' ? 220 : 244) * scale)
  }

  static resize(side: string, start: number, offset: number, maximum: number, fontScale: number): PanelResizeResult {
    const minimum = SidebarService.panelMinimum(side, fontScale)
    const desired = start + (side === 'left' ? offset : -offset)
    if (!Number.isFinite(desired)) return { width: minimum, collapsed: false }
    return { width: Math.round(Math.max(minimum, Math.min(Math.max(minimum, maximum), desired))),
      collapsed: desired <= start / 3 }
  }

  static defaults(): SidebarPreferences {
    return { workspaceSectionExpanded: true, recentSectionExpanded: true, expandedWorkspaceIds: [],
      expandedHistoryIds: [], showAllRecent: false, panelVisible: true, taskPanelVisible: true,
      leftWidth: 256, rightWidth: 274, fontScale: 0.9, themeId: UiTheme.defaultThemeId }
  }

  static normalize(value?: SidebarPreferences): SidebarPreferences {
    const fallback = SidebarService.defaults()
    if (value === undefined || value === null || typeof value !== 'object') return fallback
    const scale = typeof value.fontScale === 'number' && Number.isFinite(value.fontScale) ? Math.min(1.3, Math.max(0.8, value.fontScale)) : 0.9
    return { workspaceSectionExpanded: typeof value.workspaceSectionExpanded === 'boolean' ? value.workspaceSectionExpanded : true,
      recentSectionExpanded: typeof value.recentSectionExpanded === 'boolean' ? value.recentSectionExpanded : true,
      expandedWorkspaceIds: Array.isArray(value.expandedWorkspaceIds) ? value.expandedWorkspaceIds
        .filter((id: string) => typeof id === 'string').slice(0, 30) : [],
      expandedHistoryIds: Array.isArray(value.expandedHistoryIds) ? value.expandedHistoryIds
        .filter((id: string) => typeof id === 'string').slice(0, 30) : [],
      showAllRecent: typeof value.showAllRecent === 'boolean' ? value.showAllRecent : false,
      fontScale: scale,
      themeId: UiTheme.normalizeTheme(value.themeId),
      taskPanelVisible: typeof value.taskPanelVisible === 'boolean' ? value.taskPanelVisible : true,
      panelVisible: typeof value.panelVisible === 'boolean' ? value.panelVisible : true,
      leftWidth: Math.max(SidebarService.panelMinimum('left', scale), typeof value.leftWidth === 'number' && Number.isFinite(value.leftWidth) ? Math.min(400, value.leftWidth) : 256),
      rightWidth: Math.max(SidebarService.panelMinimum('right', scale), typeof value.rightWidth === 'number' && Number.isFinite(value.rightWidth) ? Math.min(420, value.rightWidth) : 274) }
  }

  static view(sessions: SessionSummary[], features: FeatureDefinition[], preferences: SidebarPreferences, query: string = ''): SidebarView {
    const sorted = sessions.slice().sort((a: SessionSummary, b: SessionSummary) =>
      b.updatedAt - a.updatedAt || b.createdAt - a.createdAt || a.id.localeCompare(b.id))
    const needle = query.trim().toLocaleLowerCase()
    const groups: SidebarWorkspaceGroup[] = []
    const matchingIds = new Set<string>()
    features.forEach((feature: FeatureDefinition) => {
      const featureMatch = feature.name.toLocaleLowerCase().includes(needle)
      const own = sorted.filter((session: SessionSummary) => session.featureId === feature.id &&
        (!needle || featureMatch || session.title.toLocaleLowerCase().includes(needle)))
      if (feature.id === 'trash') own.sort((a: SessionSummary, b: SessionSummary) => (b.deletedAt || 0) - (a.deletedAt || 0))
      own.forEach((session: SessionSummary) => matchingIds.add(session.id))
      if (needle && !featureMatch && own.length === 0) return
      const all = needle.length > 0 || preferences.expandedHistoryIds.includes(feature.id)
      groups.push({ feature: feature, sessions: all ? own : own.slice(0, SidebarService.workspacePreviewCount),
        totalCount: own.length, expanded: needle.length > 0 || preferences.expandedWorkspaceIds.includes(feature.id), showAll: all })
    })
    const active = sorted.filter((session: SessionSummary) => session.featureId !== 'trash')
    const recent = needle ? active.filter((session: SessionSummary) => matchingIds.has(session.id) || session.title.toLocaleLowerCase().includes(needle)) : active
    return { workspaces: groups, recent: preferences.showAllRecent || needle ? recent : recent.slice(0, SidebarService.recentPreviewCount),
      recentCount: recent.length }
  }
}
