import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AgentApiSettings, ApiConfig } from '../../config/ApiConfig'
import { ProviderAdapter, ProviderDeltaSink, ProviderMessage, ProviderTurn } from '../../models/ProviderModels'
import { AgentToolCall, AgentToolDefinition, AgentToolProperty } from '../../models/WorkspaceModels'
import { ModelContentPart } from '../../models/AttachmentModels'

interface AnthropicSource {
  type: string
  media_type?: string
  data?: string
}

interface AnthropicBlock {
  type: string
  text?: string
  partial_json?: string
  thinking?: string
  source?: AnthropicSource
  id?: string
  name?: string
  input?: Object
  tool_use_id?: string
  content?: string
}

interface AnthropicMessage {
  role: string
  content: AnthropicBlock[]
}

interface AnthropicTool {
  name: string
  description: string
  input_schema: AgentToolProperty
}

interface AnthropicBody {
  model: string
  max_tokens: number
  system: string
  messages: AnthropicMessage[]
  tools?: AnthropicTool[]
  stream: boolean
}

interface AnthropicStreamEvent {
  type?: string
  index?: number
  delta?: AnthropicBlock
  content_block?: AnthropicBlock
  error?: AnthropicStreamEventError
  message?: string
}

interface AnthropicResponse {
  content?: AnthropicBlock[]
  error?: AnthropicStreamEventError
}

interface AnthropicStreamEventError {
  type?: string
  message?: string
}

// Anthropic Messages API：工具以 tool_use / tool_result 内容块表达，与 OpenAI 的 function calling 完全不同。
export class AnthropicProvider implements ProviderAdapter {
  private static readonly LOG_DOMAIN: number = 0xD001
  private static readonly LOG_TAG: string = 'AgentAPI'
  private static readonly maxTokens: number = 4096
  private static readonly version: string = '2023-06-01'

  readonly kind: string = 'anthropic'
  label: string = ''
  private settings: AgentApiSettings
  private activeRequests: http.HttpRequest[] = []

  constructor(settings: AgentApiSettings) {
    this.settings = { baseUrl: settings.baseUrl.trim(), model: settings.model.trim(), apiKey: settings.apiKey.trim() }
    this.label = this.settings.model
  }

  cancel(): void {
    this.activeRequests.forEach((request: http.HttpRequest) => request.destroy())
    this.activeRequests = []
  }

  async complete(system: string, messages: ProviderMessage[], tools: AgentToolDefinition[],
    sink: ProviderDeltaSink): Promise<ProviderTurn> {
    const body: AnthropicBody = { model: this.settings.model, max_tokens: AnthropicProvider.maxTokens,
      system: system, messages: AnthropicProvider.wire(messages), stream: true,
      tools: tools.length > 0 ? tools.map((tool: AgentToolDefinition): AnthropicTool => ({ name: tool.function.name,
        description: tool.function.description, input_schema: tool.function.parameters })) : undefined }
    return await this.round(body, sink)
  }

  // 连续的 tool 结果合并成一条 user 消息里的多个 tool_result 块，符合 Messages API 的要求。
  private static wire(messages: ProviderMessage[]): AnthropicMessage[] {
    const result: AnthropicMessage[] = []
    let openToolResults: AnthropicMessage | undefined = undefined
    messages.forEach((message: ProviderMessage) => {
      if (message.role === 'tool') {
        const block: AnthropicBlock = { type: 'tool_result',
          tool_use_id: message.toolCallId === undefined ? '' : message.toolCallId,
          content: typeof message.content === 'string' ? message.content : '' }
        if (openToolResults === undefined) {
          openToolResults = { role: 'user', content: [block] }
          result.push(openToolResults)
        } else {
          openToolResults.content.push(block)
        }
        return
      }
      openToolResults = undefined
      const blocks: AnthropicBlock[] = AnthropicProvider.blocks(message)
      result.push({ role: message.role === 'assistant' ? 'assistant' : 'user', content: blocks })
    })
    return result
  }

  private static blocks(message: ProviderMessage): AnthropicBlock[] {
    const blocks: AnthropicBlock[] = []
    if (message.role === 'assistant') {
      const text = typeof message.content === 'string' ? message.content : ''
      if (text.length > 0) blocks.push({ type: 'text', text: text })
      ;(message.toolCalls || []).forEach((call: AgentToolCall) => {
        let input: Object = JSON.parse('{}') as Object
        try { input = JSON.parse(call.arguments) as Object } catch (_error) { input = JSON.parse('{}') as Object }
        blocks.push({ type: 'tool_use', id: call.id, name: call.name, input: input })
      })
      return blocks
    }
    if (typeof message.content === 'string') {
      blocks.push({ type: 'text', text: message.content })
      return blocks
    }
    (message.content as ModelContentPart[]).forEach((part: ModelContentPart) => {
      if (part.type === 'image_url' && part.image_url !== undefined) {
        const url = part.image_url.url
        const comma = url.indexOf(',')
        const header = url.slice(0, comma)
        const media = header.indexOf(':') >= 0 && header.indexOf(';') >= 0 ? header.slice(header.indexOf(':') + 1, header.indexOf(';')) : 'image/jpeg'
        const source: AnthropicSource = { type: 'base64', media_type: media, data: url.slice(comma + 1) }
        blocks.push({ type: 'image', source: source })
      } else if (part.text !== undefined) {
        blocks.push({ type: 'text', text: part.text })
      }
    })
    if (blocks.length === 0) blocks.push({ type: 'text', text: '' })
    return blocks
  }

  private messagesUrl(): string {
    let base = this.settings.baseUrl.trim()
    while (base.endsWith('/')) base = base.slice(0, base.length - 1)
    if (base.endsWith('/messages')) return base
    return `${base}/messages`
  }

  private async round(body: AnthropicBody, sink: ProviderDeltaSink): Promise<ProviderTurn> {
    let assistantText = ''
    let streamError = ''
    let streamedContent = false
    let analyzing = false
    const calls = new Map<number, AgentToolCall>()
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'accept': 'text/event-stream',
      'anthropic-version': AnthropicProvider.version
    }
    if (this.settings.apiKey.length > 0) headers['x-api-key'] = this.settings.apiKey

    const client = http.createHttp()
    this.activeRequests.push(client)
    let pendingLine = ''
    let responseText = ''
    const decoder = util.TextDecoder.create('utf-8')
    hilog.info(AnthropicProvider.LOG_DOMAIN, AnthropicProvider.LOG_TAG, 'Anthropic SSE request started')

    const consumeLine = (line: string): void => {
      const trimmed = line.trim()
      if (!trimmed.startsWith('data:')) return
      const data = trimmed.slice(5).trim()
      if (data.length === 0 || data === '[DONE]') return
      try {
        const event = JSON.parse(data) as AnthropicStreamEvent
        if (event.type === 'error') {
          streamError = event.error?.message || '模型服务返回错误。'
          return
        }
        if (event.type === 'content_block_start' && event.content_block?.type === 'tool_use') {
          const index = event.index === undefined ? calls.size : event.index
          calls.set(index, { id: event.content_block.id || `call-${index}`, name: event.content_block.name || '', arguments: '' })
          return
        }
        if (event.type === 'content_block_delta' && event.delta !== undefined) {
          if (event.delta.type === 'text_delta' && event.delta.text !== undefined && !sink.isCancelled()) {
            streamedContent = true
            assistantText = (assistantText + event.delta.text).slice(0, 32000)
            sink.onDelta(event.delta.text)
          } else if (event.delta.type === 'input_json_delta' && event.delta.partial_json !== undefined) {
            const index = event.index === undefined ? 0 : event.index
            const call = calls.get(index)
            if (call !== undefined) {
              call.arguments = `${call.arguments}${event.delta.partial_json}`
              if (call.arguments.length > 40000) streamError = '模型工具参数过长。'
            }
          } else if (event.delta.type === 'thinking_delta' && !analyzing) {
            analyzing = true
            if (!sink.isCancelled()) sink.onAnalyzing()
          }
        }
      } catch (_error) {
        // Ignore incomplete or non-JSON SSE frames; the finished response is validated below.
      }
    }

    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: ApiConfig.requestTimeoutMs,
        readTimeout: ApiConfig.requestTimeoutMs,
        header: headers
      }
      client.on('dataReceive', (data: ArrayBuffer): void => {
        if (sink.isCancelled()) return
        const chunk = decoder.decodeToString(new Uint8Array(data), { stream: true })
        responseText = (responseText + chunk).slice(-200000)
        pendingLine += chunk
        if (pendingLine.length > 400000) { streamError = '模型返回的单个数据片段过大。'; pendingLine = ''; return }
        let newline = pendingLine.indexOf('\n')
        while (newline >= 0) {
          consumeLine(pendingLine.slice(0, newline))
          pendingLine = pendingLine.slice(newline + 1)
          newline = pendingLine.indexOf('\n')
        }
      })
      const responseCode = await client.requestInStream(this.messagesUrl(), options)
      hilog.info(AnthropicProvider.LOG_DOMAIN, AnthropicProvider.LOG_TAG, 'Anthropic SSE completed with HTTP %{public}d', responseCode)
      if (sink.isCancelled()) return { content: '', calls: [] }
      const trailingText = decoder.decodeToString(new Uint8Array(0), { stream: false })
      pendingLine += trailingText
      if (pendingLine.trim().length > 0) consumeLine(pendingLine)
      if (responseCode < 200 || responseCode >= 300) {
        let detail = ''
        try { detail = (JSON.parse(responseText) as AnthropicResponse).error?.message || '' } catch (_error) {}
        throw new Error(detail || `模型服务请求失败（HTTP ${responseCode}）。`)
      }
      if (streamError.length > 0) throw new Error(streamError)
      if (!streamedContent && calls.size === 0 && responseText.trim().startsWith('{')) {
        // 兼容不支持流式、直接返回完整 JSON 的网关。
        try {
          const parsed = JSON.parse(responseText) as AnthropicResponse
          ;(parsed.content || []).forEach((block: AnthropicBlock) => {
            if (block.type === 'text' && block.text !== undefined && block.text.length > 0 && !sink.isCancelled()) {
              streamedContent = true
              assistantText = block.text
              sink.onDelta(block.text)
            } else if (block.type === 'tool_use') {
              calls.set(calls.size, { id: block.id || 'call-0', name: block.name || '',
                arguments: block.input === undefined ? '{}' : JSON.stringify(block.input) })
            }
          })
        } catch (_error) {
          throw new Error('模型服务返回格式无法识别，请确认接口符合 Anthropic Messages API。')
        }
      }
      if (streamError.length > 0) throw new Error(streamError)
      if (!streamedContent && calls.size === 0) throw new Error('模型服务已响应，但没有返回回答内容。')
      const completed: AgentToolCall[] = Array.from(calls.keys()).sort((a: number, b: number) => a - b)
        .map((index: number): AgentToolCall => {
          const call = calls.get(index) as AgentToolCall
          return { id: call.id, name: call.name, arguments: call.arguments.length > 0 ? call.arguments : '{}' }
        })
      return { content: assistantText, calls: completed }
    } catch (error) {
      if (sink.isCancelled()) return { content: '', calls: [] }
      hilog.error(AnthropicProvider.LOG_DOMAIN, AnthropicProvider.LOG_TAG, 'Anthropic SSE failed')
      const message = (error as Error).message
      if (message && message.length > 0) throw new Error(message)
      throw new Error('连接模型服务失败，请检查网络、服务地址和 API Key。')
    } finally {
      this.activeRequests = this.activeRequests.filter((request: http.HttpRequest) => request !== client)
      client.destroy()
    }
  }
}