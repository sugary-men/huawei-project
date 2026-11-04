import { common } from '@kit.AbilityKit'
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { LocalAlgorithmArchive, LocalAlgorithmEntry, LocalModelEntry } from '../models/LocalAlgorithmModels'
import { LocalJsonStore } from './LocalJsonStore'

export class LocalAlgorithmService {
  private store: LocalJsonStore<LocalAlgorithmArchive>
  private directory: string

  constructor(filesDir: string) {
    this.directory = filesDir
    this.store = new LocalJsonStore<LocalAlgorithmArchive>(`${filesDir}/local_algorithms.json`,
      (): LocalAlgorithmArchive => LocalAlgorithmService.empty(), LocalAlgorithmService.valid)
  }

  private static empty(): LocalAlgorithmArchive {
    const now = Date.now()
    return {
      version: 1,
      models: [],
      algorithms: [
        { id: 'builtin-hybrid', name: '混合检索', description: 'BM25 关键词与本地向量语义分数归一化融合。',
          builtIn: true, enabled: true, createdAt: now },
        { id: 'builtin-bm25', name: 'BM25 关键词', description: '按词频、逆文档频率和长度归一化进行关键词召回。',
          builtIn: true, enabled: true, createdAt: now },
        { id: 'builtin-local-vector', name: '本地哈希向量', description: '离线生成稳定哈希向量，不向网络发送原文。',
          builtIn: true, enabled: true, createdAt: now }
      ]
    }
  }

  private static valid(value: LocalAlgorithmArchive): boolean {
    return !!value && value.version === 1 && Array.isArray(value.models) && value.models.length <= 100 &&
      Array.isArray(value.algorithms) && value.algorithms.length <= 100 &&
      value.models.every((model: LocalModelEntry) => !!model && typeof model.id === 'string' &&
        typeof model.name === 'string' && typeof model.path === 'string' && Number.isFinite(model.size) &&
        typeof model.format === 'string' && typeof model.enabled === 'boolean' && Number.isFinite(model.addedAt)) &&
      value.algorithms.every((algorithm: LocalAlgorithmEntry) => !!algorithm &&
        typeof algorithm.id === 'string' && typeof algorithm.name === 'string' &&
        typeof algorithm.description === 'string' && typeof algorithm.builtIn === 'boolean' &&
        typeof algorithm.enabled === 'boolean' && Number.isFinite(algorithm.createdAt))
  }

  read(): LocalAlgorithmArchive { return this.store.read() }

  async pickAndAddModel(context: common.UIAbilityContext): Promise<LocalModelEntry | undefined> {
    const uris = await new picker.DocumentViewPicker(context).select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['本地模型|.onnx,.bin,.gguf,.json']
    })
    if (uris.length === 0) return undefined
    return this.addModel(context, uris[0])
  }

  private async addModel(context: common.UIAbilityContext, uri: string): Promise<LocalModelEntry> {
    let source: fs.File | undefined = undefined
    try {
      source = await fs.open(uri, fs.OpenMode.READ_ONLY)
      const size = (await fs.stat(source.fd)).size
      if (size <= 0 || size > 512 * 1024 * 1024) {
        throw new Error('本地模型需为非空文件，且不超过 512 MB。')
      }
      const originalName = new fileUri.FileUri(uri).name || '本地模型'
      const extension = originalName.split('.').pop()?.toLowerCase() || 'bin'
      if (!['onnx', 'bin', 'gguf', 'json'].includes(extension)) {
        throw new Error('目前支持 ONNX、BIN、GGUF 和 JSON 模型文件。')
      }
      const folder = `${this.directory}/local_models`
      if (!await fs.access(folder)) await fs.mkdir(folder)
      const id = `local-model:${util.generateRandomUUID()}`
      const target = `${folder}/${id.replace(/[^a-zA-Z0-9:-]/g, '')}.${extension}`
      await fs.copyFile(source.fd, target)
      const model: LocalModelEntry = {
        id: id,
        name: originalName.slice(0, 120),
        path: target,
        size: size,
        format: extension.toUpperCase(),
        enabled: true,
        addedAt: Date.now()
      }
      this.store.change((state: LocalAlgorithmArchive): LocalAlgorithmArchive => {
        if (state.models.length >= 100) throw new Error('最多保存 100 个本地模型。')
        state.models.push(model)
        return state
      })
      return model
    } catch (error) {
      throw new Error(`本地模型导入失败：${(error as Error).message || '无法读取文件。'}`)
    } finally {
      if (source !== undefined) {
        try { await fs.close(source) } catch (_error) {}
      }
    }
  }

  addAlgorithm(name: string, description: string): LocalAlgorithmEntry {
    const title = name.trim()
    if (!title || title.length > 60) throw new Error('算法名称需为 1 至 60 字。')
    const algorithm: LocalAlgorithmEntry = {
      id: `local-algorithm:${util.generateRandomUUID()}`,
      name: title,
      description: description.trim().slice(0, 300),
      builtIn: false,
      enabled: true,
      createdAt: Date.now()
    }
    this.store.change((state: LocalAlgorithmArchive): LocalAlgorithmArchive => {
      if (state.algorithms.length >= 100) throw new Error('最多保存 100 个本地算法。')
      state.algorithms.push(algorithm)
      return state
    })
    return algorithm
  }
}
