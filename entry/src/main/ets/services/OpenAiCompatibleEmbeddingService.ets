import { http } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { QueryEmbedder } from '../models/RagModels'

export interface EmbeddingApiSettings {
  baseUrl: string
  model: string
  apiKey: string
  dimensions: number
}

interface EmbeddingRequest {
  model: string
  input: string[]
  dimensions?: number
}

interface EmbeddingItem {
  index?: number
  embedding?: number[]
}

interface EmbeddingError {
  message?: string
}

interface EmbeddingResponse {
  data?: EmbeddingItem[]
  error?: EmbeddingError
}

export class OpenAiCompatibleEmbeddingService implements QueryEmbedder {
  private static readonly LOG_DOMAIN: number = 0xD005
  private static readonly LOG_TAG: string = 'EmbeddingAPI'
  modelId: string
  private settings: EmbeddingApiSettings
  private activeRequests: http.HttpRequest[] = []

  constructor(settings: EmbeddingApiSettings) {
    this.settings = {
      baseUrl: settings.baseUrl.trim(),
      model: settings.model.trim(),
      apiKey: settings.apiKey.trim(),
      dimensions: Math.max(0, Math.min(4096, Math.round(settings.dimensions)))
    }
    if (!this.settings.baseUrl || !this.settings.model) throw new Error('请填写Embedding服务地址和模型名称。')
    this.modelId = this.settings.dimensions > 0
      ? `${this.settings.model}@${this.settings.dimensions}` : this.settings.model
  }

  cancel(): void {
    this.activeRequests.forEach((request: http.HttpRequest) => request.destroy())
    this.activeRequests = []
  }

  async embed(query: string): Promise<number[]> {
    const vectors = await this.embedBatch([query])
    return vectors[0]
  }

  async embedBatch(queries: string[]): Promise<number[][]> {
    if (queries.length === 0 || queries.length > 64) throw new Error('单次Embedding请求需包含1至64条文本。')
    const input = queries.map((query: string): string => {
      const text = query.trim()
      if (!text || text.length > 12000) throw new Error('参与向量化的单条文本需为1至12000字符。')
      return text
    })
    const headers: Record<string, string> = { 'content-type': 'application/json', 'accept': 'application/json' }
    if (this.settings.apiKey.length > 0) headers['authorization'] = `Bearer ${this.settings.apiKey}`
    const body: EmbeddingRequest = { model: this.settings.model, input: input }
    if (this.settings.dimensions > 0) body.dimensions = this.settings.dimensions
    const client = http.createHttp()
    this.activeRequests.push(client)
    hilog.info(OpenAiCompatibleEmbeddingService.LOG_DOMAIN, OpenAiCompatibleEmbeddingService.LOG_TAG,
      'Embedding request started')
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 30000,
        header: headers
      }
      const response = await client.request(this.embeddingsUrl(), options)
      const text = typeof response.result === 'string' ? response.result : JSON.stringify(response.result)
      let parsed: EmbeddingResponse | undefined = undefined
      try { parsed = JSON.parse(text) as EmbeddingResponse } catch (_error) {}
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(parsed?.error?.message || `Embedding服务请求失败（HTTP ${response.responseCode}）。`)
      }
      if (parsed === undefined || !Array.isArray(parsed.data) || parsed.data.length !== input.length) {
        throw new Error('Embedding服务返回格式不正确。')
      }
      const vectors: number[][] = new Array<number[]>(input.length)
      parsed.data.forEach((item: EmbeddingItem, position: number) => {
        const index = item.index === undefined ? position : item.index
        if (!Number.isInteger(index) || index < 0 || index >= input.length || !Array.isArray(item.embedding)) {
          throw new Error('Embedding服务返回的向量索引无效。')
        }
        if (this.settings.dimensions > 0 && item.embedding.length !== this.settings.dimensions) {
          throw new Error(`Embedding维度不一致，期望${this.settings.dimensions}，实际${item.embedding.length}。`)
        }
        if (vectors[index] !== undefined || !item.embedding.every((value: number) => Number.isFinite(value))) {
          throw new Error('Embedding服务返回了重复索引或无效数值。')
        }
        vectors[index] = item.embedding
      })
      if (vectors.some((vector: number[]) => !Array.isArray(vector))) {
        throw new Error('Embedding服务缺少部分输入对应的向量。')
      }
      return vectors
    } catch (error) {
      hilog.error(OpenAiCompatibleEmbeddingService.LOG_DOMAIN, OpenAiCompatibleEmbeddingService.LOG_TAG,
        'Embedding request failed')
      const message = (error as Error).message
      throw new Error(message || '连接Embedding服务失败，请检查网络、地址和API Key。')
    } finally {
      this.activeRequests = this.activeRequests.filter((request: http.HttpRequest) => request !== client)
      client.destroy()
    }
  }

  private embeddingsUrl(): string {
    let base = this.settings.baseUrl
    while (base.endsWith('/')) base = base.slice(0, base.length - 1)
    if (base.endsWith('/embeddings')) return base
    return `${base}/embeddings`
  }
}
