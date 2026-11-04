import { FeatureDefinition } from './AppModels'
import { SessionSummary } from '../services/SessionService'

export interface SidebarPreferences {
  workspaceSectionExpanded: boolean
  recentSectionExpanded: boolean
  expandedWorkspaceIds: string[]
  expandedHistoryIds: string[]
  showAllRecent: boolean
  panelVisible: boolean
  taskPanelVisible?: boolean
  leftWidth?: number
  fontScale?: number
  themeId?: string
  rightWidth?: number
}

export interface PanelResizeResult {
  width: number
  collapsed: boolean
}

export interface SidebarWorkspaceGroup {
  feature: FeatureDefinition
  sessions: SessionSummary[]
  totalCount: number
  expanded: boolean
  showAll: boolean
}

export interface SidebarView {
  workspaces: SidebarWorkspaceGroup[]
  recent: SessionSummary[]
  recentCount: number
}
