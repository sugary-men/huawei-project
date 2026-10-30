const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const assert = require('node:assert/strict')

const apiKey = (process.env.EMBEDDING_API_KEY || '').trim()
if (!apiKey) {
  console.log('SKIP: set EMBEDDING_API_KEY to run the live Embedding RAG test.')
  process.exit(0)
}

const ts = require(process.argv[2] || 'typescript')
const root = path.join(__dirname, '../entry/src/main/ets')
const cache = new Map()
const apiUrl = (process.env.EMBEDDING_API_URL || 'https://open.bigmodel.cn/api/paas/v4').replace(/\/+$/, '')
const model = process.env.EMBEDDING_MODEL || 'embedding-3'
const dimensions = Number(process.env.EMBEDDING_DIMENSIONS || 512)

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
      if (name === '../models/RagModels') return {}
      if (!name.startsWith('.')) throw Error(`Unexpected dependency ${name}`)
      return load(path.relative(root, path.resolve(path.dirname(absolute), name)).replaceAll('\\', '/'))
    }
  })
  return result
}

const embedder = {
  modelId: `${model}@${dimensions}`,
  async embed(text) {
    const result = await this.embedBatch([text])
    return result[0]
  },
  async embedBatch(texts) {
    const response = await fetch(`${apiUrl}/embeddings`, {
      method: 'POST',
      headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ model, input: texts, dimensions })
    })
    const body = await response.json()
    if (!response.ok) throw new Error(body.error?.message || `Embedding API failed with HTTP ${response.status}`)
    if (!Array.isArray(body.data) || body.data.length !== texts.length) throw new Error('Embedding API returned an invalid batch')
    const ordered = new Array(texts.length)
    body.data.forEach((item, position) => {
      const index = Number.isInteger(item.index) ? item.index : position
      ordered[index] = item.embedding
    })
    ordered.forEach(vector => assert.equal(vector.length, dimensions))
    return ordered
  }
};

(async () => {
  const { RagIndexBuilder } = load('services/RagIndexBuilder')
  const { RagService } = load('services/RagService')
  const sources = [
    {
      id: 'library-photo', title: '图书馆自习区照片', location: '视觉描述', course: '校园生活',
      text: '照片显示图书馆三楼自习区，浅色长桌靠窗，每个座位都有电源插座。晚上灯光充足，环境安静，适合戴耳机看网课和整理笔记。',
      modality: 'image', mediaPath: '/app/library_files/library.jpg', mediaMimeType: 'image/jpeg'
    },
    {
      id: 'software-tests', title: '软件测试笔记', location: '黑盒测试', course: '软件工程',
      text: '黑盒测试不检查程序内部代码结构，而是根据输入和预期输出设计用例。常用方法包括等价类划分、边界值分析和判定表。',
      modality: 'text'
    },
    {
      id: 'weekly-table', title: '本周课程表', location: '星期三', course: '数据结构',
      text: '星期三上午九点开始数据结构课程，教室为第三教学楼 305。星期三下午没有课程安排。',
      modality: 'table'
    },
    {
      id: 'campus-audio', title: '校园服务讲座转写', location: '00:12-00:36', course: '校园生活',
      text: '讲座介绍图书馆开放时间、借阅规则和考试周延长开放安排。读者可以使用校园卡进入，并预约讨论室。',
      modality: 'audio'
    }
  ]
  const index = await RagIndexBuilder.build(sources, embedder, { maxChars: 800, overlapChars: 120, batchSize: 8 })
  assert.equal(index.chunks.length, sources.length)
  assert.equal(index.chunks.find(chunk => chunk.sourceId === 'library-photo').modality, 'image')
  assert.equal(index.chunks.find(chunk => chunk.sourceId === 'library-photo').mediaMimeType, 'image/jpeg')

  const rag = new RagService({ snapshot: () => index }, embedder)
  const cases = [
    { query: '晚上想找个能插电脑、不吵的地方看课程视频，应该去哪里？', expected: 'library-photo' },
    { query: '不看内部代码，只根据输入和输出来设计用例，可以用什么方法？', expected: 'software-tests' },
    { query: '我星期三上午要上什么课？', expected: 'weekly-table' }
  ]
  for (const item of cases) {
    const result = await rag.search(item.query, {
      course: '', topK: 3, minScore: 0.15, maxPerSource: 2, contextChars: 1600
    })
    assert.equal(result.status, 'hit', item.query)
    assert.equal(result.mode, 'hybrid', item.query)
    assert.ok(result.sources.some(source => source.sourceId === item.expected), `${item.query} -> ${result.sources.map(s => s.sourceId)}`)
  }
  console.log(`PASS: live ${model}@${dimensions} embeddings built a text/image-description/table/audio-transcript RAG index and retrieved all expected sources.`)
})().catch(error => { console.error(error); process.exitCode = 1 })
