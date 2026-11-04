import { AgentGateway, AgentRequest, StreamSink } from '../models/IntegrationModels'
import { AgentApiSettings } from '../config/ApiConfig'
import { LlmClient } from './LlmClient'
import { ProviderKind } from '../models/ProviderModels'

// 单配置兼容入口：外部集成仍可只给一组设置；多配置与降级请直接用 LlmClient。
export class OpenAiCompatibleGateway implements AgentGateway {
  name: string = ''
  private client: LlmClient

  constructor(settings: AgentApiSettings) {
    this.client = new LlmClient([{ label: settings.model, model: settings.model.trim(),
      baseUrl: settings.baseUrl.trim(), apiKey: settings.apiKey.trim(), kind: ProviderKind.openAi }])
    this.name = this.client.name
  }

  generate(request: AgentRequest, sink: StreamSink): Promise<void> {
    return this.client.generate(request, sink)
  }

  cancel(): void {
    this.client.cancel()
  }
}