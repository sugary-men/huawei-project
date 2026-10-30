import { KnowledgeChunk, KnowledgeIndex, QueryEmbedder } from '../models/RagModels'

export interface RagSourceDocument {
  id: string
  title: string
  location: string
  course: string
  text: string
  modality?: string
  mediaPath?: string
  mediaMimeType?: string
}

export interface RagChunkOptions {
  maxChars: number
  overlapChars: number
  batchSize: number
}

interface ChunkDraft {
  chunk: KnowledgeChunk
  embeddingText: string
}

export class RagIndexBuilder {
  static defaults(): RagChunkOptions {
    return { maxChars: 800, overlapChars: 120, batchSize: 24 }
  }

  static split(text: string, options: RagChunkOptions = RagIndexBuilder.defaults()): string[] {
    const content = text.trim()
    if (content.length === 0) return []
    const maxChars = Math.max(80, Math.min(4000, Math.floor(options.maxChars)))
    const overlap = Math.max(0, Math.min(maxChars - 1, Math.floor(options.overlapChars)))
    const step = maxChars - overlap
    const chunks: string[] = []
    for (let start = 0; start < content.length; start += step) {
      const value = content.slice(start, start + maxChars)
      if (value.trim().length > 0) chunks.push(value)
      if (start + maxChars >= content.length) break
    }
    return chunks
  }

  static async build(sources: RagSourceDocument[], embedder: QueryEmbedder,
    options: RagChunkOptions = RagIndexBuilder.defaults()): Promise<KnowledgeIndex> {
    const ids = new Set<string>()
    const drafts: ChunkDraft[] = []
    sources.forEach((source: RagSourceDocument) => {
      if (!source.id || ids.has(source.id) || !source.title.trim() || !source.text.trim()) {
        throw new Error('RAG资料需要唯一ID、标题和非空内容。')
      }
      ids.add(source.id)
      const modality = (source.modality || 'text').trim()
      const parts = RagIndexBuilder.split(source.text, options)
      parts.forEach((content: string, index: number) => {
        const version = RagIndexBuilder.fingerprint(content)
        const location = parts.length > 1 ? `${source.location} · 片段 ${index + 1}` : source.location
        drafts.push({
          chunk: {
            id: `${source.id}:${version}:${index}`,
            sourceId: source.id,
            title: source.title.trim(),
            location: location,
            course: source.course.trim(),
            content: content,
            vector: [],
            vectorModel: '',
            modality: modality,
            mediaPath: modality === 'image' ? source.mediaPath || '' : '',
            mediaMimeType: modality === 'image' ? source.mediaMimeType || '' : ''
          },
          embeddingText: `${source.title.trim()}\n资料模态：${RagIndexBuilder.modalityLabel(modality)}\n` +
            `${location}\n${content}`
        })
      })
    })
    if (drafts.length === 0) throw new Error('没有可向量化的RAG片段。')

    const vectors: number[][] = []
    const batchSize = Math.max(1, Math.min(64, Math.floor(options.batchSize)))
    if (embedder.embedBatch !== undefined) {
      for (let start = 0; start < drafts.length; start += batchSize) {
        const batch = drafts.slice(start, start + batchSize).map((item: ChunkDraft): string => item.embeddingText)
        const result = await embedder.embedBatch(batch)
        if (result.length !== batch.length) throw new Error('Embedding服务返回的向量数量与输入不一致。')
        result.forEach((vector: number[]) => vectors.push(RagIndexBuilder.validVector(vector)))
      }
    } else {
      for (const draft of drafts) {
        vectors.push(RagIndexBuilder.validVector(await embedder.embed(draft.embeddingText)))
      }
    }
    const chunks = drafts.map((draft: ChunkDraft, index: number): KnowledgeChunk => {
      draft.chunk.vector = vectors[index]
      draft.chunk.vectorModel = embedder.modelId
      return draft.chunk
    })
    const signature = chunks.map((chunk: KnowledgeChunk): string =>
      `${chunk.id}:${chunk.vectorModel}:${chunk.modality}:${chunk.content.length}`).join('|')
    return { revision: `rag-${RagIndexBuilder.fingerprint(signature)}`, chunks: chunks }
  }

  private static validVector(vector: number[]): number[] {
    if (!Array.isArray(vector) || vector.length === 0 || vector.length > 4096 ||
      !vector.every((value: number) => Number.isFinite(value))) {
      throw new Error('Embedding服务返回了无效向量。')
    }
    let norm = 0
    vector.forEach((value: number) => norm += value * value)
    if (norm <= 0) return new Array<number>(vector.length).fill(0)
    const scale = 1 / Math.sqrt(norm)
    return vector.map((value: number) => value * scale)
  }

  private static modalityLabel(modality: string): string {
    if (modality === 'image') return '图片描述'
    if (modality === 'table') return '表格'
    if (modality === 'audio') return '音频转写'
    if (modality === 'video') return '视频转写'
    return '文本'
  }

  private static fingerprint(value: string): string {
    let hash = 0
    for (let i = 0; i < value.length; i++) hash = (Math.imul(hash, 31) + value.charCodeAt(i)) | 0
    return (hash >>> 0).toString(36)
  }
}
