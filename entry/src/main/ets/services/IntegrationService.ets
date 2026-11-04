import { AgentGateway, AgentRequest, ModuleAdapter, ModuleResult, StreamSink, VoiceAdapter } from '../models/IntegrationModels'
import { SourceCitation, KnowledgeRepository, QueryEmbedder } from '../models/RagModels'
import { MemoryKnowledgeRepository, xuanShenKnowledgeIndex } from './KnowledgeService'
import { RagService } from './RagService'
import { AgentApiSettings } from '../config/ApiConfig'
import { LlmCandidate } from '../models/ProviderModels'
import { LlmClient } from './LlmClient'
import { OpenAiCompatibleGateway } from './OpenAiCompatibleGateway'
import { common } from '@kit.AbilityKit'
import { HarmonyVoiceAdapter } from './HarmonyVoiceAdapter'
import { PrivacyModuleAdapter } from './PrivacyModuleAdapter'
import { HarmonyScheduleAdapter } from './HarmonyScheduleAdapter'
import { SchedulePlatform } from '../models/ScheduleModels'
import { LibraryService } from './LibraryService'
import { StudyStore } from './StudyStore'
import { StudyModuleAdapter } from './StudyModuleAdapter'
import { StudentQueryEmbedder } from './StudentQueryEmbedder'
import { FocusIntegrationAdapter } from './FocusIntegrationAdapter'
import { RagWorkspaceService } from './RagWorkspaceService'

// 可运行的离线摘录模式，不冒充已经接入真实大模型。
export class ExtractiveGateway implements AgentGateway {
  name: string = '本地原文摘录'
  cancel(): void {}
  async generate(request: AgentRequest, sink: StreamSink): Promise<void> {
    if (sink.isCancelled()) return
    let content = ''
    if (request.retrieval.sources.length === 0) {
      content = request.retrieval.notice || '当前没有可引用资料。请先到知识库载入资料。'
    } else {
      content = '从资料中找到以下原文，供你核对：\n\n' + request.retrieval.sources.map((source: SourceCitation): string =>
        `[${source.number}] ${source.excerpt}`).join('\n\n')
    }
    if (!sink.isCancelled()) sink.onDelta(content)
  }
}

export class UnavailableModule implements ModuleAdapter {
  private label: string
  constructor(label: string) { this.label = label }
  async execute(_action: string, _input: string): Promise<ModuleResult> {
    return { ok: false, message: `${this.label}服务尚未接入。接入后可在此查看结果。`, items: [] }
  }
}

export class UnavailableVoice implements VoiceAdapter {
  async start(): Promise<void> { throw new Error('语音服务尚未接入，当前可使用文字输入。') }
  async stop(): Promise<string> { return '' }
  async cancel(): Promise<void> {}
  async speak(_text: string): Promise<void> { throw new Error('语音播报服务尚未接入。') }
  async stopSpeaking(): Promise<void> {}
}

// 对话网关可在聊天页配置；其他能力由各模块负责人接入。
export class IntegrationService {
  static knowledge: KnowledgeRepository = new MemoryKnowledgeRepository()
  static embedder: QueryEmbedder = new StudentQueryEmbedder()
  static library: LibraryService | undefined = undefined
  static ragWorkspace: RagWorkspaceService | undefined = undefined
  static initializeLibrary(context: common.Context): void {
    if (IntegrationService.library !== undefined) return
    const base = new MemoryKnowledgeRepository()
    base.replace(xuanShenKnowledgeIndex())
    const library = new LibraryService(context.filesDir, base)
    IntegrationService.library = library
    IntegrationService.knowledge = library
    IntegrationService.ragWorkspace = new RagWorkspaceService(context.filesDir)
  }
  static agent: AgentGateway = new OpenAiCompatibleGateway({ baseUrl: '', model: '', apiKey: '' })
  static agentSettings: AgentApiSettings = { baseUrl: '', model: '', apiKey: '' }
  static forms: ModuleAdapter = new UnavailableModule('表单')

  // M2 表单工具的官方注入点：实现 ModuleAdapter 后调用一次即可，工具层与页面无需改动。
  static initializeForms(adapter: ModuleAdapter): void {
    if (adapter === undefined || adapter === null || typeof adapter.execute !== 'function') {
      throw new Error('表单适配器必须实现 execute(action, input): Promise<ModuleResult>。')
    }
    IntegrationService.forms = adapter
  }

  static study: ModuleAdapter = new UnavailableModule('学习课程')
  static studyStore: StudyStore | undefined = undefined
  static initializeStudy(context: common.Context): void {
    if (IntegrationService.studyStore !== undefined) return
    const store = new StudyStore(context.filesDir)
    IntegrationService.studyStore = store
    IntegrationService.study = new StudyModuleAdapter(store)
  }
  static hardware: ModuleAdapter = new UnavailableModule('自律魔方')
  static privacy: ModuleAdapter = new UnavailableModule('隐私与档案')
  static voice: VoiceAdapter = new UnavailableVoice()
  static schedule: SchedulePlatform | undefined = undefined
  static initializeSchedule(context: common.UIAbilityContext): void {
    if (IntegrationService.schedule === undefined) IntegrationService.schedule = new HarmonyScheduleAdapter(context)
  }
  static initializeVoice(context: common.UIAbilityContext): void {
    if (IntegrationService.voice instanceof UnavailableVoice) IntegrationService.voice = new HarmonyVoiceAdapter(context)
  }
  static initializeFocus(context: common.UIAbilityContext): void {
    if (IntegrationService.hardware instanceof UnavailableModule) {
      IntegrationService.hardware = new FocusIntegrationAdapter(context)
    }
  }
  static disposeFocus(): void {
    if (IntegrationService.hardware instanceof FocusIntegrationAdapter) IntegrationService.hardware.dispose()
    IntegrationService.hardware = new UnavailableModule('自律魔方')
  }
  // 隐私档案独立于专注适配器，保留 main 的能力。
  static initializePrivacy(context: common.UIAbilityContext): void {
    if (IntegrationService.privacy instanceof UnavailableModule) IntegrationService.privacy = new PrivacyModuleAdapter(context)
  }
  static rag(): RagService {
    if (IntegrationService.library !== undefined && IntegrationService.ragWorkspace !== undefined) {
      return IntegrationService.ragWorkspace.createRag(IntegrationService.library,
        IntegrationService.ragWorkspace.activeBase().id)
    }
    return new RagService(IntegrationService.knowledge, IntegrationService.embedder)
  }
  static configureAgent(settings: AgentApiSettings): void {
    IntegrationService.configureAgentChain(LlmClient.candidatesOf(settings))
  }
  // 主配置在前、备用配置在后；请求失败时由 LlmClient 按顺序降级。
  static configureAgentChain(candidates: LlmCandidate[]): void {
    const primary = candidates.length > 0 ? candidates[0] : undefined
    IntegrationService.agentSettings = primary === undefined ? { baseUrl: '', model: '', apiKey: '' }
      : { baseUrl: primary.baseUrl.trim(), model: primary.model.trim(), apiKey: primary.apiKey.trim() }
    IntegrationService.agent = new LlmClient(candidates)
  }
}
