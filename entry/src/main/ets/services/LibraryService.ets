import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { ChatAttachment } from '../models/AttachmentModels'
import { LibraryArchive, LibraryDocument } from '../models/LibraryModels'
import { KnowledgeChunk, KnowledgeIndex, KnowledgeRepository, SourceCitation } from '../models/RagModels'
import { LocalJsonStore } from './LocalJsonStore'
import { MemoryKnowledgeRepository } from './KnowledgeService'
import { LOCAL_VECTOR_MODEL, localHashVector } from './LocalVector'

export class LibraryService implements KnowledgeRepository {
  private store: LocalJsonStore<LibraryArchive>
  private directory: string
  private base: KnowledgeRepository
  constructor(filesDir: string, base: KnowledgeRepository = new MemoryKnowledgeRepository()) {
    this.base = base
    this.directory = filesDir
    this.store = new LocalJsonStore<LibraryArchive>(`${filesDir}/library.json`,
      (): LibraryArchive => ({ version: 1, documents: [], deletedIds: [], disabledSources: [] }), LibraryService.valid)
  }

  private static valid(value: LibraryArchive): boolean {
    return !!value && value.version === 1 && Array.isArray(value.documents) && value.documents.length <= 100 &&
      Array.isArray(value.deletedIds) && value.deletedIds.length <= 2000 && value.deletedIds.every((id: string) => typeof id === 'string') &&
      Array.isArray(value.disabledSources) && value.disabledSources.every((id: string) => typeof id === 'string') &&
      new Set(value.documents.map((d: LibraryDocument) => d.id)).size === value.documents.length &&
      value.documents.every((d: LibraryDocument) => !!d && typeof d.id === 'string' && typeof d.title === 'string' && typeof d.text === 'string' &&
        d.text.length <= 12000 && typeof d.course === 'string' && typeof d.path === 'string' && typeof d.kind === 'string' &&
        typeof d.indexed === 'boolean' && Number.isFinite(d.createdAt) && (d.chunks === undefined ||
          (Array.isArray(d.chunks) && d.chunks.length <= 500 && d.chunks.every(LibraryService.validChunk))))
  }

  private static validChunk(c: KnowledgeChunk): boolean {
    return !!c && typeof c.id === 'string' && typeof c.sourceId === 'string' && typeof c.title === 'string' &&
      typeof c.course === 'string' && typeof c.location === 'string' && typeof c.content === 'string' && c.content.length <= 12000 &&
      Array.isArray(c.vector) && c.vector.length <= 4096 && c.vector.every((n: number) => Number.isFinite(n)) &&
      typeof c.vectorModel === 'string' && (c.modality === undefined || typeof c.modality === 'string') &&
      (c.mediaPath === undefined || typeof c.mediaPath === 'string') &&
      (c.mediaMimeType === undefined || typeof c.mediaMimeType === 'string')
  }

  private static fingerprint(value: string): string {
    let hash = 0
    for (let i = 0; i < value.length; i++) hash = (Math.imul(hash, 31) + value.charCodeAt(i)) | 0
    return (hash >>> 0).toString(36)
  }

  setBase(base: KnowledgeRepository): void { this.base = base }

  saveText(title: string, text: string, id?: string): void {
    if (!title.trim() || title.length > 120 || !text.trim() || text.length > 12000) throw new Error('请填写名称和正文，正文最多12000字。')
    this.store.change((state: LibraryArchive): LibraryArchive => {
      const previous = state.documents.find((d: LibraryDocument) => d.id === id)
      if (id && (!previous || previous.origin !== '文本资料')) throw new Error('仅可在这里修改文本资料。')
      if (!previous && state.documents.length >= 100) throw new Error('资料库最多保存100份本地资料。')
      state.documents = state.documents.filter((d: LibraryDocument) => d.id !== id)
      state.documents.push({ id: id || `text:${util.generateRandomUUID()}`, title: title.trim(), text: text, course: previous?.course || '个人资料',
        kind: 'document', origin: '文本资料', path: '', mimeType: 'text/plain', size: text.length, indexed: previous?.indexed !== false,
        truncated: false, createdAt: Date.now() })
      return state
    })
  }

  private baseDocuments(): LibraryDocument[] {
    const grouped = new Map<string, KnowledgeChunk[]>()
    this.base.snapshot().chunks.forEach((chunk: KnowledgeChunk) => {
      const chunks = grouped.get(chunk.sourceId) || []; chunks.push(chunk); grouped.set(chunk.sourceId, chunks)
    })
    const disabled = this.store.read().disabledSources
    const documents: LibraryDocument[] = []
    grouped.forEach((chunks: KnowledgeChunk[], id: string) => documents.push({ id: `rag:${id}`, title: chunks[0].title,
      course: chunks[0].course, kind: 'index', origin: 'RAG资料', path: '', mimeType: '', size: 0,
      text: chunks.map((c: KnowledgeChunk) => c.content).join('\n\n').slice(0, 12000), truncated: false,
      indexed: !disabled.includes(id), createdAt: 0, chunks: chunks }))
    return documents
  }

  documents(query: string = ''): LibraryDocument[] {
    const needle = query.trim().toLocaleLowerCase()
    return this.store.read().documents.concat(this.baseDocuments()).filter((d: LibraryDocument) =>
      !needle || `${d.title} ${d.course} ${d.text}`.toLocaleLowerCase().includes(needle))
      .sort((a: LibraryDocument, b: LibraryDocument) => b.createdAt - a.createdAt || a.id.localeCompare(b.id))
  }

  private chunks(document: LibraryDocument): KnowledgeChunk[] {
    if (document.chunks !== undefined) return document.chunks
    const result: KnowledgeChunk[] = []
    const text = document.text.trim()
    const version = LibraryService.fingerprint(text)
    for (let start = 0; start < text.length; start += 680) {
      const content = text.slice(start, start + 800)
      result.push({ id: `${document.id}:${version}:${start}`, sourceId: document.id, title: document.title,
        course: document.course, location: `片段 ${result.length + 1}`, content: content,
        vector: localHashVector(`${document.title} ${content}`), vectorModel: LOCAL_VECTOR_MODEL,
        modality: document.kind, mediaPath: document.kind === 'image' ? document.path : '',
        mediaMimeType: document.kind === 'image' ? document.mimeType : '' })
      if (start + 800 >= text.length) break
    }
    return result
  }

  snapshot(): KnowledgeIndex {
    const state = this.store.read()
    const base = this.base.snapshot()
    const chunks = base.chunks.filter((c: KnowledgeChunk) => !state.disabledSources.includes(c.sourceId))
    state.documents.filter((d: LibraryDocument) => d.indexed).forEach((d: LibraryDocument) => chunks.push(...this.chunks(d)))
    return { revision: `library-${base.revision}-${LibraryService.fingerprint(state.documents.map((d: LibraryDocument) => `${d.id}:${d.indexed}:${d.createdAt}:${d.text}`).join('|') + state.disabledSources.join(','))}`, chunks: chunks }
  }

  register(attachments: ChatAttachment[], origin: string = '导入文件'): void {
    const state = this.store.read()
    const added: LibraryDocument[] = []
    const copied: string[] = []
    try {
      for (const attachment of attachments) {
        const id = `file:${attachment.id}`
        if (state.deletedIds.includes(id) || state.documents.some((d: LibraryDocument) => d.id === id)) continue
        if (state.documents.length + added.length >= 100) throw new Error('资料库最多保存100份本地资料。')
        const folder = `${this.directory}/library_files`
        if (!fs.accessSync(folder)) fs.mkdirSync(folder)
        const extension = attachment.path.split('.').pop()?.replace(/[^a-zA-Z0-9]/g, '') || 'bin'
        const path = `${folder}/${attachment.id.replace(/[^a-zA-Z0-9-]/g, '')}.${extension}`
        fs.copyFileSync(attachment.path, path); copied.push(path)
        const document: LibraryDocument = { id: id, title: attachment.name, course: '个人资料', kind: attachment.kind, origin: origin,
          path: path, mimeType: attachment.mimeType, size: attachment.size, text: attachment.text, truncated: attachment.truncated,
          indexed: attachment.kind === 'document' || attachment.text.trim().length > 0, createdAt: Date.now() }
        if (attachment.name.toLowerCase().endsWith('.json') && attachment.size > 2000000) throw new Error('JSON资料最多2MB，请拆分索引后导入。')
        if (attachment.name.toLowerCase().endsWith('.json')) {
          let index: KnowledgeIndex | undefined = undefined
          try { index = JSON.parse(fs.readTextSync(path)) as KnowledgeIndex } catch (_error) {}
          if (index !== undefined && Array.isArray(index.chunks)) {
            if (!index.chunks.length || index.chunks.length > 500 || !index.chunks.every(LibraryService.validChunk)) throw new Error('RAG索引需包含1–500个有效资料片段。')
            const seen = new Set<string>()
            document.chunks = index.chunks.map((c: KnowledgeChunk): KnowledgeChunk => {
              if (!c.id || seen.has(c.id)) throw new Error('RAG索引片段ID为空或重复。')
              seen.add(c.id)
              return { id: `${id}:${c.id}`, sourceId: id, title: c.title, course: c.course, location: c.location,
                content: c.content, vector: c.vector.slice(), vectorModel: c.vectorModel,
                modality: c.modality || 'text', mediaPath: c.mediaPath || '', mediaMimeType: c.mediaMimeType || '' }
            })
            document.kind = 'index'; document.text = document.chunks.map((c: KnowledgeChunk) => c.content).join('\n\n').slice(0, 12000)
          }
        }
        added.push(document)
      }
      if (added.length) this.store.change((current: LibraryArchive): LibraryArchive => {
        added.forEach((d: LibraryDocument) => { if (!current.documents.some((item: LibraryDocument) => item.id === d.id) && !current.deletedIds.includes(d.id)) current.documents.push(d) })
        return current
      })
    } catch (error) {
      copied.forEach((path: string) => { try { fs.unlinkSync(path) } catch (_error) {} })
      throw error as Error
    }
  }

  registerContext(source: SourceCitation): void {
    const id = `context:${source.chunkId}`
    const state = this.store.read()
    if (state.deletedIds.some((deleted: string) => deleted === source.sourceId || source.chunkId.startsWith(`${deleted}:`))) return
    if (state.documents.some((d: LibraryDocument) => d.id === source.sourceId)) return
    if (this.base.snapshot().chunks.some((c: KnowledgeChunk) => c.id === source.chunkId || c.sourceId === source.sourceId)) return
    const snapshot = this.snapshot()
    if (snapshot.chunks.some((c: KnowledgeChunk) => c.id === source.chunkId)) return
    this.store.change((state: LibraryArchive): LibraryArchive => {
      if (state.deletedIds.includes(id) || state.documents.some((d: LibraryDocument) => d.id === id)) return state
      state.documents.push({ id: id, title: source.title, course: source.course || '对话上下文', kind: 'document', origin: '对话上下文', path: '',
        mimeType: 'text/plain', size: 0, text: source.excerpt.slice(0, 12000), truncated: false, indexed: true, createdAt: Date.now() })
      return state
    })
  }

  toggle(id: string): void {
    this.store.change((state: LibraryArchive): LibraryArchive => {
      if (id.startsWith('rag:')) {
        const key = id.slice(4)
        state.disabledSources = state.disabledSources.includes(key) ? state.disabledSources.filter((value: string) => value !== key) : state.disabledSources.concat(key)
      } else {
        const document = state.documents.find((d: LibraryDocument) => d.id === id)
        if (document === undefined || !document.text.trim()) {
          throw new Error('这份资料尚无文字或图片描述，暂不能参与检索。')
        }
        document.indexed = !document.indexed
      }
      return state
    })
  }

  saveImageDescription(id: string, description: string): void {
    const text = description.trim()
    if (!text || text.length > 12000) throw new Error('图片描述需为1至12000字。')
    this.store.change((state: LibraryArchive): LibraryArchive => {
      const document = state.documents.find((d: LibraryDocument) => d.id === id)
      if (document === undefined || document.kind !== 'image') throw new Error('这份资料不是可添加描述的图片。')
      document.text = text
      document.indexed = true
      document.truncated = false
      return state
    })
  }

  remove(id: string): void {
    if (id.startsWith('rag:')) throw new Error('外部RAG资料可停用检索，请在源数据中删除。')
    let path = ''
    this.store.change((state: LibraryArchive): LibraryArchive => {
      const document = state.documents.find((d: LibraryDocument) => d.id === id)
      if (document === undefined) throw new Error('资料不存在。')
      path = document.path; state.documents = state.documents.filter((d: LibraryDocument) => d.id !== id)
      state.deletedIds = state.deletedIds.concat(id); return state
    })
    if (path.startsWith(`${this.directory}/library_files/`)) { try { fs.unlinkSync(path) } catch (_error) {} }
  }

  citations(id: string): SourceCitation[] {
    const document = this.documents().find((d: LibraryDocument) => d.id === id)
    if (document === undefined) throw new Error('资料不存在。')
    return this.chunks(document).slice(0, 4).map((c: KnowledgeChunk, i: number): SourceCitation => ({ number: i + 1,
      chunkId: c.id, sourceId: c.sourceId, title: c.title, location: c.location, course: c.course, excerpt: c.content, score: 1 }))
  }

  attachment(id: string): ChatAttachment {
    const d = this.documents().find((item: LibraryDocument) => item.id === id)
    if (d === undefined || !d.path || !fs.accessSync(d.path)) throw new Error('这份资料没有可用的原始文件。')
    const folder = `${this.directory}/chat_attachments`
    if (!fs.accessSync(folder)) fs.mkdirSync(folder)
    const uuid = util.generateRandomUUID(), path = `${folder}/${uuid}.${d.path.split('.').pop()}`
    fs.copyFileSync(d.path, path)
    return { id: uuid, name: d.title, kind: d.kind === 'image' ? 'image' : 'document', path: path,
      mimeType: d.mimeType, size: d.size, text: d.text, truncated: d.truncated }
  }
}
