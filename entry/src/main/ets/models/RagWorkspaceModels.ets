import { KnowledgeIndex } from './RagModels'

export interface RagApiProfile {
  id: string
  kind: string
  name: string
  baseUrl: string
  model: string
  apiKey: string
  dimensions: number
  createdAt: number
}

export interface RagKnowledgeBase {
  id: string
  name: string
  description: string
  embeddingMode: string
  embeddingProfileId: string
  rerankMode: string
  rerankProfileId: string
  includeBuiltIn: boolean
  includeAllLocal: boolean
  documentIds: string[]
  createdAt: number
  updatedAt: number
  lastIndexedAt: number
  chunkCount: number
}

export interface RagAlgorithmSettings {
  lexicalWeight: number
  semanticWeight: number
  bm25K1: number
  bm25B: number
  localRerank: boolean
  rerankWeight: number
  topK: number
  minScore: number
  maxPerSource: number
  contextChars: number
  chunkChars: number
  chunkOverlap: number
}

export interface RagStoredIndex {
  baseId: string
  builtAt: number
  modelId: string
  index: KnowledgeIndex
}

export interface RagWorkspaceArchive {
  version: number
  activeBaseId: string
  knowledgeBases: RagKnowledgeBase[]
  apiProfiles: RagApiProfile[]
  indexes: RagStoredIndex[]
  algorithm: RagAlgorithmSettings
}
