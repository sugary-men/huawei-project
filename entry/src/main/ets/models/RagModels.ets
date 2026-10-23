export interface KnowledgeChunk {
  id: string
  sourceId: string
  title: string
  location: string
  course: string
  content: string
  vector: number[]
  vectorModel: string
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
