import { AgentApiSettings } from '../config/ApiConfig'
import { ProviderAdapter, ProviderKind } from '../models/ProviderModels'
import { OpenAiProvider } from './providers/OpenAiProvider'
import { AnthropicProvider } from './providers/AnthropicProvider'

// 显式指定优先；未指定时按服务地址判断，默认按 OpenAI 兼容处理。
export class ProviderFactory {
  static kindFor(baseUrl: string, hint: string = ProviderKind.auto): string {
    if (hint === ProviderKind.openAi || hint === ProviderKind.anthropic) return hint
    const url = baseUrl.trim().toLowerCase()
    if (url.indexOf('anthropic') >= 0 || url.endsWith('/messages')) return ProviderKind.anthropic
    return ProviderKind.openAi
  }

  static create(settings: AgentApiSettings, hint: string = ProviderKind.auto): ProviderAdapter {
    return ProviderFactory.kindFor(settings.baseUrl, hint) === ProviderKind.anthropic
      ? new AnthropicProvider(settings) : new OpenAiProvider(settings)
  }
}