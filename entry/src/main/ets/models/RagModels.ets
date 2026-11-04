export interface KnowledgeChunk {
  id: string
  sourceId: string
  title: string
  location: string
  course: string
  content: string
  vector: number[]
  vectorModel: string
  modality?: string
  mediaPath?: string
  mediaMimeType?: string
}

export interface KnowledgeIndex {
  revision: string
  chunks: KnowledgeChunk[]
}

export interface KnowledgeRepository {
  snapshot(): KnowledgeIndex
}

export interface QueryEmbedder {
  modelId: string
  embed(query: string): Promise<number[]>
  embedBatch?(queries: string[]): Promise<number[][]>
}

export interface RetrievalOptions {
  course: string
  topK: number
  minScore: number
  maxPerSource: number
  contextChars: number
}

export interface SourceCitation {
  number: number
  chunkId: string
  sourceId: string
  title: string
  location: string
  course: string
  excerpt: string
  score: number
  modality?: string
  mediaPath?: string
  mediaMimeType?: string
}

export interface RetrievalResult {
  query: string
  revision: string
  status: string
  mode: string
  notice: string
  sources: SourceCitation[]
  context: string
}

export interface RankedChunk {
  chunk: KnowledgeChunk
  score: number
}

export interface RagRankingPolicy {
  lexicalWeight: number
  semanticWeight: number
  bm25K1: number
  bm25B: number
  localRerank: boolean
  rerankWeight: number
}

export interface RerankProvider {
  modelId: string
  rerank(query: string, candidates: RankedChunk[]): Promise<RankedChunk[]>
}
