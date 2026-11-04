import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { AgentApiSettings, AgentApiProfile, AgentProfileArchive, AgentProfileSummary } from '../config/ApiConfig'
import { preferences } from '@kit.ArkData'

export class LocalAgentConfigService {
  static readonly maxProfiles: number = 20
  private static readonly archiveKey: string = 'profiles_v1'

  static empty(): AgentProfileArchive { return { version: 1, activeId: '', items: [] } }
  static blank(): AgentApiSettings { return { baseUrl: '', model: '', apiKey: '' } }

  private static settings(value: AgentApiSettings): AgentApiSettings {
    if (!value || typeof value.baseUrl !== 'string' || typeof value.model !== 'string' || typeof value.apiKey !== 'string') throw new Error('模型配置格式不正确。')
    const result: AgentApiSettings = { baseUrl: value.baseUrl.trim(), model: value.model.trim(), apiKey: value.apiKey.trim() }
    if (!/^https?:\/\/[^/\s?#]+(?:[/?][^\s#]*)?$/.test(result.baseUrl) || result.baseUrl.length > 2048) throw new Error('请填写以http://或https://开头的完整服务地址。')
    if (!result.model || result.model.length > 160 || /[\r\n]/.test(result.model)) throw new Error('请填写1–160字的模型名称。')
    if (result.apiKey.length > 8192 || /[\r\n]/.test(result.apiKey)) throw new Error('API Key格式不正确，请检查长度或换行。')
    return result
  }

  // 旧配置没有该字段，按自动判断处理；未知取值视为损坏，不静默改写。
  static providerKind(value?: string): string {
    if (value === undefined || value === '') return ''
    if (value === 'openai' || value === 'anthropic') return value
    throw new Error('服务商类型不正确。')
  }

  private static validate(value: AgentProfileArchive): AgentProfileArchive {
    if (!value || value.version !== 1 || typeof value.activeId !== 'string' || !Array.isArray(value.items) || value.items.length > LocalAgentConfigService.maxProfiles) throw new Error('已保存的模型配置读取失败，原配置已保留。')
    const ids = new Set<string>()
    const items: AgentApiProfile[] = value.items.map((item: AgentApiProfile): AgentApiProfile => {
      if (!item || typeof item.id !== 'string' || !item.id || item.id.length > 80 || ids.has(item.id) || typeof item.name !== 'string' || !item.name.trim() || item.name.length > 60) throw new Error('已保存的模型配置格式不正确，原配置已保留。')
      ids.add(item.id)
      const settings = LocalAgentConfigService.settings(item)
      return { id: item.id, name: item.name.trim(), baseUrl: settings.baseUrl, model: settings.model, apiKey: settings.apiKey,
        provider: LocalAgentConfigService.providerKind(item.provider) }
    })
    if (value.activeId && !ids.has(value.activeId)) throw new Error('当前模型配置不存在，原配置已保留。')
    return { version: 1, activeId: value.activeId, items: items }
  }

  static readProfiles(context: common.Context): AgentProfileArchive | undefined {
    const text = preferences.getPreferencesSync(context, { name: 'agent_runtime' }).getSync(LocalAgentConfigService.archiveKey, '') as string
    if (!text) return undefined
    try { return LocalAgentConfigService.validate(JSON.parse(text) as AgentProfileArchive) }
    catch (_error) { throw new Error('已保存的模型配置读取失败，原配置已保留。') }
  }

  private static write(context: common.Context, archive: AgentProfileArchive): AgentProfileArchive {
    const next = LocalAgentConfigService.validate(archive)
    const store = preferences.getPreferencesSync(context, { name: 'agent_runtime' })
    const before = store.getSync(LocalAgentConfigService.archiveKey, '') as string
    const legacy = store.getSync('settings', '') as string
    try {
      store.putSync(LocalAgentConfigService.archiveKey, JSON.stringify(next))
      store.deleteSync('settings')
      store.flushSync()
    } catch (_error) {
      try {
        if (before) store.putSync(LocalAgentConfigService.archiveKey, before)
        else store.deleteSync(LocalAgentConfigService.archiveKey)
        if (legacy) store.putSync('settings', legacy)
        else store.deleteSync('settings')
        store.flushSync()
      } catch (_rollbackError) {}
      throw new Error('模型配置保存失败，请检查本机存储后重试。')
    }
    return next
  }

  static summaries(archive: AgentProfileArchive): AgentProfileSummary[] {
    return archive.items.map((item: AgentApiProfile): AgentProfileSummary => ({ id: item.id, name: item.name, model: item.model }))
  }

  static activeProfile(archive: AgentProfileArchive): AgentApiProfile | undefined {
    return archive.items.find((item: AgentApiProfile) => item.id === archive.activeId)
  }

  static active(archive: AgentProfileArchive): AgentApiSettings {
    const profile = LocalAgentConfigService.activeProfile(archive)
    return profile ? { baseUrl: profile.baseUrl, model: profile.model, apiKey: profile.apiKey } : LocalAgentConfigService.blank()
  }

  static save(context: common.Context, id: string, name: string, settings: AgentApiSettings, activate: boolean,
    provider: string = ''): AgentProfileArchive {
    const archive = LocalAgentConfigService.readProfiles(context) || LocalAgentConfigService.empty()
    const normalized = LocalAgentConfigService.settings(settings)
    const kind = LocalAgentConfigService.providerKind(provider)
    const title = name.trim() || normalized.model.slice(0, 60)
    if (title.length > 60) throw new Error('配置名称最多60字。')
    if (id && !archive.items.some((item: AgentApiProfile) => item.id === id)) throw new Error('该配置已被删除，请重新选择。')
    if (!id && archive.items.length >= LocalAgentConfigService.maxProfiles) throw new Error('最多保存20组模型配置，请先删除不再使用的配置。')
    const profile: AgentApiProfile = { id: id || util.generateRandomUUID(), name: title, baseUrl: normalized.baseUrl,
      model: normalized.model, apiKey: normalized.apiKey, provider: kind }
    const index = archive.items.findIndex((item: AgentApiProfile) => item.id === profile.id)
    if (index < 0) archive.items.push(profile)
    else archive.items[index] = profile
    if (activate) archive.activeId = profile.id
    return LocalAgentConfigService.write(context, archive)
  }

  static select(context: common.Context, id: string): AgentProfileArchive {
    const archive = LocalAgentConfigService.readProfiles(context)
    if (!archive || !archive.items.some((item: AgentApiProfile) => item.id === id)) throw new Error('请选择已保存的模型配置。')
    archive.activeId = id
    return LocalAgentConfigService.write(context, archive)
  }

  static remove(context: common.Context, id: string): AgentProfileArchive {
    const archive = LocalAgentConfigService.readProfiles(context)
    if (!archive || !archive.items.some((item: AgentApiProfile) => item.id === id)) throw new Error('该配置已被删除，请刷新后重试。')
    archive.items = archive.items.filter((item: AgentApiProfile) => item.id !== id)
    if (archive.activeId === id) archive.activeId = archive.items[0]?.id || ''
    return LocalAgentConfigService.write(context, archive)
  }

  // Compatibility for native task callers. Empty selection never revives bundled settings.
  static saveRuntime(context: common.Context, settings: AgentApiSettings): void {
    const archive = LocalAgentConfigService.readProfiles(context) || LocalAgentConfigService.empty()
    if (!settings.baseUrl.trim() && !settings.model.trim() && !settings.apiKey.trim()) {
      archive.activeId = ''; LocalAgentConfigService.write(context, archive); return
    }
    LocalAgentConfigService.save(context, archive.activeId, settings.model, settings, true)
  }

  private static legacy(context: common.Context): AgentApiSettings | undefined {
    const text = preferences.getPreferencesSync(context, { name: 'agent_runtime' }).getSync('settings', '') as string
    if (!text) return undefined
    try {
      const saved = JSON.parse(text) as AgentApiSettings
      if (saved && saved.baseUrl === '' && saved.model === '' && saved.apiKey === '') return LocalAgentConfigService.blank()
      return LocalAgentConfigService.settings(saved)
    } catch (_error) { throw new Error('原有模型配置读取失败，原配置已保留。') }
  }

  private static async bundled(context: common.Context): Promise<AgentApiSettings | undefined> {
    try {
      const rawFile = await context.resourceManager.getRawFileContent('local_api.json')
      return LocalAgentConfigService.settings(JSON.parse(util.TextDecoder.create().decodeToString(rawFile)) as AgentApiSettings)
    } catch (_error) { return undefined }
  }

  static async loadProfiles(context: common.Context): Promise<AgentProfileArchive> {
    const existing = LocalAgentConfigService.readProfiles(context)
    if (existing) return existing
    const old = LocalAgentConfigService.legacy(context)
    const settings = old || await LocalAgentConfigService.bundled(context)
    // A save made while the resource read was pending wins over migration.
    const latest = LocalAgentConfigService.readProfiles(context)
    if (latest) return latest
    if (settings?.baseUrl && settings.model) return LocalAgentConfigService.save(context, '', settings.model, settings, true)
    return LocalAgentConfigService.write(context, LocalAgentConfigService.empty())
  }

  static async load(context: common.Context): Promise<AgentApiSettings | undefined> {
    try {
      // Background abilities may outlive a foreground model switch. Refresh
      // their process-local preference cache before selecting the next model.
      preferences.removePreferencesFromCacheSync(context, 'agent_runtime')
      const archive = LocalAgentConfigService.readProfiles(context)
      if (archive) return LocalAgentConfigService.active(archive)
      return LocalAgentConfigService.legacy(context) || await LocalAgentConfigService.bundled(context)
    } catch (_error) { return undefined }
  }
}
