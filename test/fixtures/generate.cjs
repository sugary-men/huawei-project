const fs = require('node:fs')
const path = require('node:path')
const zlib = require('node:zlib')

const root = __dirname
const imageDir = path.join(root, 'images')
fs.mkdirSync(imageDir, { recursive: true })

const generatedAt = '2026-11-02T00:00:00.000Z'
const palette = ['#202020', '#596158', '#735F50', '#526473', '#735454', '#59616B']
const courses = ['操作系统', '数据结构', '计算机网络', '数据库系统', '软件工程', '人工智能']
const tags = ['文件管理', '进程调度', '关系模型', '索引', '检索', '测试']

function createLibrary() {
  return Array.from({ length: 12 }, (_, index) => {
    const course = courses[index % courses.length]
    const isImage = index < 4
    return {
      id: isImage ? `image-${String(index + 1).padStart(2, '0')}` : `document-${String(index + 1).padStart(2, '0')}`,
      title: isImage ? `知识卡片 ${String(index + 1).padStart(2, '0')}` : `${course}学习资料 ${index + 1}`,
      course,
      kind: isImage ? 'image' : 'document',
      origin: '离线测试素材',
      path: isImage ? `images/knowledge-card-${String(index + 1).padStart(2, '0')}.png` : '',
      mimeType: isImage ? 'image/png' : 'text/plain',
      size: isImage ? 320 * 200 : 840,
      text: isImage
        ? `${course}知识卡片，展示概念、关系与检索示例。测试编号 ${index + 1}。`
        : `${course}资料 ${index + 1}。本节介绍${tags[index % tags.length]}、${tags[(index + 1) % tags.length]}以及相关实践。`,
      truncated: false,
      indexed: true,
      createdAt: 1762041600000 + index
    }
  })
}

function createGraph() {
  const nodes = [{
    id: 'base:fixture',
    kind: 'base',
    label: '离线测试知识库',
    sourceId: '',
    chunkId: '',
    tags: ['测试'],
    content: '120 节点关系图验收数据',
    x: 450,
    y: 280
  }]
  const edges = []
  for (let index = 0; index < 120; index++) {
    const angle = index * 2.399963229728653
    const radius = 70 + Math.sqrt((index + 1) / 120) * 250
    const id = `chunk:${String(index + 1).padStart(3, '0')}`
    const course = courses[index % courses.length]
    nodes.push({
      id,
      kind: 'chunk',
      label: `${course}节点 ${index + 1}`,
      sourceId: `document-${String((index % 12) + 1).padStart(2, '0')}`,
      chunkId: `fixture-chunk-${index + 1}`,
      tags: [course, tags[index % tags.length]],
      content: `${course}知识片段 ${index + 1}，用于验证缩放、平移、拖拽、边高亮与详情联动。`,
      x: Math.round((450 + Math.cos(angle) * radius) * 100) / 100,
      y: Math.round((280 + Math.sin(angle) * radius) * 100) / 100
    })
    edges.push({
      id: `edge-root-${index + 1}`,
      source: 'base:fixture',
      target: id,
      kind: 'branch',
      weight: 0.45
    })
    if (index > 0 && index % 3 === 0) {
      edges.push({
        id: `edge-semantic-${index + 1}`,
        source: `chunk:${String(index).padStart(3, '0')}`,
        target: id,
        kind: 'semantic',
        weight: 0.68
      })
    }
  }
  return {
    schemaVersion: 1,
    generatedAt,
    viewport: { width: 900, height: 560 },
    base: { id: 'fixture', name: '离线测试知识库' },
    nodes,
    edges
  }
}

function crc32(buffer) {
  let crc = 0xFFFFFFFF
  for (const byte of buffer) {
    crc ^= byte
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xEDB88320 : 0)
    }
  }
  return (crc ^ 0xFFFFFFFF) >>> 0
}

function pngChunk(type, data) {
  const typeBuffer = Buffer.from(type, 'ascii')
  const length = Buffer.alloc(4)
  length.writeUInt32BE(data.length)
  const checksum = Buffer.alloc(4)
  checksum.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])))
  return Buffer.concat([length, typeBuffer, data, checksum])
}

function makePng(file, index) {
  const width = 320
  const height = 200
  const pixels = Buffer.alloc((width * 4 + 1) * height)
  const color = palette[index % palette.length]
  const rgb = [
    parseInt(color.slice(1, 3), 16),
    parseInt(color.slice(3, 5), 16),
    parseInt(color.slice(5, 7), 16)
  ]
  for (let y = 0; y < height; y++) {
    const row = y * (width * 4 + 1)
    pixels[row] = 0
    for (let x = 0; x < width; x++) {
      const offset = row + 1 + x * 4
      const grid = (x % 32 === 0 || y % 32 === 0) ? 18 : 0
      pixels[offset] = Math.min(255, rgb[0] + grid)
      pixels[offset + 1] = Math.min(255, rgb[1] + grid)
      pixels[offset + 2] = Math.min(255, rgb[2] + grid)
      pixels[offset + 3] = 255
    }
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8
  ihdr[9] = 6
  const png = Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', zlib.deflateSync(pixels)),
    pngChunk('IEND', Buffer.alloc(0))
  ])
  fs.writeFileSync(file, png)
}

const library = createLibrary()
const graph = createGraph()
fs.writeFileSync(path.join(root, 'library.json'), `${JSON.stringify(library, null, 2)}\n`)
fs.writeFileSync(path.join(root, 'knowledge-graph.json'), `${JSON.stringify(graph, null, 2)}\n`)
fs.writeFileSync(path.join(root, 'rag-workspace.seed.json'), `${JSON.stringify({
  schemaVersion: 1,
  activeBaseId: 'kb-fixture',
  knowledgeBases: [{
    id: 'kb-fixture',
    name: '离线测试知识库',
    description: '由 generate.cjs 生成，不依赖网络',
    embeddingMode: 'local',
    embeddingProfileId: '',
    rerankMode: 'local',
    rerankProfileId: '',
    includeBuiltIn: false,
    includeAllLocal: true,
    documentIds: library.map(item => item.id),
    createdAt: 1762041600000,
    updatedAt: 1762041600000,
    lastIndexedAt: 0,
    chunkCount: 120
  }],
  apiProfiles: [],
  indexes: [],
  algorithm: {
    lexicalWeight: 0.55,
    semanticWeight: 0.45,
    bm25K1: 1.2,
    bm25B: 0.75,
    localRerank: true,
    rerankWeight: 0.25,
    topK: 4,
    minScore: 0.2,
    maxPerSource: 2,
    contextChars: 2400,
    chunkChars: 800,
    chunkOverlap: 120
  }
}, null, 2)}\n`)
fs.writeFileSync(path.join(root, 'manifest.json'), `${JSON.stringify({
  schemaVersion: 1,
  generatedAt,
  generator: 'test/fixtures/generate.cjs',
  counts: {
    documents: library.length,
    images: 4,
    knowledgeNodes: graph.nodes.filter(node => node.kind === 'chunk').length,
    edges: graph.edges.length
  },
  files: [
    'library.json',
    'knowledge-graph.json',
    'rag-workspace.seed.json',
    'images/knowledge-card-01.png',
    'images/knowledge-card-02.png',
    'images/knowledge-card-03.png',
    'images/knowledge-card-04.png'
  ]
}, null, 2)}\n`)
for (let index = 1; index <= 4; index++) {
  makePng(path.join(imageDir, `knowledge-card-${String(index).padStart(2, '0')}.png`), index)
}
console.log('Generated offline fixtures in test/fixtures')
