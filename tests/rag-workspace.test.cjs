const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const assert = require('node:assert/strict')

const ts = require(process.argv[2] || 'typescript')
const root = path.join(__dirname, '../entry/src/main/ets')
const cache = new Map()
const files = new Map()
const dirs = new Map()
const handles = new Map()
let sequence = 1
let ragConstruction

const fileIo = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  accessSync: value => files.has(value) || dirs.has(value),
  readTextSync: value => { if (!files.has(value)) throw Error('missing'); return files.get(value) },
  mkdirSync: value => { if (dirs.has(value)) throw Error('exists'); dirs.set(value, Date.now() / 1000) },
  rmdirSync: value => { if (!dirs.has(value)) throw Error('missing'); dirs.delete(value) },
  statSync: value => ({ mtime: dirs.get(value), size: (files.get(value) || '').length }),
  openSync: value => { const handle = { fd: sequence++ }; handles.set(handle.fd, value); return handle },
  writeSync: (fd, text) => { files.set(handles.get(fd), text); return text.length },
  fsyncSync: () => {},
  closeSync: () => {},
  copyFileSync: (source, target) => files.set(target, files.get(source)),
  renameSync: (source, target) => { files.set(target, files.get(source)); files.delete(source) },
  unlinkSync: value => files.delete(value)
}

class FakeEmbedding {
  constructor(settings) { this.settings = settings; this.modelId = `${settings.model}@${settings.dimensions}` }
}
class FakeRerank {
  constructor(settings) { this.settings = settings; this.modelId = settings.model }
}
class FakeRagService {
  constructor(repository, embedder, policy, reranker) {
    this.repository = repository
    this.embedder = embedder
    this.policy = policy
    this.reranker = reranker
  }
}
class FakeStudent {
  constructor() { this.modelId = 'local-hash-64'; this.embedder = true }
}

function load(file) {
  if (file === 'services/LibraryService') return { LibraryService: class {} }
  if (file === 'services/OpenAiCompatibleEmbeddingService') return { OpenAiCompatibleEmbeddingService: FakeEmbedding }
  if (file === 'services/OpenAiCompatibleRerankService') return { OpenAiCompatibleRerankService: FakeRerank }
  if (file === 'services/RagService') return { RagService: FakeRagService }
  if (file === 'services/StudentQueryEmbedder') return { StudentQueryEmbedder: FakeStudent }
  const absolute = path.resolve(root, file + '.ets')
  if (cache.has(absolute)) return cache.get(absolute)
  const result = {}
  cache.set(absolute, result)
  const compiled = ts.transpileModule(fs.readFileSync(absolute, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText
  vm.runInNewContext(compiled, {
    exports: result,
    Date,
    require: name => {
      if (name === '@kit.ArkTS') return { util: { generateRandomUUID: () => `uuid-${sequence++}` } }
      if (name === '@kit.CoreFileKit') return { fileIo }
      if (!name.startsWith('.')) throw Error(`Unexpected dependency ${name}`)
      return load(path.relative(root, path.resolve(path.dirname(absolute), name)).replaceAll('\\', '/'))
    }
  })
  return result
}

const { RagWorkspaceService } = load('services/RagWorkspaceService')
const workspace = new RagWorkspaceService('/app')
let archive = workspace.read()
assert.equal(archive.knowledgeBases.length, 1)
assert.equal(archive.activeBaseId, 'kb-local')
assert.equal(archive.algorithm.chunkChars, 800)

const embedding = workspace.saveProfile('', 'embedding', '课程向量', 'https://example.invalid/v4',
  'embedding-3', 'secret-test-key', 512)
assert.equal(embedding.kind, 'embedding')
assert.equal(embedding.dimensions, 512)
const rerank = workspace.saveProfile('', 'rerank', '课程重排', 'https://example.invalid/v4',
  'rerank-v1', 'secret-test-key', 0)
assert.equal(rerank.kind, 'rerank')

const base = workspace.saveBase('', '课程 RAG', '课程与图片描述', 'online', embedding.id,
  'online', rerank.id, false, false, ['file:a', 'file:b', 'file:a'])
assert.equal(base.embeddingMode, 'online')
assert.equal(base.rerankMode, 'online')
assert.deepEqual(Array.from(base.documentIds), ['file:a', 'file:b'])
assert.equal(workspace.activeBase().id, base.id)

const chunks = [
  { id: 'a:1', sourceId: 'file:a', title: 'A', location: '1', course: '测试', content: '图片描述',
    vector: [1, 0], vectorModel: 'embedding-3@512', modality: 'image', mediaPath: '/app/a.jpg', mediaMimeType: 'image/jpeg' }
]
archive = workspace.storeIndex(base.id, { revision: 'online-1', chunks }, 'embedding-3@512')
assert.equal(archive.indexes.length, 1)
assert.equal(archive.knowledgeBases.find(value => value.id === base.id).chunkCount, 1)
assert.equal(workspace.repository({}, base.id).snapshot().chunks[0].modality, 'image')

const liveLibrary = {
  snapshot: () => ({ revision: 'live', chunks: [
    { id: 'a:1', sourceId: 'file:a', title: 'A', content: 'A', vector: [1, 0], vectorModel: 'local-hash-64' },
    { id: 'c:1', sourceId: 'file:c', title: 'C', content: 'C', vector: [0, 1], vectorModel: 'local-hash-64' }
  ] }),
  documents: () => [
    { id: 'file:a', chunks: undefined },
    { id: 'file:c', chunks: undefined }
  ]
}
const selectedBase = workspace.saveBase('', '局部资料', '', 'local', '', 'local', '',
  false, false, ['file:a'])
assert.deepEqual(Array.from(workspace.repository(liveLibrary, selectedBase.id).snapshot().chunks.map(value => value.sourceId)), ['file:a'])

const algorithm = workspace.algorithm()
algorithm.lexicalWeight = 2
algorithm.semanticWeight = -1
algorithm.topK = 99
algorithm.chunkOverlap = 9999
workspace.saveAlgorithm(algorithm)
archive = workspace.read()
assert.equal(archive.algorithm.lexicalWeight, 1)
assert.equal(archive.algorithm.semanticWeight, 0)
assert.equal(archive.algorithm.topK, 10)
assert.equal(archive.algorithm.chunkOverlap, archive.algorithm.chunkChars - 1)

const rag = workspace.createRag(liveLibrary, base.id)
assert.equal(rag.embedder.modelId, 'embedding-3@512')
assert.equal(rag.reranker.modelId, 'rerank-v1')
assert.equal(rag.policy.lexicalWeight, 1)

workspace.removeProfile(embedding.id)
archive = workspace.read()
assert.equal(archive.knowledgeBases.find(value => value.id === base.id).embeddingProfileId, '')
workspace.removeBase(base.id)
workspace.removeBase(selectedBase.id)
assert.equal(workspace.read().activeBaseId, 'kb-local')
assert.throws(() => workspace.removeBase('kb-local'), /不能删除/)
console.log('PASS: persisted knowledge bases, online embedding/rerank profiles, source scoping, stored indexes, algorithm bounds and safe defaults.')
