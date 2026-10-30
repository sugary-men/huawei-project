import { http } from '@kit.NetworkKit'
import { KnowledgeChunk, RankedChunk, RerankProvider } from '../models/RagModels'

export interface RerankApiSettings {
  baseUrl: string
  model: string
  apiKey: string
}

interface RerankItem {
  index?: number
  relevance_score?: number
  score?: number
}

interface RerankError {
  message?: string
}

interface RerankResponse {
  results?: RerankItem[]
  data?: RerankItem[]
  error?: RerankError
}

export class OpenAiCompatibleRerankService implements RerankProvider {
  modelId: string
  private settings: RerankApiSettings

  constructor(settings: RerankApiSettings) {
    this.settings = {
      baseUrl: settings.baseUrl.trim(),
      model: settings.model.trim(),
      apiKey: settings.apiKey.trim()
    }
    if (!this.settings.baseUrl || !this.settings.model) throw new Error('请填写重排序服务地址和模型名称。')
    this.modelId = this.settings.model
  }

  async rerank(query: string, candidates: RankedChunk[]): Promise<RankedChunk[]> {
    if (candidates.length === 0) return []
    const headers: Record<string, string> = { 'content-type': 'application/json', 'accept': 'application/json' }
    if (this.settings.apiKey.length > 0) headers['authorization'] = `Bearer ${this.settings.apiKey}`
    const client = http.createHttp()
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        extraData: JSON.stringify({
          model: this.settings.model,
          query: query.slice(0, 4000),
          documents: candidates.map((item: RankedChunk): string => item.chunk.content.slice(0, 4000)),
          top_n: candidates.length
        }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 30000,
        header: headers
      }
      const response = await client.request(this.rerankUrl(), options)
      const text = typeof response.result === 'string' ? response.result : JSON.stringify(response.result)
      let parsed: RerankResponse | undefined = undefined
      try { parsed = JSON.parse(text) as RerankResponse } catch (_error) {}
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(parsed?.error?.message || `重排序服务请求失败（HTTP ${response.responseCode}）。`)
      }
      const results = parsed?.results || parsed?.data
      if (!Array.isArray(results) || results.length === 0) throw new Error('重排序服务没有返回有效结果。')
      const seen = new Set<number>()
      const reranked: RankedChunk[] = []
      results.forEach((item: RerankItem, position: number) => {
        const index = item.index === undefined ? position : item.index
        const score = item.relevance_score === undefined ? item.score : item.relevance_score
        if (!Number.isInteger(index) || index < 0 || index >= candidates.length ||
          seen.has(index) || score === undefined || !Number.isFinite(score)) return
        seen.add(index)
        const original: KnowledgeChunk = candidates[index].chunk
        reranked.push({ chunk: original, score: Math.max(0, Math.min(1, score)) })
      })
      if (reranked.length === 0) throw new Error('重排序服务返回的索引无效。')
      return reranked
    } finally {
      client.destroy()
    }
  }

  private rerankUrl(): string {
    let base = this.settings.baseUrl
    while (base.endsWith('/')) base = base.slice(0, base.length - 1)
    if (base.endsWith('/rerank')) return base
    return `${base}/rerank`
  }
}
