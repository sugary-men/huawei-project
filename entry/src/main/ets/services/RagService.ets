import { RagConfig } from '../config/RagConfig'
import { KnowledgeChunk, KnowledgeRepository, QueryEmbedder, RankedChunk, RetrievalOptions,
  RetrievalResult, SourceCitation } from '../models/RagModels'

export class RagService {
  private repository: KnowledgeRepository
  private embedder: QueryEmbedder | undefined
  constructor(repository: KnowledgeRepository, embedder?: QueryEmbedder) {
    this.repository = repository
    this.embedder = embedder
  }

  static tokens(text: string): string[] {
    const parts: string[] = text.toLowerCase().match(/[a-z0-9]+|[\u4e00-\u9fff]+/g) || []
    const tokens: string[] = []
    parts.forEach((part: string) => {
      if (/^[\u4e00-\u9fff]+$/.test(part) && part.length > 1) {
        for (let i = 0; i < part.length - 1; i++) tokens.push(part.substring(i, i + 2))
      } else {
        tokens.push(part)
      }
    })
    return tokens
  }

  static cosine(a: number[], b: number[]): number {
    if (a.length === 0 || a.length !== b.length) return 0
    let dot = 0
    let aa = 0
    let bb = 0
    for (let i = 0; i < a.length; i++) {
      if (!Number.isFinite(a[i]) || !Number.isFinite(b[i])) return 0
      dot += a[i] * b[i]
      aa += a[i] * a[i]
      bb += b[i] * b[i]
    }
    return aa > 0 && bb > 0 ? Math.max(0, Math.min(1, dot / Math.sqrt(aa * bb))) : 0
  }

  async search(query: string, options: RetrievalOptions = RagConfig.defaults()): Promise<RetrievalResult> {
    const snapshot = this.repository.snapshot()
    const result: RetrievalResult = {
      query: query.trim().slice(0, 500), revision: snapshot.revision, status: 'empty',
      mode: 'keyword', notice: '', sources: [], context: ''
    }
    const seen = new Set<string>()
    const chunks = snapshot.chunks.filter((chunk: KnowledgeChunk) => {
      if (!chunk.id || !chunk.sourceId || !chunk.content.trim() || seen.has(chunk.id)) return false
      seen.add(chunk.id)
      return options.course === '' || chunk.course === options.course
    })
    if (!result.query) { result.notice = '请输入检索问题。'; return result }
    if (chunks.length === 0) { result.notice = '当前范围没有资料，请载入资料或切换课程。'; return result }
    const queryTokens = Array.from(new Set<string>(RagService.tokens(result.query)))
    if (queryTokens.length === 0) { result.status = 'miss'; result.notice = '请输入文字或英文关键词。'; return result }
    let queryVector: number[] = []
    let modelId = ''
    if (this.embedder !== undefined) {
      modelId = this.embedder.modelId
      try {
        queryVector = await this.embedder.embed(result.query)
        if (RagService.cosine(queryVector, queryVector) === 0) queryVector = []
      } catch (_) {
        result.notice = '向量服务暂不可用，已使用关键词检索。'
      }
    }
    const corpus = chunks.map((chunk: KnowledgeChunk): string[] => RagService.tokens(`${chunk.title} ${chunk.content}`))
    const averageLength = corpus.reduce((total: number, row: string[]) => total + row.length, 0) / chunks.length
    const frequencies = queryTokens.map((token: string): number => corpus.filter((row: string[]) => row.indexOf(token) >= 0).length)
    let hybrid = false
    const ranked: RankedChunk[] = chunks.map((chunk: KnowledgeChunk, index: number): RankedChunk => {
      const row = corpus[index]
      let bm25 = 0
      let matched = 0
      queryTokens.forEach((token: string, tokenIndex: number) => {
        const tf = row.filter((value: string) => value === token).length
        if (tf > 0) {
          matched++
          const idf = Math.log(1 + (chunks.length - frequencies[tokenIndex] + 0.5) / (frequencies[tokenIndex] + 0.5))
          bm25 += idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * row.length / Math.max(1, averageLength)))
        }
      })
      const lexical = 0.55 * bm25 / (bm25 + 2) + 0.45 * matched / queryTokens.length
      const usableVector = modelId.length > 0 && chunk.vectorModel === modelId &&
        queryVector.length > 0 && chunk.vector.length === queryVector.length && RagService.cosine(chunk.vector, chunk.vector) > 0
      if (usableVector) hybrid = true
      const semantic = usableVector ? RagService.cosine(queryVector, chunk.vector) : 0
      return { chunk: chunk, score: usableVector ? 0.55 * lexical + 0.45 * semantic : lexical }
    })
    result.mode = hybrid ? 'hybrid' : 'keyword'
    ranked.sort((a: RankedChunk, b: RankedChunk): number => b.score - a.score || a.chunk.id.localeCompare(b.chunk.id))
    const counts = new Map<string, number>()
    const contents = new Set<string>()
    let remaining = Math.max(0, Math.min(8000, Math.floor(options.contextChars)))
    const topK = Math.max(1, Math.min(10, Math.floor(options.topK)))
    const maxPerSource = Math.max(1, Math.min(10, Math.floor(options.maxPerSource)))
    for (let i = 0; i < ranked.length && result.sources.length < topK && remaining > 0; i++) {
      const item = ranked[i]
      const count = counts.get(item.chunk.sourceId) || 0
      const normalized = item.chunk.content.replace(/\s+/g, ' ').trim()
      if (item.score < Math.max(0.01, options.minScore) || count >= maxPerSource || contents.has(normalized)) continue
      const excerpt = item.chunk.content.slice(0, Math.min(900, remaining))
      const citation: SourceCitation = {
        number: result.sources.length + 1, chunkId: item.chunk.id, sourceId: item.chunk.sourceId,
        title: item.chunk.title, location: item.chunk.location, course: item.chunk.course,
        excerpt: excerpt, score: item.score
      }
      result.sources.push(citation)
      counts.set(item.chunk.sourceId, count + 1)
      contents.add(normalized)
      remaining -= excerpt.length
    }
    result.status = result.sources.length > 0 ? 'hit' : 'miss'
    if (result.status === 'miss') result.notice = '未找到足够相关的资料。请更换关键词或补充资料；当前不会自动联网。'
    result.context = result.sources.length > 0 ? JSON.stringify(result.sources) : ''
    return result
  }
}
