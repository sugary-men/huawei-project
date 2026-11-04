import { AgentProfileArchive, AgentApiProfile } from '../config/ApiConfig'
import { LlmCandidate, ProviderKind } from '../models/ProviderModels'

// 把已保存的配置整理成降级链：当前选中的排第一，其余可用的按保存顺序跟在后面。
export class AgentCandidates {
  static build(archive: AgentProfileArchive): LlmCandidate[] {
    const usable = archive.items.filter((item: AgentApiProfile): boolean =>
      item.baseUrl.trim().length > 0 && item.model.trim().length > 0)
    const primary = usable.filter((item: AgentApiProfile): boolean => item.id === archive.activeId)
    const rest = usable.filter((item: AgentApiProfile): boolean => item.id !== archive.activeId)
    return primary.concat(rest).map((item: AgentApiProfile): LlmCandidate => ({
      label: item.name.length > 0 ? item.name : item.model,
      model: item.model,
      baseUrl: item.baseUrl,
      apiKey: item.apiKey,
      kind: item.provider === undefined ? ProviderKind.auto : item.provider
    }))
  }
}