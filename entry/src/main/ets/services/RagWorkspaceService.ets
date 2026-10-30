import { util } from '@kit.ArkTS'
import { KnowledgeChunk, KnowledgeIndex, KnowledgeRepository, RagRankingPolicy } from '../models/RagModels'
import { RagAlgorithmSettings, RagApiProfile, RagKnowledgeBase, RagStoredIndex, RagWorkspaceArchive } from '../models/RagWorkspaceModels'
import { LibraryDocument } from '../models/LibraryModels'
import { LibraryService } from './LibraryService'
import { LocalJsonStore } from './LocalJsonStore'
import { OpenAiCompatibleEmbeddingService } from './OpenAiCompatibleEmbeddingService'
import { OpenAiCompatibleRerankService } from './OpenAiCompatibleRerankService'
import { RagService } from './RagService'
import { StudentQueryEmbedder } from './StudentQueryEmbedder'

class SnapshotKnowledgeRepository implements KnowledgeRepository {
  private index: KnowledgeIndex
  constructor(index: KnowledgeIndex) { this.index = index }
  snapshot(): KnowledgeIndex { return this.index }
}

export class RagWorkspaceService {
  private store: LocalJsonStore<RagWorkspaceArchive>

  constructor(filesDir: string) {
    this.store = new LocalJsonStore<RagWorkspaceArchive>(`${filesDir}/rag_workspace.json`,
      (): RagWorkspaceArchive => RagWorkspaceService.empty(), RagWorkspaceService.valid)
  }

  static emptyAlgorithm(): RagAlgorithmSettings {
    return { lexicalWeight: 0.55, semanticWeight: 0.45, bm25K1: 1.2, bm25B: 0.75,
      localRerank: false, rerankWeight: 0.25, topK: 4, minScore: 0.2, maxPerSource: 2,
      contextChars: 2400, chunkChars: 800, chunkOverlap: 120 }
  }

  static empty(): RagWorkspaceArchive {
    const now = Date.now()
    return {
      version: 1,
      activeBaseId: 'kb-local',
      knowledgeBases: [{
        id: 'kb-local', name: '本地资料库', description: '本机文件、对话上下文与内置演示资料',
        embeddingMode: 'local', embeddingProfileId: '', rerankMode: 'local', rerankProfileId: '',
        includeBuiltIn: true, includeAllLocal: true, documentIds: [], createdAt: now, updatedAt: now,
        lastIndexedAt: 0, chunkCount: 0
      }],
      apiProfiles: [],
      indexes: [],
      algorithm: RagWorkspaceService.emptyAlgorithm()
    }
  }

  private static validProfile(value: RagApiProfile): boolean {
    return !!value && typeof value.id === 'string' && value.id.length <= 80 &&
      (value.kind === 'embedding' || value.kind === 'rerank') &&
      typeof value.name === 'string' && value.name.length <= 60 &&
      typeof value.baseUrl === 'string' && value.baseUrl.length <= 2048 &&
      typeof value.model === 'string' && value.model.length <= 160 &&
      typeof value.apiKey === 'string' && value.apiKey.length <= 8192 &&
      Number.isFinite(value.dimensions) && value.dimensions >= 0 && value.dimensions <= 4096 &&
      Number.isFinite(value.createdAt)
  }

  private static validBase(value: RagKnowledgeBase): boolean {
    return !!value && typeof value.id === 'string' && value.id.length <= 80 &&
      typeof value.name === 'string' && value.name.length > 0 && value.name.length <= 80 &&
      typeof value.description === 'string' && value.description.length <= 300 &&
      (value.embeddingMode === 'local' || value.embeddingMode === 'online') &&
      typeof value.embeddingProfileId === 'string' &&
      (value.rerankMode === 'local' || value.rerankMode === 'online' || value.rerankMode === 'none') &&
      typeof value.rerankProfileId === 'string' &&
      typeof value.includeBuiltIn === 'boolean' && typeof value.includeAllLocal === 'boolean' &&
      Array.isArray(value.documentIds) && value.documentIds.length <= 100 &&
      value.documentIds.every((id: string) => typeof id === 'string' && id.length <= 120) &&
      Number.isFinite(value.createdAt) && Number.isFinite(value.updatedAt) &&
      Number.isFinite(value.lastIndexedAt) && Number.isFinite(value.chunkCount)
  }

  private static validIndex(value: RagStoredIndex): boolean {
    if (!value || typeof value.baseId !== 'string' || !Number.isFinite(value.builtAt) ||
      typeof value.modelId !== 'string' || !value.index || !Array.isArray(value.index.chunks) ||
      value.index.chunks.length > 1000 || typeof value.index.revision !== 'string') return false
    return value.index.chunks.every((chunk: KnowledgeChunk) => !!chunk && typeof chunk.id === 'string' &&
      typeof chunk.sourceId === 'string' && typeof chunk.content === 'string' &&
      Array.isArray(chunk.vector) && chunk.vector.length <= 4096 &&
      chunk.vector.every((vector: number) => Number.isFinite(vector)) && typeof chunk.vectorModel === 'string')
  }

  private static valid(value: RagWorkspaceArchive): boolean {
    return !!value && value.version === 1 && typeof value.activeBaseId === 'string' &&
      Array.isArray(value.knowledgeBases) && value.knowledgeBases.length >= 1 && value.knowledgeBases.length <= 20 &&
      value.knowledgeBases.every(RagWorkspaceService.validBase) &&
      new Set(value.knowledgeBases.map((base: RagKnowledgeBase) => base.id)).size === value.knowledgeBases.length &&
      value.knowledgeBases.some((base: RagKnowledgeBase) => base.id === value.activeBaseId) &&
      Array.isArray(value.apiProfiles) && value.apiProfiles.length <= 30 &&
      value.apiProfiles.every(RagWorkspaceService.validProfile) &&
      new Set(value.apiProfiles.map((profile: RagApiProfile) => profile.id)).size === value.apiProfiles.length &&
      Array.isArray(value.indexes) && value.indexes.length <= 20 &&
      value.indexes.every(RagWorkspaceService.validIndex) &&
      new Set(value.indexes.map((index: RagStoredIndex) => index.baseId)).size === value.indexes.length &&
      !!value.algorithm && Number.isFinite(value.algorithm.lexicalWeight) &&
      Number.isFinite(value.algorithm.semanticWeight) && Number.isFinite(value.algorithm.bm25K1) &&
      Number.isFinite(value.algorithm.bm25B) && Number.isFinite(value.algorithm.rerankWeight) &&
      Number.isFinite(value.algorithm.topK) && Number.isFinite(value.algorithm.minScore) &&
      Number.isFinite(value.algorithm.maxPerSource) && Number.isFinite(value.algorithm.contextChars) &&
      Number.isFinite(value.algorithm.chunkChars) && Number.isFinite(value.algorithm.chunkOverlap)
  }

  read(): RagWorkspaceArchive { return this.store.read() }
  algorithm(): RagAlgorithmSettings { return this.store.read().algorithm }
  activeBase(): RagKnowledgeBase {
    const archive = this.store.read()
    return archive.knowledgeBases.find((base: RagKnowledgeBase) => base.id === archive.activeBaseId) as RagKnowledgeBase
  }
  profile(id: string): RagApiProfile | undefined {
    return this.store.read().apiProfiles.find((profile: RagApiProfile) => profile.id === id)
  }

  activateBase(id: string): RagWorkspaceArchive {
    const changed = this.store.change((state: RagWorkspaceArchive): RagWorkspaceArchive => {
      if (!state.knowledgeBases.some((base: RagKnowledgeBase) => base.id === id)) throw new Error('知识库不存在。')
      state.activeBaseId = id
      return state
    })
    return changed
  }

  saveBase(id: string, name: string, description: string, embeddingMode: string, embeddingProfileId: string,
    rerankMode: string, rerankProfileId: string, includeBuiltIn: boolean, includeAllLocal: boolean,
    documentIds: string[]): RagKnowledgeBase {
    const title = name.trim()
    if (!title || title.length > 80) throw new Error('知识库名称需为1至80字。')
    const ids = Array.from(new Set<string>(documentIds.filter((value: string) => value.length > 0))).slice(0, 100)
    const changed = this.store.change((state: RagWorkspaceArchive): RagWorkspaceArchive => {
      const now = Date.now()
      let base = state.knowledgeBases.find((item: RagKnowledgeBase) => item.id === id)
      if (base === undefined) {
        if (state.knowledgeBases.length >= 20) throw new Error('最多保存20个知识库。')
        base = { id: `kb:${util.generateRandomUUID()}`, name: title, description: description.trim().slice(0, 300),
          embeddingMode: embeddingMode === 'online' ? 'online' : 'local', embeddingProfileId: embeddingProfileId,
          rerankMode: rerankMode === 'online' ? 'online' : rerankMode === 'none' ? 'none' : 'local',
          rerankProfileId: rerankProfileId, includeBuiltIn: includeBuiltIn, includeAllLocal: includeAllLocal,
          documentIds: ids, createdAt: now, updatedAt: now, lastIndexedAt: 0, chunkCount: 0 }
        state.knowledgeBases.push(base)
      } else {
        base.name = title
        base.description = description.trim().slice(0, 300)
        base.embeddingMode = embeddingMode === 'online' ? 'online' : 'local'
        base.embeddingProfileId = embeddingProfileId
        base.rerankMode = rerankMode === 'online' ? 'online' : rerankMode === 'none' ? 'none' : 'local'
        base.rerankProfileId = rerankProfileId
        base.includeBuiltIn = includeBuiltIn
        base.includeAllLocal = includeAllLocal
        base.documentIds = ids
        base.updatedAt = now
        base.lastIndexedAt = 0
        base.chunkCount = 0
        state.indexes = state.indexes.filter((item: RagStoredIndex) => item.baseId !== base?.id)
      }
      state.activeBaseId = base.id
      return state
    })
    const saved = changed.knowledgeBases.find((item: RagKnowledgeBase) => item.id === changed.activeBaseId)
    if (saved === undefined) throw new Error('知识库保存失败。')
    return saved
  }

  removeBase(id: string): RagWorkspaceArchive {
    if (id === 'kb-local') throw new Error('默认本地知识库不能删除。')
    const changed = this.store.change((state: RagWorkspaceArchive): RagWorkspaceArchive => {
      if (!state.knowledgeBases.some((base: RagKnowledgeBase) => base.id === id)) throw new Error('知识库不存在。')
      state.knowledgeBases = state.knowledgeBases.filter((base: RagKnowledgeBase) => base.id !== id)
      state.indexes = state.indexes.filter((index: RagStoredIndex) => index.baseId !== id)
      if (state.activeBaseId === id) state.activeBaseId = 'kb-local'
      return state
    })
    return changed
  }

  saveProfile(id: string, kind: string, name: string, baseUrl: string, model: string,
    apiKey: string, dimensions: number): RagApiProfile {
    const profileId = id || `rag-api:${util.generateRandomUUID()}`
    const changed = this.store.change((state: RagWorkspaceArchive): RagWorkspaceArchive => {
      const now = Date.now()
      let profile = state.apiProfiles.find((item: RagApiProfile) => item.id === id)
      const next: RagApiProfile = {
        id: profileId,
        kind: kind === 'rerank' ? 'rerank' : 'embedding',
        name: (name.trim() || model.trim()).slice(0, 60),
        baseUrl: baseUrl.trim(),
        model: model.trim(),
        apiKey: apiKey.trim(),
        dimensions: Math.max(0, Math.min(4096, Math.round(dimensions))),
        createdAt: profile?.createdAt || now
      }
      if (!next.baseUrl || !next.model) throw new Error('请填写API服务地址和模型名称。')
      if (state.apiProfiles.length >= 30 && profile === undefined) throw new Error('最多保存30组RAG API配置。')
      if (profile === undefined) state.apiProfiles.push(next)
      else state.apiProfiles[state.apiProfiles.indexOf(profile)] = next
      return state
    })
    const saved = changed.apiProfiles.find((item: RagApiProfile) => item.id === profileId)
    if (saved === undefined) throw new Error('API配置保存失败。')
    return saved
  }

  removeProfile(id: string): RagWorkspaceArchive {
    return this.store.change((state: RagWorkspaceArchive): RagWorkspaceArchive => {
      state.apiProfiles = state.apiProfiles.filter((profile: RagApiProfile) => profile.id !== id)
      state.knowledgeBases.forEach((base: RagKnowledgeBase) => {
        if (base.embeddingProfileId === id) base.embeddingProfileId = ''
        if (base.rerankProfileId === id) base.rerankProfileId = ''
      })
      return state
    })
  }

  saveAlgorithm(value: RagAlgorithmSettings): RagWorkspaceArchive {
    return this.store.change((state: RagWorkspaceArchive): RagWorkspaceArchive => {
      state.algorithm = {
        lexicalWeight: Math.max(0, Math.min(1, value.lexicalWeight)),
        semanticWeight: Math.max(0, Math.min(1, value.semanticWeight)),
        bm25K1: Math.max(0.1, Math.min(5, value.bm25K1)),
        bm25B: Math.max(0, Math.min(1, value.bm25B)),
        localRerank: value.localRerank,
        rerankWeight: Math.max(0, Math.min(1, value.rerankWeight)),
        topK: Math.max(1, Math.min(10, Math.round(value.topK))),
        minScore: Math.max(0, Math.min(1, value.minScore)),
        maxPerSource: Math.max(1, Math.min(10, Math.round(value.maxPerSource))),
        contextChars: Math.max(200, Math.min(8000, Math.round(value.contextChars))),
        chunkChars: Math.max(80, Math.min(4000, Math.round(value.chunkChars))),
        chunkOverlap: Math.max(0, Math.min(value.chunkChars - 1, Math.round(value.chunkOverlap)))
      }
      return state
    })
  }

  storeIndex(baseId: string, index: KnowledgeIndex, modelId: string): RagWorkspaceArchive {
    return this.store.change((state: RagWorkspaceArchive): RagWorkspaceArchive => {
      const base = state.knowledgeBases.find((item: RagKnowledgeBase) => item.id === baseId)
      if (base === undefined) throw new Error('知识库不存在。')
      state.indexes = state.indexes.filter((item: RagStoredIndex) => item.baseId !== baseId)
      state.indexes.push({ baseId: baseId, builtAt: Date.now(), modelId: modelId, index: index })
      base.lastIndexedAt = Date.now()
      base.chunkCount = index.chunks.length
      return state
    })
  }

  repository(library: LibraryService, baseId: string): KnowledgeRepository {
    const archive = this.store.read()
    const base = archive.knowledgeBases.find((item: RagKnowledgeBase) => item.id === baseId) || archive.knowledgeBases[0]
    const stored = archive.indexes.find((item: RagStoredIndex) => item.baseId === base.id)
    if (stored !== undefined) {
      return new SnapshotKnowledgeRepository(stored.index)
    }
    const live = library.snapshot()
    if (base.id === 'kb-local') {
      return new SnapshotKnowledgeRepository(live)
    }
    const selected = new Set<string>(base.documentIds)
    const sourceIds = new Set<string>()
    library.documents().forEach((document: LibraryDocument) => {
      const included = (base.includeAllLocal && !document.id.startsWith('rag:')) ||
        selected.has(document.id) || (base.includeBuiltIn && document.id.startsWith('rag:'))
      if (!included) return
      if (document.chunks !== undefined && document.chunks.length > 0) {
        document.chunks.forEach((chunk: KnowledgeChunk) => sourceIds.add(chunk.sourceId))
      } else {
        sourceIds.add(document.id)
      }
    })
    const index: KnowledgeIndex = {
        revision: `${live.revision}-${base.id}`,
        chunks: live.chunks.filter((chunk: KnowledgeChunk) => sourceIds.has(chunk.sourceId))
    }
    return new SnapshotKnowledgeRepository(index)
  }

  createRag(library: LibraryService, baseId: string): RagService {
    const archive = this.store.read()
    const base = archive.knowledgeBases.find((item: RagKnowledgeBase) => item.id === baseId) || archive.knowledgeBases[0]
    const embeddingProfile = archive.apiProfiles.find((profile: RagApiProfile) =>
      profile.id === base.embeddingProfileId && profile.kind === 'embedding')
    const rerankProfile = archive.apiProfiles.find((profile: RagApiProfile) =>
      profile.id === base.rerankProfileId && profile.kind === 'rerank')
    const embedder = base.embeddingMode === 'online' && embeddingProfile !== undefined
      ? new OpenAiCompatibleEmbeddingService({ baseUrl: embeddingProfile.baseUrl, model: embeddingProfile.model,
        apiKey: embeddingProfile.apiKey, dimensions: embeddingProfile.dimensions })
      : new StudentQueryEmbedder()
    const reranker = base.rerankMode === 'online' && rerankProfile !== undefined
      ? new OpenAiCompatibleRerankService({ baseUrl: rerankProfile.baseUrl, model: rerankProfile.model,
        apiKey: rerankProfile.apiKey })
      : undefined
    const algorithm = archive.algorithm
    const policy: RagRankingPolicy = { lexicalWeight: algorithm.lexicalWeight, semanticWeight: algorithm.semanticWeight,
      bm25K1: algorithm.bm25K1, bm25B: algorithm.bm25B,
      localRerank: base.rerankMode === 'local' && algorithm.localRerank,
      rerankWeight: algorithm.rerankWeight }
    return new RagService(this.repository(library, base.id), embedder, policy, reranker)
  }
}
