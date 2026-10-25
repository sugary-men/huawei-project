import { AgentGateway, AgentRequest, ModuleAdapter, ModuleResult, StreamSink, VoiceAdapter } from '../models/IntegrationModels'
import { SourceCitation, KnowledgeRepository, QueryEmbedder } from '../models/RagModels'
import { MemoryKnowledgeRepository } from './KnowledgeService'
import { RagService } from './RagService'
import { AgentApiSettings } from '../config/ApiConfig'
import { OpenAiCompatibleGateway } from './OpenAiCompatibleGateway'
import { common } from '@kit.AbilityKit'
import { HarmonyVoiceAdapter } from './HarmonyVoiceAdapter'

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
  static embedder: QueryEmbedder | undefined = undefined
  static agent: AgentGateway = new OpenAiCompatibleGateway({ baseUrl: '', model: '', apiKey: '' })
  static agentSettings: AgentApiSettings = { baseUrl: '', model: '', apiKey: '' }
  static forms: ModuleAdapter = new UnavailableModule('表单')
  static study: ModuleAdapter = new UnavailableModule('学习课程')
  static hardware: ModuleAdapter = new UnavailableModule('自律魔方')
  static voice: VoiceAdapter = new UnavailableVoice()
  static initializeVoice(context: common.UIAbilityContext): void {
    if (IntegrationService.voice instanceof UnavailableVoice) IntegrationService.voice = new HarmonyVoiceAdapter(context)
  }
  static rag(): RagService { return new RagService(IntegrationService.knowledge, IntegrationService.embedder) }
  static configureAgent(settings: AgentApiSettings): void {
    IntegrationService.agentSettings = { baseUrl: settings.baseUrl.trim(), model: settings.model.trim(), apiKey: settings.apiKey.trim() }
    IntegrationService.agent = new OpenAiCompatibleGateway(IntegrationService.agentSettings)
  }
}
