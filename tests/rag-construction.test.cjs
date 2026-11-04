const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const assert = require('node:assert/strict')

const ts = require(process.argv[2] || 'typescript')
const root = path.join(__dirname, '../entry/src/main/ets')
const cache = new Map()
let sentUrl = ''
let sentBody = undefined

const http = {
  RequestMethod: { POST: 'POST' },
  HttpDataType: { STRING: 'string' },
  createHttp: () => ({
    on: () => {},
    destroy: () => {},
    request: async (url, options) => {
      sentUrl = url
      sentBody = JSON.parse(options.extraData)
      return {
        responseCode: 200,
        result: JSON.stringify({ data: [
          { index: 1, embedding: [0, 1, 0] },
          { index: 0, embedding: [1, 0, 0] }
        ] })
      }
    }
  })
}

function load(file) {
  const absolute = path.resolve(root, file + '.ets')
  if (cache.has(absolute)) return cache.get(absolute)
  const result = {}
  cache.set(absolute, result)
  const compiled = ts.transpileModule(fs.readFileSync(absolute, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText
  vm.runInNewContext(compiled, {
    exports: result,
    require: name => {
      if (name === '@kit.NetworkKit') return { http }
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info: () => {}, error: () => {} } }
      if (name === '../models/RagModels') return {}
      if (!name.startsWith('.')) throw Error(`Unexpected dependency ${name}`)
      return load(path.relative(root, path.resolve(path.dirname(absolute), name)).replaceAll('\\', '/'))
    }
  })
  return result
}

function classify(text) {
  if (/图片|图书馆|安静|学习|网课|舒服/.test(text)) return [1, 0, 0]
  if (/需求|测试|验收/.test(text)) return [0, 1, 0]
  return [0, 0, 1]
}

const embedder = {
  modelId: 'fake-rag@3',
  async embed(text) { return classify(text) },
  async embedBatch(texts) { return texts.map(classify) }
};

(async () => {
  const { RagIndexBuilder } = load('services/RagIndexBuilder')
  const { RagService } = load('services/RagService')
  const { OpenAiCompatibleEmbeddingService } = load('services/OpenAiCompatibleEmbeddingService')

  const repeated = '图书馆三楼靠窗座位安静，桌边有电源，晚上可以长时间看网课。'.repeat(35)
  const sources = [
    { id: 'library-photo', title: '自习区照片', location: '图片描述', course: '校园生活',
      text: repeated, modality: 'image', mediaPath: '/app/library_files/library.jpg', mediaMimeType: 'image/jpeg' },
    { id: 'software-notes', title: '软件工程笔记', location: '课程资料', course: '软件工程',
      text: '需求分析需要明确用户、场景和验收条件，测试用例需要覆盖正常与异常路径。', modality: 'text' },
    { id: 'course-table', title: '课程表', location: '第三周', course: '数据结构',
      text: '星期二上午算法课，星期四下午实验课。', modality: 'table' }
  ]
  const index = await RagIndexBuilder.build(sources, embedder, { maxChars: 220, overlapChars: 40, batchSize: 2 })
  assert.ok(index.chunks.length > 3)
  const image = index.chunks.find(chunk => chunk.sourceId === 'library-photo')
  assert.equal(image.modality, 'image')
  assert.equal(image.mediaPath, '/app/library_files/library.jpg')
  assert.equal(image.mediaMimeType, 'image/jpeg')
  assert.equal(image.vectorModel, 'fake-rag@3')
  assert.equal(index.chunks.find(chunk => chunk.sourceId === 'course-table').modality, 'table')

  const sequence = '0123456789'.repeat(20)
  const parts = RagIndexBuilder.split(sequence, { maxChars: 80, overlapChars: 20, batchSize: 4 })
  assert.equal(parts[0].length, 80)
  assert.equal(parts[1].slice(0, 20), parts[0].slice(-20))
  await assert.rejects(() => RagIndexBuilder.build([sources[0], sources[0]], embedder), /唯一ID/)

  const repository = { snapshot: () => index }
  const rag = new RagService(repository, embedder)
  const semantic = await rag.search('一个人去哪里看网课比较舒服', {
    course: '', topK: 3, minScore: 0.15, maxPerSource: 1, contextChars: 1200 })
  assert.equal(semantic.status, 'hit')
  assert.equal(semantic.mode, 'hybrid')
  assert.equal(semantic.sources[0].sourceId, 'library-photo')
  assert.equal(semantic.sources[0].modality, 'image')
  assert.equal(semantic.sources[0].mediaPath, '/app/library_files/library.jpg')

  const mismatched = JSON.parse(JSON.stringify(index))
  mismatched.chunks.forEach(chunk => { chunk.vectorModel = 'other-model' })
  const keyword = await new RagService({ snapshot: () => mismatched }, embedder).search('图书馆 靠近电源', {
    course: '', topK: 2, minScore: 0.1, maxPerSource: 1, contextChars: 800 })
  assert.equal(keyword.mode, 'keyword')
  assert.equal(keyword.status, 'hit')

  const client = new OpenAiCompatibleEmbeddingService({
    baseUrl: 'https://example.invalid/v4/', model: 'mock-embedding', apiKey: 'private-test', dimensions: 3
  })
  const vectors = await client.embedBatch(['第一段', '第二段'])
  assert.equal(sentUrl, 'https://example.invalid/v4/embeddings')
  assert.deepEqual(sentBody, { model: 'mock-embedding', input: ['第一段', '第二段'], dimensions: 3 })
  assert.deepEqual(JSON.parse(JSON.stringify(vectors)), [[1, 0, 0], [0, 1, 0]])
  assert.equal(client.modelId, 'mock-embedding@3')
  console.log('PASS: multimodal chunk metadata, overlap, batch embeddings, hybrid retrieval, model mismatch fallback and OpenAI-compatible Embedding API payload.')
})().catch(error => { console.error(error); process.exitCode = 1 })
