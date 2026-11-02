import { common } from '@kit.AbilityKit'
import { fileIo as fs, picker } from '@kit.CoreFileKit'
import { LibraryDocument } from '../models/LibraryModels'
import { RagApiProfile, RagKnowledgeBase } from '../models/RagWorkspaceModels'
import { LibraryService } from './LibraryService'
import { OpenAiCompatibleEmbeddingService } from './OpenAiCompatibleEmbeddingService'
import { RagIndexBuilder, RagSourceDocument } from './RagIndexBuilder'
import { RagWorkspaceService } from './RagWorkspaceService'

export interface RagRebuildResult {
  chunkCount: number
  modelId: string
}

export class RagMaintenanceService {
  static async rebuild(workspace: RagWorkspaceService, library: LibraryService,
    baseId: string): Promise<RagRebuildResult> {
    const archive = workspace.read()
    const base = archive.knowledgeBases.find((item: RagKnowledgeBase) => item.id === baseId)
    if (base === undefined) throw new Error('知识库不存在。')
    if (base.embeddingMode !== 'online') throw new Error('当前知识库使用本地即时索引，无需重建。')
    const profile = archive.apiProfiles.find((item: RagApiProfile) => item.id === base.embeddingProfileId &&
      item.kind === 'embedding' && item.enabled !== false)
    if (profile === undefined) throw new Error('当前知识库没有可用的在线 Embedding 配置。')
    const documents = library.documents().filter((document: LibraryDocument) => {
      if (document.text.trim().length === 0) return false
      if (document.id.startsWith('rag:')) return base.includeBuiltIn
      if (base.includeAllLocal) return true
      return base.documentIds.includes(document.id)
    })
    if (documents.length === 0) throw new Error('当前知识库没有可索引的文本或图片描述。')
    const algorithm = workspace.algorithm()
    const sources = documents.map((document: LibraryDocument): RagSourceDocument => ({
      id: document.id,
      title: document.title,
      location: document.origin,
      course: document.course,
      text: document.text,
      modality: document.kind === 'image' ? 'image' : document.kind === 'index' ? 'table' : 'text',
      mediaPath: document.path,
      mediaMimeType: document.mimeType
    }))
    const embedder = new OpenAiCompatibleEmbeddingService({
      baseUrl: profile.baseUrl,
      model: profile.model,
      apiKey: profile.apiKey,
      dimensions: profile.dimensions
    })
    const index = await RagIndexBuilder.build(sources, embedder, {
      maxChars: algorithm.chunkChars,
      overlapChars: algorithm.chunkOverlap,
      batchSize: 24
    })
    workspace.storeIndex(base.id, index, embedder.modelId)
    return { chunkCount: index.chunks.length, modelId: embedder.modelId }
  }

  static async exportBase(context: common.UIAbilityContext, workspace: RagWorkspaceService,
    library: LibraryService, baseId: string): Promise<string> {
    const archive = workspace.read()
    const base = archive.knowledgeBases.find((item: RagKnowledgeBase) => item.id === baseId)
    if (base === undefined) throw new Error('知识库不存在。')
    const index = workspace.repository(library, base.id).snapshot()
    const safeName = base.name.replace(/[\\/:*?"<>|\r\n]/g, '_').slice(0, 48) || 'knowledge-base'
    const options = new picker.DocumentSaveOptions()
    options.newFileNames = [`${safeName}-${new Date().toISOString().slice(0, 10)}.json`]
    options.fileSuffixChoices = ['知识库索引|.json']
    const uris = await new picker.DocumentViewPicker(context).save(options)
    if (uris.length === 0) throw new Error('未选择导出位置。')
    const content = JSON.stringify({
      format: 'harmony-rag-knowledge-base',
      version: 1,
      exportedAt: Date.now(),
      knowledgeBase: base,
      index: index
    }, null, 2)
    const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
    try {
      const written = fs.writeSync(file.fd, content)
      if (written <= 0) throw new Error('知识库导出写入失败。')
    } finally {
      fs.closeSync(file)
    }
    return uris[0]
  }
}
