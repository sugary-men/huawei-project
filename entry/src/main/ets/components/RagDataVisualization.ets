import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { KnowledgeChunk, RetrievalResult, SourceCitation } from '../models/RagModels'
import { RagKnowledgeBase, RagWorkspaceArchive } from '../models/RagWorkspaceModels'
import { IntegrationService } from '../services/IntegrationService'

interface SourceGroup {
  sourceId: string
  title: string
  course: string
  modality: string
  chunks: KnowledgeChunk[]
}

interface BaseNetwork {
  base: RagKnowledgeBase
  sources: SourceGroup[]
  sourceIds: Set<string>
}

interface MindNode {
  id: string
  kind: string
  baseId: string
  sourceId: string
  chunkId: string
  title: string
  detail: string
  x: number
  y: number
  width: number
  height: number
}

interface MindEdge {
  from: string
  to: string
  kind: string
}

interface RelatedKnowledge {
  index: number
  score: number
}

interface DistributionItem {
  label: string
  value: number
  color: string
}

interface WordCloudItem {
  term: string
  count: number
  size: number
  color: string
}

@Component
export struct RagDataVisualization {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop baseId: string = 'kb-local'
  @Prop viewportWidth: number = 1280
  onUse: (source: SourceCitation) => void = () => {}
  @State query: string = ''
  @State busy: boolean = false
  @State archive: RagWorkspaceArchive | undefined = undefined
  @State networks: BaseNetwork[] = []
  @State nodes: MindNode[] = []
  @State selectedBase: string = ''
  @State selectedSource: string = ''
  @State selectedChunk: string = ''
  @State result: RetrievalResult | undefined = undefined
  @State graphWidth: number = 900
  @State graphHeight: number = 520
  @State graphScale: number = 1
  @State offsetX: number = 0
  @State offsetY: number = 0
  @State graphFilter: string = 'all'
  @State chartFilter: string = ''
  @State chartDimension: string = 'course'
  @State chartTooltip: string = ''
  @State selectedPie: number = -1
  @State pieWidth: number = 420
  @State pieHeight: number = 236
  @State loadError: string = ''
  @State notice: string = ''
  private edges: MindEdge[] = []
  private render: RenderingContextSettings = new RenderingContextSettings(true)
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.render)
  private pieRender: RenderingContextSettings = new RenderingContextSettings(true)
  private pieCanvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.pieRender)
  private pinchStartScale: number = 1
  private pinchStartDistance: number = 0
  private pinchActive: boolean = false
  private draggingNodeId: string = ''
  private dragStartX: number = 0
  private dragStartY: number = 0
  private touchStartX: number = 0
  private touchStartY: number = 0
  private touchStartOffsetX: number = 0
  private touchStartOffsetY: number = 0

  aboutToAppear(): void {
    this.graphWidth = Math.max(240, this.viewportWidth - 370)
    this.graphHeight = 540
    this.refresh()
  }

  private wide(): boolean { return this.viewportWidth >= 900 }

  private refresh(): void {
    try {
      const workspace = IntegrationService.ragWorkspace
      const library = IntegrationService.library
      if (workspace === undefined || library === undefined) return
      this.loadError = ''
      this.archive = workspace.read()
      const networks: BaseNetwork[] = []
      this.archive.knowledgeBases.forEach((base: RagKnowledgeBase) => {
        try {
          const chunks = workspace.repository(library, base.id).snapshot().chunks
          const sourceIds = new Set<string>()
          chunks.forEach((chunk: KnowledgeChunk) => sourceIds.add(chunk.sourceId))
          networks.push({ base: base, sources: this.groupSources(chunks), sourceIds: sourceIds })
        } catch (_error) {}
      })
      this.networks = networks
      const active = networks.find((network: BaseNetwork) => network.base.id === this.archive?.activeBaseId)
      this.selectedBase = active?.base.id || networks[0]?.base.id || ''
      this.buildMindMap()
      this.notice = networks.length === 0 ? '当前没有可展示的知识库数据。' : ''
    } catch (error) {
      this.networks = []
      this.nodes = []
      this.edges = []
      this.loadError = (error as Error).message || '知识网络加载失败。'
    }
  }

  private activeNetwork(): BaseNetwork | undefined {
    return this.networks.find((network: BaseNetwork) => network.base.id === this.selectedBase) ||
      this.networks.find((network: BaseNetwork) => network.base.id === this.baseId) ||
      this.networks[0]
  }

  private activeChunks(): KnowledgeChunk[] {
    const chunks: KnowledgeChunk[] = []
    this.activeNetwork()?.sources.forEach((source: SourceGroup) =>
      source.chunks.forEach((chunk: KnowledgeChunk) => chunks.push(chunk)))
    return chunks
  }

  private groupSources(chunks: KnowledgeChunk[]): SourceGroup[] {
    const grouped = new Map<string, KnowledgeChunk[]>()
    chunks.forEach((chunk: KnowledgeChunk) => {
      const rows = grouped.get(chunk.sourceId) || []
      rows.push(chunk)
      grouped.set(chunk.sourceId, rows)
    })
    const result: SourceGroup[] = []
    grouped.forEach((rows: KnowledgeChunk[], sourceId: string) => {
      result.push({ sourceId: sourceId, title: rows[0].title, course: rows[0].course,
        modality: rows[0].modality || 'text', chunks: rows })
    })
    return result.sort((a: SourceGroup, b: SourceGroup): number => a.title.localeCompare(b.title))
  }

  private rootNodeId(baseId: string): string { return `kb:${baseId}` }

  private graphChunks(network: BaseNetwork): KnowledgeChunk[] {
    const chunks: KnowledgeChunk[] = []
    network.sources.forEach((source: SourceGroup) => source.chunks.forEach((chunk: KnowledgeChunk) => chunks.push(chunk)))
    if (this.chartFilter.length > 0) {
      return chunks.filter((chunk: KnowledgeChunk) => this.chartLabel(chunk) === this.chartFilter)
    }
    if (this.graphFilter === 'source') {
      return chunks.filter((chunk: KnowledgeChunk) => chunk.sourceId === this.selectedSource)
    }
    if (this.graphFilter === 'hit') {
      const hitIds = new Set<string>()
      this.result?.sources.forEach((source: SourceCitation) => hitIds.add(source.chunkId))
      return chunks.filter((chunk: KnowledgeChunk) => hitIds.has(chunk.id))
    }
    return chunks
  }

  private buildMindMap(): void {
    const width = Math.max(240, this.graphWidth)
    const height = Math.max(300, this.graphHeight)
    const network = this.activeNetwork()
    if (network === undefined) {
      this.nodes = []
      this.edges = []
      return
    }
    const nodes: MindNode[] = []
    const edges: MindEdge[] = []
    const allChunks = this.graphChunks(network)
    const centerX = width / 2
    const centerY = height / 2
    const root: MindNode = {
      id: this.rootNodeId(network.base.id), kind: 'base', baseId: network.base.id, sourceId: '',
      chunkId: '', title: network.base.name,
      detail: `${allChunks.length} 个知识节点 · ${network.sources.length} 个来源`,
      x: centerX - 76, y: centerY - 24, width: 152, height: 48
    }
    nodes.push(root)
    const ringX = Math.max(72, Math.min(width * 0.36, 340))
    const ringY = Math.max(72, Math.min(height * 0.36, 235))
    allChunks.forEach((chunk: KnowledgeChunk, index: number) => {
      const angle = -Math.PI / 2 + Math.PI * 2 * index / Math.max(1, allChunks.length)
      const node: MindNode = {
        id: `knowledge:${network.base.id}:${chunk.id}`, kind: 'chunk', baseId: network.base.id,
        sourceId: chunk.sourceId, chunkId: chunk.id, title: chunk.title,
        detail: `${chunk.location} · ${this.modalityLabel(chunk.modality || 'text')}`,
        x: centerX + Math.cos(angle) * ringX - 68,
        y: centerY + Math.sin(angle) * ringY - 21,
        width: 136, height: 42
      }
      nodes.push(node)
      edges.push({ from: root.id, to: node.id, kind: 'branch' })
    })
    for (let left = 0; left < Math.min(allChunks.length, 220); left++) {
      const related: RelatedKnowledge[] = []
      for (let right = 0; right < Math.min(allChunks.length, 220); right++) {
        if (left === right) continue
        const score = this.relationScore(allChunks[left], allChunks[right])
        if (score > 0.05) related.push({ index: right, score: score } as RelatedKnowledge)
      }
      related.sort((a: RelatedKnowledge, b: RelatedKnowledge): number => b.score - a.score)
      const sameSource = allChunks.reduce((total: number, chunk: KnowledgeChunk): number =>
        total + (chunk.sourceId === allChunks[left].sourceId ? 1 : 0), 0)
      const limit = sameSource > 8 ? 2 : 3
      related.slice(0, Math.min(limit, related.length)).forEach((item: RelatedKnowledge) => {
        const from = nodes[left + 1].id
        const to = nodes[item.index + 1].id
        const exists = edges.some((edge: MindEdge) =>
          (edge.from === from && edge.to === to) || (edge.from === to && edge.to === from))
        if (!exists) edges.push({ from: from, to: to, kind: 'semantic' })
      })
    }
    this.resolveCollisions(nodes, width, height, true)
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => {
      this.nodes = nodes
      this.edges = edges
    })
  }

  private relationScore(a: KnowledgeChunk, b: KnowledgeChunk): number {
    if (a.sourceId === b.sourceId && a.location !== b.location) return 0.12
    let semantic = 0
    if (a.vectorModel === b.vectorModel && a.vector.length === b.vector.length &&
      a.vector.length > 0) {
      let dot = 0
      let aa = 0
      let bb = 0
      for (let i = 0; i < a.vector.length; i++) {
        dot += a.vector[i] * b.vector[i]
        aa += a.vector[i] * a.vector[i]
        bb += b.vector[i] * b.vector[i]
      }
      semantic = aa > 0 && bb > 0 ? Math.max(0, Math.min(1, dot / Math.sqrt(aa * bb))) : 0
    }
    const tokensA = new Set<string>(`${a.title} ${a.content}`.toLowerCase().split(/\s+/))
    const tokensB = new Set<string>(`${b.title} ${b.content}`.toLowerCase().split(/\s+/))
    let shared = 0
    tokensA.forEach((token: string) => { if (tokensB.has(token)) shared++ })
    const lexical = shared / Math.max(1, Math.min(tokensA.size, tokensB.size))
    return semantic * 0.75 + lexical * 0.25
  }

  private resolveCollisions(nodes: MindNode[], width: number, height: number, repulse: boolean = false): void {
    const iterations = nodes.length > 120 ? 8 : nodes.length > 60 ? 18 : 34
    for (let iteration = 0; iteration < iterations; iteration++) {
      for (let i = 0; i < nodes.length; i++) {
        for (let j = i + 1; j < nodes.length; j++) {
          const a = nodes[i]
          const b = nodes[j]
          if (repulse && iteration < 4) {
            const dx = (a.x + a.width / 2) - (b.x + b.width / 2)
            const dy = (a.y + a.height / 2) - (b.y + b.height / 2)
            const distance = Math.max(1, Math.sqrt(dx * dx + dy * dy))
            if (distance < 190) {
              const force = (190 - distance) * 0.012
              a.x += dx / distance * force
              a.y += dy / distance * force
              b.x -= dx / distance * force
              b.y -= dy / distance * force
            }
          }
          const overlapX = (a.width + b.width) / 2 + 10 - Math.abs((a.x + a.width / 2) - (b.x + b.width / 2))
          const overlapY = (a.height + b.height) / 2 + 8 - Math.abs((a.y + a.height / 2) - (b.y + b.height / 2))
          if (overlapX <= 0 || overlapY <= 0) continue
          if (overlapX < overlapY) {
            const direction = a.x + a.width / 2 < b.x + b.width / 2 ? -1 : 1
            const push = overlapX * (a.kind === 'base' ? 0.25 : 0.5)
            a.x += direction * push
            b.x -= direction * push
          } else {
            const direction = a.y + a.height / 2 < b.y + b.height / 2 ? -1 : 1
            const push = overlapY * (a.kind === 'base' ? 0.25 : 0.5)
            a.y += direction * push
            b.y -= direction * push
          }
        }
      }
      nodes.forEach((node: MindNode) => {
        node.x = Math.max(18, Math.min(width - node.width - 18, node.x))
        node.y = Math.max(18, Math.min(height - node.height - 18, node.y))
      })
    }
  }

  private node(id: string): MindNode | undefined {
    return this.nodes.find((item: MindNode) => item.id === id)
  }
  private selectedBaseData(): RagKnowledgeBase | undefined {
    return this.networks.find((network: BaseNetwork) => network.base.id === this.selectedBase)?.base
  }
  private selectedSourceData(): SourceGroup | undefined {
    return this.networks.find((network: BaseNetwork) => network.base.id === this.selectedBase)
      ?.sources.find((source: SourceGroup) => source.sourceId === this.selectedSource)
  }
  private currentChunk(): KnowledgeChunk | undefined {
    return this.selectedSourceData()?.chunks.find((chunk: KnowledgeChunk) => chunk.id === this.selectedChunk)
  }
  private modalityLabel(value: string): string {
    if (value === 'image') return '图片'
    if (value === 'table') return '表格'
    if (value === 'audio') return '音频'
    if (value === 'video') return '视频'
    return '文本'
  }
  private short(value: string, max: number): string {
    return value.length > max ? `${value.slice(0, max)}…` : value
  }
  private nodeSelected(node: MindNode): boolean {
    if (node.kind === 'base') return node.baseId === this.selectedBase && this.selectedSource.length === 0
    if (node.kind === 'chunk') return this.selectedChunk === this.chunkIdFromNode(node)
    return node.baseId === this.selectedBase && node.sourceId === this.selectedSource
  }
  private chunkIdFromNode(node: MindNode): string {
    return node.chunkId
  }
  private chunkForNode(node: MindNode): KnowledgeChunk | undefined {
    return this.activeChunks().find((chunk: KnowledgeChunk) => chunk.id === node.chunkId)
  }
  private nodeHit(node: MindNode): boolean {
    if (this.result === undefined) return false
    if (node.kind === 'chunk') {
      const chunkId = this.chunkIdFromNode(node)
      return this.result.sources.some((source: SourceCitation) => source.chunkId === chunkId)
    }
    if (node.kind === 'source') {
      return this.result.sources.some((source: SourceCitation) =>
        source.sourceId === node.sourceId &&
        this.networks.find((network: BaseNetwork) => network.base.id === node.baseId)?.sourceIds.has(source.sourceId) === true)
    }
    return false
  }
  private nodeRelated(node: MindNode): boolean {
    const activeId = this.selectedChunk.length > 0
      ? `knowledge:${this.selectedBase}:${this.selectedChunk}` : this.rootNodeId(this.selectedBase)
    return this.edges.some((edge: MindEdge) =>
      (edge.from === activeId && edge.to === node.id) || (edge.to === activeId && edge.from === node.id))
  }
  private edgeRelated(edge: MindEdge): boolean {
    const activeId = this.selectedChunk.length > 0
      ? `knowledge:${this.selectedBase}:${this.selectedChunk}` : this.rootNodeId(this.selectedBase)
    return edge.from === activeId || edge.to === activeId
  }
  private relatedNodes(): MindNode[] {
    if (!this.selectedChunk) return []
    const activeId = `knowledge:${this.selectedBase}:${this.selectedChunk}`
    const ids = new Set<string>()
    this.edges.forEach((edge: MindEdge) => {
      if (edge.from === activeId) ids.add(edge.to)
      if (edge.to === activeId) ids.add(edge.from)
    })
    return this.nodes.filter((node: MindNode) => node.kind === 'chunk' && ids.has(node.id))
  }
  private nodeLeft(node: MindNode): number { return node.x * this.graphScale + this.offsetX }
  private nodeTop(node: MindNode): number { return node.y * this.graphScale + this.offsetY }
  private nodeWidth(node: MindNode): number { return node.width * this.graphScale }
  private nodeHeight(node: MindNode): number { return node.height * this.graphScale }
  private selectNode(node: MindNode): void {
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => {
      this.selectedBase = node.baseId
      if (node.kind === 'chunk') {
        this.selectedSource = node.sourceId
        this.selectedChunk = this.chunkIdFromNode(node)
      } else {
        this.selectedSource = node.kind === 'base' || this.selectedSource === node.sourceId ? '' : node.sourceId
        if (node.kind === 'base') this.selectedChunk = ''
      }
    })
    this.chartTooltip = node.kind === 'base'
      ? `${node.title} · ${node.detail}` : `${node.title} · ${node.detail}`
    this.drawMindMap()
  }

  private drawMindMap(): void {
    const width = Math.max(240, this.graphWidth)
    const height = Math.max(300, this.graphHeight)
    this.canvas.clearRect(0, 0, width, height)
    this.canvas.fillStyle = '#FAFAFA'
    this.canvas.fillRect(0, 0, width, height)
    this.canvas.save()
    this.canvas.translate(this.offsetX, this.offsetY)
    this.canvas.scale(this.graphScale, this.graphScale)
    this.edges.forEach((edge: MindEdge) => {
      const from = this.node(edge.from)
      const to = this.node(edge.to)
      if (from === undefined || to === undefined) return
      const active = this.edgeRelated(edge)
      const fromX = from.x + from.width / 2
      const fromY = from.y + from.height / 2
      const toX = to.x + to.width / 2
      const toY = to.y + to.height / 2
      this.canvas.beginPath()
      this.canvas.moveTo(fromX, fromY)
      this.canvas.setLineDash(edge.kind === 'semantic' ? [3, 5] : [])
      this.canvas.globalAlpha = active ? 0.9 : edge.kind === 'semantic' ? 0.26 : 0.42
      this.canvas.strokeStyle = active ? '#343434' : edge.kind === 'semantic' ? '#B8B8B8' : '#C7C7C7'
      this.canvas.lineWidth = active ? 1.7 : edge.kind === 'semantic' ? 0.8 : 1
      const direction = toX >= fromX ? 1 : -1
      this.canvas.bezierCurveTo(fromX + 32 * direction, fromY, toX - 32 * direction, toY, toX, toY)
      this.canvas.stroke()
    })
    this.canvas.globalAlpha = 1
    this.canvas.setLineDash([])
    this.nodes.forEach((node: MindNode) => {
      if (!this.nodeSelected(node) && !this.nodeHit(node) && !this.nodeRelated(node)) return
      this.canvas.beginPath()
      this.canvas.roundRect(node.x - 4, node.y - 4, node.width + 8, node.height + 8, 10)
      this.canvas.strokeStyle = this.nodeSelected(node) ? '#202020' : this.nodeHit(node) ? '#666666' : '#A0A0A0'
      this.canvas.lineWidth = this.nodeSelected(node) ? 2.2 : this.nodeHit(node) ? 1.5 : 0.9
      this.canvas.stroke()
    })
    this.canvas.restore()
  }

  private async search(): Promise<void> {
    if (this.busy) return
    const query = this.query.trim()
    if (!query) { this.result = undefined; return }
    this.busy = true
    try {
      const workspace = IntegrationService.ragWorkspace
      const library = IntegrationService.library
      if (workspace === undefined || library === undefined) throw new Error('RAG服务尚未初始化。')
      const policy = workspace.algorithm()
      this.result = await workspace.createRag(library, this.baseId || this.selectedBase).search(query, {
        course: '', topK: policy.topK, minScore: policy.minScore,
        maxPerSource: policy.maxPerSource, contextChars: policy.contextChars
      })
      if (this.result.sources.length > 0) {
        const source = this.result.sources[0]
        const owner = this.networks.find((network: BaseNetwork) => network.sourceIds.has(source.sourceId))
        if (owner !== undefined) {
          this.selectedBase = owner.base.id
          this.selectedSource = source.sourceId
          this.selectedChunk = source.chunkId
        }
        this.graphFilter = 'all'
        this.buildMindMap()
      }
      this.notice = this.result.sources.length > 0
        ? `命中 ${this.result.sources.length} 个知识片段，已在图谱中高亮。`
        : (this.result.notice || '没有达到阈值的检索结果。')
      this.drawMindMap()
    } catch (error) {
      this.result = { query: query, revision: '', status: 'miss', mode: 'keyword',
        notice: (error as Error).message || '检索失败。', sources: [], context: '' }
      this.notice = this.result.notice
    } finally {
      this.busy = false
    }
  }

  private useChunk(chunk: KnowledgeChunk): void {
    this.onUse({ number: 1, chunkId: chunk.id, sourceId: chunk.sourceId, title: chunk.title,
      location: chunk.location, course: chunk.course, excerpt: chunk.content, score: 1,
      modality: chunk.modality || 'text', mediaPath: chunk.mediaPath || '',
      mediaMimeType: chunk.mediaMimeType || '' })
  }
  private palette(): string[] {
    return ['#202020', '#5B645C', '#7B7164', '#566575', '#7D5D5D', '#64646C', '#687C74', '#7B6D56']
  }
  private distribution(): DistributionItem[] {
    const counts = new Map<string, number>()
    this.activeChunks().forEach((chunk: KnowledgeChunk) => {
      const label = this.chartLabel(chunk)
      counts.set(label, (counts.get(label) || 0) + 1)
    })
    const colors = this.palette()
    const result: DistributionItem[] = []
    counts.forEach((value: number, label: string) => {
      result.push({ label: label, value: value, color: colors[result.length % colors.length] })
    })
    return result.sort((a: DistributionItem, b: DistributionItem): number => b.value - a.value).slice(0, 8)
  }
  private chunkScore(chunk: KnowledgeChunk): number {
    return this.result?.sources.find((source: SourceCitation) => source.chunkId === chunk.id)?.score || 0
  }
  private scoreLabel(score: number): string {
    if (score >= 0.8) return '高相似度 ≥ 80%'
    if (score >= 0.6) return '较高 60–79%'
    if (score >= 0.4) return '中等 40–59%'
    if (score > 0) return '较低 1–39%'
    return '未参与检索'
  }
  private chartLabel(chunk: KnowledgeChunk): string {
    if (this.chartDimension === 'modality') return this.modalityLabel(chunk.modality || 'text')
    if (this.chartDimension === 'source') return chunk.title.trim() || '未命名来源'
    if (this.chartDimension === 'similarity') return this.scoreLabel(this.chunkScore(chunk))
    return chunk.course.trim() || '未分类'
  }
  private maxDistribution(): number {
    return Math.max(1, ...this.distribution().map((item: DistributionItem) => item.value))
  }
  private wordCloudItems(): WordCloudItem[] {
    const terms: string[] = []
    this.activeChunks().forEach((chunk: KnowledgeChunk) => {
      terms.push(chunk.course)
      const segments: string[] = `${chunk.title} ${chunk.content}`
        .split(/[\s,，。；;:：!?！？、/\\|()（）\[\]【】<>《》"'“”]+/).slice(0, 80)
      segments.forEach((segment: string) => {
        if (segment.length <= 14) {
          terms.push(segment)
        } else {
          for (let start = 0; start < Math.min(segment.length, 80); start += 4) {
            terms.push(segment.slice(start, start + 4))
          }
        }
      })
    })
    const counts = new Map<string, number>()
    const stopWords = new Set<string>(['the', 'and', 'for', 'with', 'this', 'that', 'from', '资料',
      '片段', '课程', '知识', '内容', '一个', '以及', '可以', '进行', '通过'])
    terms.forEach((value: string) => {
      const token = value.trim().toLowerCase()
      if (token.length >= 2 && token.length <= 14 && !stopWords.has(token)) {
        counts.set(token, (counts.get(token) || 0) + 1)
      }
    })
    const colors = this.palette()
    const items: WordCloudItem[] = []
    counts.forEach((count: number, term: string) => {
      items.push({ term: term, count: count, size: 11 + Math.min(12, count * 2.2),
        color: colors[items.length % colors.length] })
    })
    return items.sort((a: WordCloudItem, b: WordCloudItem): number => b.count - a.count).slice(0, 34)
  }
  private applyChartFilter(label: string): void {
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => {
      this.chartFilter = this.chartFilter === label ? '' : label
      this.chartTooltip = this.chartFilter.length > 0
        ? `${label} · ${this.activeChunks().filter((chunk: KnowledgeChunk) => this.chartLabel(chunk) === label).length} 个知识片段`
        : '已清除图表筛选。'
    })
    this.buildMindMap()
  }
  private setChartDimension(value: string): void {
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => {
      this.chartDimension = value
      this.chartFilter = ''
      this.chartTooltip = ''
      this.selectedPie = -1
    })
    setTimeout(() => this.drawPie(), 30)
  }
  private drawPie(): void {
    const items = this.distribution()
    const width = Math.max(260, this.pieWidth)
    const height = Math.max(190, this.pieHeight)
    this.pieCanvas.clearRect(0, 0, width, height)
    this.pieCanvas.fillStyle = '#FAFAFA'
    this.pieCanvas.fillRect(0, 0, width, height)
    if (items.length === 0) return
    const total = items.reduce((sum: number, item: DistributionItem): number => sum + item.value, 0)
    const cx = width / 2
    const cy = height / 2
    const radius = Math.max(56, Math.min(width, height) * 0.34)
    let angle = -Math.PI / 2
    items.forEach((item: DistributionItem, index: number) => {
      const next = angle + Math.PI * 2 * item.value / Math.max(1, total)
      const mid = (angle + next) / 2
      const offset = this.selectedPie === index ? 7 : 0
      this.pieCanvas.beginPath()
      this.pieCanvas.moveTo(cx + Math.cos(mid) * offset, cy + Math.sin(mid) * offset)
      this.pieCanvas.arc(cx + Math.cos(mid) * offset, cy + Math.sin(mid) * offset,
        radius, angle, next)
      this.pieCanvas.closePath()
      this.pieCanvas.fillStyle = item.color
      this.pieCanvas.globalAlpha = this.selectedPie >= 0 && this.selectedPie !== index ? 0.42 : 1
      this.pieCanvas.fill()
      if (this.selectedPie === index) {
        this.pieCanvas.strokeStyle = '#FFFFFF'
        this.pieCanvas.lineWidth = 2
        this.pieCanvas.stroke()
      }
      angle = next
    })
    this.pieCanvas.globalAlpha = 1
  }
  private handlePieTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Up || event.touches.length === 0) return
    const items = this.distribution()
    if (items.length === 0) return
    const x = event.touches[0].x - this.pieWidth / 2
    const y = event.touches[0].y - this.pieHeight / 2
    const distance = Math.sqrt(x * x + y * y)
    const radius = Math.max(56, Math.min(this.pieWidth, this.pieHeight) * 0.34)
    if (distance > radius + 10) return
    let angle = Math.atan2(y, x) + Math.PI / 2
    if (angle < 0) angle += Math.PI * 2
    const total = items.reduce((sum: number, item: DistributionItem): number => sum + item.value, 0)
    let start = 0
    let chosen = -1
    for (let index = 0; index < items.length; index++) {
      const end = start + Math.PI * 2 * items[index].value / Math.max(1, total)
      if (angle >= start && angle < end) {
        chosen = index
        break
      }
      start = end
    }
    if (chosen < 0) return
    const chosenItem = items[chosen]
    this.selectedPie = chosen
    this.chartTooltip = `${chosenItem.label} · ${chosenItem.value} 个片段 · ${Math.round(chosenItem.value / total * 100)}%`
    this.chartFilter = chosenItem.label
    this.drawPie()
    this.buildMindMap()
  }
  private resetView(): void {
    this.offsetX = 0
    this.offsetY = 0
    this.graphScale = 1
    this.buildMindMap()
    this.drawMindMap()
  }
  private zoomBy(value: number): void {
    this.graphScale = Math.max(0.65, Math.min(2.2, this.graphScale + value))
    this.drawMindMap()
  }
  private startNodeDrag(node: MindNode): void {
    this.draggingNodeId = node.id
    this.dragStartX = node.x
    this.dragStartY = node.y
    this.selectNode(node)
  }
  private moveNode(node: MindNode, event: GestureEvent): void {
    node.x = this.dragStartX + event.offsetX / this.graphScale
    node.y = this.dragStartY + event.offsetY / this.graphScale
    this.resolveCollisions(this.nodes, Math.max(240, this.graphWidth), Math.max(300, this.graphHeight), true)
    this.nodes = this.nodes.slice()
    this.drawMindMap()
  }
  private handleTouch(event: TouchEvent): void {
    if (event.touches.length >= 2) {
      const dx = event.touches[0].x - event.touches[1].x
      const dy = event.touches[0].y - event.touches[1].y
      const distance = Math.sqrt(dx * dx + dy * dy)
      if (!this.pinchActive || this.pinchStartDistance <= 0) {
        this.pinchActive = true
        this.pinchStartDistance = Math.max(1, distance)
        this.pinchStartScale = this.graphScale
      } else if (event.type === TouchType.Move) {
        this.graphScale = Math.max(0.65, Math.min(2.2,
          this.pinchStartScale * distance / this.pinchStartDistance))
        this.drawMindMap()
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pinchActive = false
      this.pinchStartDistance = 0
      this.touchStartX = 0
      this.touchStartY = 0
    } else if (event.touches.length === 1) {
      const touch = event.touches[0]
      if (event.type === TouchType.Down || this.touchStartX === 0) {
        this.touchStartX = touch.x
        this.touchStartY = touch.y
        this.touchStartOffsetX = this.offsetX
        this.touchStartOffsetY = this.offsetY
      } else if (event.type === TouchType.Move && !this.pinchActive) {
        this.offsetX = this.touchStartOffsetX + touch.x - this.touchStartX
        this.offsetY = this.touchStartOffsetY + touch.y - this.touchStartY
        this.drawMindMap()
      }
    }
  }

  @Styles
  interactive() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.82) } })
    .animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }
  @Builder
  GraphFilterButton(label: string, value: string) {
    Button(label).height(27 * this.fontScale).fontSize(9 * this.fontScale)
      .backgroundColor(this.graphFilter === value ? UiTheme.primary : UiTheme.surface)
      .fontColor(this.graphFilter === value ? UiTheme.onPrimary : UiTheme.text)
      .border({ width: 1, color: this.graphFilter === value ? UiTheme.primary : UiTheme.border })
      .borderRadius(6).onClick(() => {
        this.graphFilter = value
        this.chartFilter = ''
        this.buildMindMap()
        setTimeout(() => this.drawMindMap(), 20)
      })
  }
  @Builder
  DimensionButton(label: string, value: string) {
    Button(label).height(26 * this.fontScale).fontSize(9 * this.fontScale)
      .backgroundColor(this.chartDimension === value ? UiTheme.primary : UiTheme.raised)
      .fontColor(this.chartDimension === value ? UiTheme.onPrimary : UiTheme.text)
      .borderRadius(6).onClick(() => this.setChartDimension(value))
  }
  @Builder
  MindNodeButton(node: MindNode) {
    Button({ type: ButtonType.Normal }) {
      if (node.kind === 'base') {
        Row({ space: 8 * this.fontScale }) {
          Text('◇').fontSize(13 * this.fontScale).fontColor(UiTheme.onPrimary)
          Column({ space: 2 * this.fontScale }) {
            Text(this.short(node.title, 14)).fontSize(10 * this.fontScale).fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.onPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(node.detail).fontSize(7 * this.fontScale).fontColor('#CFCFCF').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
      } else if (node.kind === 'source') {
        Column({ space: 1 * this.fontScale }) {
          Text(this.short(node.title, 15)).fontSize(8 * this.fontScale).fontColor(UiTheme.text)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(node.detail).fontSize(7 * this.fontScale).fontColor(UiTheme.muted).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      } else {
        Row({ space: 4 * this.fontScale }) {
          Text('·').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          Text(this.short(node.title, 11)).fontSize(7 * this.fontScale).fontColor(UiTheme.text)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }.width('100%')
      }
    }.width(this.nodeWidth(node)).height(this.nodeHeight(node)).padding({ left: 8, right: 8 })
      .backgroundColor(node.kind === 'base' ? (this.nodeSelected(node) ? '#3B3B3B' : UiTheme.primary) :
        this.nodeSelected(node) ? '#ECECEC' : this.nodeHit(node) ? '#F1F1F1' : UiTheme.surface)
      .border({ width: this.nodeSelected(node) || this.nodeHit(node) ? 2 : 1,
        color: this.nodeSelected(node) ? UiTheme.primary : this.nodeHit(node) ? '#787878' : UiTheme.border })
      .borderRadius(node.kind === 'base' ? 8 * this.fontScale : 13 * this.fontScale)
      .position({ x: this.nodeLeft(node), y: this.nodeTop(node) })
      .shadow({ radius: this.nodeSelected(node) ? 10 : 0, color: '#1A000000', offsetY: 3 })
      .animation({ duration: UiMotion.section, curve: Curve.EaseOut })
      .accessibilityText(node.kind === 'base' ? `知识库 ${node.title}` : `知识片段 ${node.title} ${node.detail}`)
      .interactive().onClick(() => this.selectNode(node))
      .gesture(
        PanGesture({ fingers: 1, distance: 2 })
          .onActionStart(() => this.startNodeDrag(node))
          .onActionUpdate((event: GestureEvent) => this.moveNode(node, event))
          .onActionEnd(() => { this.draggingNodeId = '' })
          .onActionCancel(() => { this.draggingNodeId = '' })
      )
  }
  @Builder
  MindMapCanvas() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.canvas).width('100%').height('100%').onReady(() => this.drawMindMap())
        .onTouch((event: TouchEvent) => this.handleTouch(event))
      ForEach(this.nodes, (node: MindNode) => {
        this.MindNodeButton(node)
      }, (node: MindNode) => node.id)
      Row({ space: 4 * this.fontScale }) {
        Button('−').width(25 * this.fontScale).height(25 * this.fontScale).fontSize(13 * this.fontScale)
          .padding(0).backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.border }).borderRadius(5).id('rag-zoom-out')
          .onClick(() => this.zoomBy(-0.15))
        Text(`${Math.round(this.graphScale * 100)}%`).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
          .width(38 * this.fontScale).textAlign(TextAlign.Center)
        Button('＋').width(25 * this.fontScale).height(25 * this.fontScale).fontSize(13 * this.fontScale)
          .padding(0).backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.border }).borderRadius(5).id('rag-zoom-in')
          .onClick(() => this.zoomBy(0.15))
        Button('重置').height(25 * this.fontScale).fontSize(9 * this.fontScale)
          .backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.border }).borderRadius(5).id('rag-graph-reset')
          .onClick(() => this.resetView())
      }.padding(8 * this.fontScale).position({ x: Math.max(10, this.graphWidth - 182), y: 10 })
    }.width('100%').height('100%').backgroundColor('#FAFAFA')
      .border({ width: 1, color: UiTheme.border }).borderRadius(9).clip(true)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width = parseFloat(String(newValue.width))
        const height = parseFloat(String(newValue.height))
        if (Number.isFinite(width) && width > 0) this.graphWidth = width
        if (Number.isFinite(height) && height > 0) this.graphHeight = height
        this.buildMindMap()
        setTimeout(() => this.drawMindMap(), 25)
      })
  }
  @Builder
  WordCloudView() {
    Column({ space: 12 * this.fontScale }) {
      Row() {
        Column({ space: 3 * this.fontScale }) {
          Text('知识词云').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('点击词语重新检索并在图谱中高亮相关片段。')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(`${this.wordCloudItems().length} 个词`).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
      }.width('100%')
      if (this.wordCloudItems().length === 0) {
        this.EmptyState('暂无可提取词语', '导入资料或添加图片描述后再查看词云。')
      } else {
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
            ForEach(this.wordCloudItems(), (item: WordCloudItem, index: number) => {
              Text(item.term).fontSize(item.size * this.fontScale)
                .fontColor(item.color).fontWeight(index < 6 ? FontWeight.Medium : FontWeight.Regular)
                .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                .margin(3).backgroundColor(index % 3 === 0 ? '#F0F0F0' : Color.Transparent)
                .borderRadius(14).accessibilityText(`关键词 ${item.term}，出现 ${item.count} 次`)
                .hoverEffect(HoverEffect.Highlight)
                .onClick(() => {
                  this.query = item.term
                  this.chartTooltip = `正在检索关键词：${item.term}`
                  this.search()
                })
            }, (item: WordCloudItem) => item.term)
          }.width('100%').padding(14 * this.fontScale)
        }.layoutWeight(1).scrollBar(BarState.Auto)
      }
    }.width('100%').height('100%').padding(14 * this.fontScale).backgroundColor(UiTheme.surface)
      .border({ width: 1, color: UiTheme.border }).borderRadius(9)
  }
  @Builder
  BarChartView() {
    Scroll() {
      Column({ space: 13 * this.fontScale }) {
        Row() {
          Column({ space: 3 * this.fontScale }) {
            Text('知识分布').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            Text('按课程或标签统计节点数量，点击柱条联动筛选。')
              .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.chartFilter) {
            Button('清除筛选').height(27 * this.fontScale).fontSize(9 * this.fontScale)
              .backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
              .onClick(() => this.applyChartFilter(this.chartFilter))
          }
        }.width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.DimensionButton('课程', 'course')
          this.DimensionButton('模态', 'modality')
          this.DimensionButton('来源', 'source')
          this.DimensionButton('相似度', 'similarity')
        }.width('100%')
        if (this.distribution().length === 0) {
          this.EmptyState('暂无分布数据', '当前知识库尚未形成可统计的知识片段。')
        } else {
          ForEach(this.distribution(), (item: DistributionItem, index: number) => {
            Column({ space: 7 * this.fontScale }) {
              Row() {
                Text(item.label).fontSize(10 * this.fontScale).fontColor(UiTheme.text).layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${item.value} 节点`).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
              }.width('100%')
              Stack({ alignContent: Alignment.Start }) {
                Row().width('100%').height(9 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(5)
                Row().width(`${Math.max(5, item.value / this.maxDistribution() * 100)}%`)
                  .height(9 * this.fontScale).backgroundColor(item.color).borderRadius(5)
                  .opacity(this.chartFilter.length === 0 || this.chartFilter === item.label ? 1 : 0.28)
                  .animation({ duration: UiMotion.section, curve: Curve.EaseOut })
              }.width('100%')
            }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.chartFilter === item.label ? '#F0F0F0' : Color.Transparent)
              .borderRadius(7).hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.applyChartFilter(item.label))
          }, (item: DistributionItem) => item.label)
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
      .padding(14 * this.fontScale).backgroundColor(UiTheme.surface)
      .border({ width: 1, color: UiTheme.border }).borderRadius(9)
  }
  @Builder
  PieChartView() {
    Scroll() {
      Column({ space: 12 * this.fontScale }) {
        Column({ space: 3 * this.fontScale }) {
          Text('知识维度占比').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('点击扇区或图例查看占比，并联动知识图谱筛选。')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
        }.width('100%').alignItems(HorizontalAlign.Start)
        Flex({ wrap: FlexWrap.Wrap }) {
          this.DimensionButton('课程', 'course')
          this.DimensionButton('模态', 'modality')
          this.DimensionButton('来源', 'source')
          this.DimensionButton('相似度', 'similarity')
        }.width('100%')
        if (this.distribution().length === 0) {
          this.EmptyState('暂无占比数据', '当前知识库尚未生成可统计节点。')
        } else {
          Canvas(this.pieCanvas).width('100%').height(236 * this.fontScale)
            .onReady(() => this.drawPie())
            .onTouch((event: TouchEvent) => this.handlePieTouch(event))
            .onAreaChange((_oldValue: Area, newValue: Area) => {
              const width = parseFloat(String(newValue.width))
              const height = parseFloat(String(newValue.height))
              if (Number.isFinite(width) && width > 0) this.pieWidth = width
              if (Number.isFinite(height) && height > 0) this.pieHeight = height
              setTimeout(() => this.drawPie(), 20)
            })
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.distribution(), (item: DistributionItem, index: number) => {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 6 * this.fontScale }) {
                  Row().width(8 * this.fontScale).height(8 * this.fontScale)
                    .backgroundColor(item.color).borderRadius(4)
                  Text(`${item.label} ${item.value}`).fontSize(9 * this.fontScale).fontColor(UiTheme.text)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.height(29 * this.fontScale).padding({ left: 8, right: 8 })
                .margin({ right: 5, bottom: 5 })
                .backgroundColor(this.selectedPie === index ? '#EAEAEA' : UiTheme.raised).borderRadius(6)
                .onClick(() => {
                  this.selectedPie = index
                  this.chartFilter = item.label
                  this.chartTooltip = `${item.label} · ${item.value} 个节点`
                  this.drawPie()
                  this.buildMindMap()
                })
            }, (item: DistributionItem) => item.label)
          }.width('100%')
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(14 * this.fontScale)
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
      .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.border }).borderRadius(9)
  }
  @Builder
  EmptyState(title: string, detail: string) {
    Column({ space: 5 * this.fontScale }) {
      Text(title).fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
      Text(detail).fontSize(10 * this.fontScale).fontColor(UiTheme.muted).textAlign(TextAlign.Center)
    }.width('100%').padding(28 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
  }
  @Builder
  TableView() {
    Column({ space: 0 }) {
      Row() {
        Column({ space: 3 * this.fontScale }) {
          Text('知识片段表格').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('点击行查看节点详情，命中结果会同步高亮。')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(`${this.activeChunks().length} 条`).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
      }.width('100%').padding({ left: 12, right: 12, top: 12, bottom: 10 })
      Row() {
        Text('知识节点').width('38%'); Text('来源').width('28%'); Text('课程').width('22%'); Text('检索').width('12%')
      }.width('100%').height(32 * this.fontScale).padding({ left: 9, right: 9 })
        .backgroundColor(UiTheme.raised).border({ width: { bottom: 1 }, color: UiTheme.border })
      Scroll() {
        Column() {
          ForEach(this.nodes.filter((node: MindNode) => node.kind === 'chunk'), (node: MindNode, index: number) => {
            Row() {
              Text(node.title).width('38%').fontSize(9 * this.fontScale).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.chunkForNode(node)?.location || node.detail).width('28%').fontSize(9 * this.fontScale).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.chunkForNode(node)?.course || '未分类').width('22%').fontSize(9 * this.fontScale).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.nodeHit(node) ? '命中' : '—').width('12%').fontSize(9 * this.fontScale)
                .fontColor(this.nodeHit(node) ? UiTheme.text : UiTheme.muted)
            }.width('100%').height(36 * this.fontScale).padding({ left: 9, right: 9 })
              .backgroundColor(this.nodeSelected(node) || this.nodeHit(node) ? '#EAEAEA' :
                index % 2 === 0 ? UiTheme.surface : '#FBFBFB')
              .border({ width: { bottom: 1 }, color: UiTheme.border }).hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.selectNode(node))
          }, (node: MindNode) => node.id)
          if (this.nodes.filter((node: MindNode) => node.kind === 'chunk').length === 0) {
            Row() { this.EmptyState('暂无知识节点', '导入资料或清除图表筛选后再查看表格。') }
              .width('100%').padding(12 * this.fontScale)
          }
        }.width('100%')
      }.layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
    }.width('100%').height('100%').border({ width: 1, color: UiTheme.border }).borderRadius(8).clip(true)
  }
  @Builder
  Inspector() {
    Scroll() {
      Column({ space: 9 * this.fontScale }) {
        Text('节点详情').fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
        Text(`${this.activeChunks().length} 个知识片段 · ${this.activeNetwork()?.sources.length || 0} 个来源`)
          .fontSize(8 * this.fontScale).fontColor(UiTheme.muted).width('100%')
        if (this.result !== undefined) {
          Divider().color(UiTheme.border)
          Text(this.result.notice || `${this.result.sources.length} 个检索命中`).fontSize(9 * this.fontScale)
            .fontColor(UiTheme.muted).width('100%')
          ForEach(this.result.sources, (source: SourceCitation) => {
            Button(source.title).height(29 * this.fontScale).fontSize(8 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised).width('100%')
              .onClick(() => {
                const owner = this.networks.find((network: BaseNetwork) => network.sourceIds.has(source.sourceId))
                if (owner !== undefined) {
                  this.selectedBase = owner.base.id
                  this.selectedSource = source.sourceId
                  this.selectedChunk = source.chunkId
                  this.buildMindMap()
                  setTimeout(() => this.drawMindMap(), 20)
                }
              })
          }, (source: SourceCitation) => source.chunkId)
        }
        Divider().color(UiTheme.border)
        if (this.selectedSourceData() !== undefined) {
          Text((this.selectedSourceData() as SourceGroup).title).fontSize(12 * this.fontScale)
            .fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
          Text(`${this.modalityLabel((this.selectedSourceData() as SourceGroup).modality)} · ` +
            `${(this.selectedSourceData() as SourceGroup).course || '未分类'} · ` +
            `${(this.selectedSourceData() as SourceGroup).chunks.length} 片段`)
            .fontSize(8 * this.fontScale).fontColor(UiTheme.muted).width('100%')
          if (this.currentChunk() !== undefined) {
            Text((this.currentChunk() as KnowledgeChunk).content).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.secondary).lineHeight(17 * this.fontScale).width('100%')
            Button('加入当前对话').height(31 * this.fontScale).fontSize(9 * this.fontScale)
              .backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary).width('100%')
              .onClick(() => {
                const chunk = this.currentChunk()
                if (chunk !== undefined) this.useChunk(chunk)
              })
            if (this.relatedNodes().length > 0) {
              Text('关联节点').fontSize(9 * this.fontScale).fontColor(UiTheme.muted).margin({ top: 5 })
              ForEach(this.relatedNodes().slice(0, 6), (node: MindNode) => {
                Button({ type: ButtonType.Normal }) {
                  Text(`${node.title} · ${node.detail}`).fontSize(8 * this.fontScale).fontColor(UiTheme.text)
                    .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.height(29 * this.fontScale).padding({ left: 8, right: 8 })
                  .backgroundColor(UiTheme.raised).width('100%').onClick(() => this.selectNode(node))
              }, (node: MindNode) => node.id)
            }
          } else {
            ForEach((this.selectedSourceData() as SourceGroup).chunks.slice(0, 6),
              (chunk: KnowledgeChunk, index: number) => {
                Button(`片段 ${index + 1} · ${chunk.location}`).height(28 * this.fontScale)
                  .fontSize(8 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                  .width('100%').onClick(() => this.selectedChunk = chunk.id)
              }, (chunk: KnowledgeChunk) => chunk.id)
          }
        } else if (this.selectedBaseData() !== undefined) {
          Text((this.selectedBaseData() as RagKnowledgeBase).name).fontSize(12 * this.fontScale)
            .fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
          Text((this.selectedBaseData() as RagKnowledgeBase).description || '未填写说明')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).lineHeight(15 * this.fontScale).width('100%')
          Text(`${(this.selectedBaseData() as RagKnowledgeBase).embeddingMode === 'online' ? '在线 Embedding' : '本地哈希'} · ` +
            `${(this.selectedBaseData() as RagKnowledgeBase).rerankMode === 'none' ? '不重排' :
              (this.selectedBaseData() as RagKnowledgeBase).rerankMode === 'online' ? '在线重排' : '本地重排'}`)
            .fontSize(8 * this.fontScale).fontColor(UiTheme.muted).width('100%')
          ForEach(this.selectedBaseData() !== undefined ?
            this.networks.find((network: BaseNetwork) =>
              network.base.id === this.selectedBase)?.sources.slice(0, 8) || [] : [],
            (source: SourceGroup) => {
              Button(source.title).height(27 * this.fontScale).fontSize(8 * this.fontScale)
                .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).width('100%')
                .onClick(() => {
                  this.selectedSource = source.sourceId
                  this.selectedChunk = ''
                  this.graphFilter = 'source'
                  this.buildMindMap()
                  setTimeout(() => this.drawMindMap(), 20)
                })
            }, (source: SourceGroup) => source.sourceId)
        } else {
          Text('点击知识库或资料来源节点查看详情。').fontSize(9 * this.fontScale)
            .fontColor(UiTheme.muted).width('100%')
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(10 * this.fontScale)
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
      .backgroundColor(Color.Transparent)
  }
  @Builder
  RelationshipCard() {
    Column({ space: 10 * this.fontScale }) {
      Row({ space: 8 * this.fontScale }) {
        Column({ space: 3 * this.fontScale }) {
          Text('知识关系图').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('每条分割知识是一个节点，单击查看详情并高亮相邻关系。')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(`${this.activeChunks().length} 节点`).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
      }.width('100%')
      Row({ space: 5 * this.fontScale }) {
        this.GraphFilterButton('全部', 'all')
        this.GraphFilterButton('检索命中', 'hit')
        this.GraphFilterButton('当前来源', 'source')
        if (this.chartFilter) {
          Button(`筛选：${this.chartFilter} ×`).height(27 * this.fontScale).fontSize(9 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.secondary)
            .onClick(() => this.applyChartFilter(this.chartFilter))
        }
      }.width('100%')
      if (this.wide()) {
        Row() {
          Column() { this.MindMapCanvas() }.layoutWeight(1).height(520 * this.fontScale)
          Column() { this.Inspector() }.width(286 * this.fontScale).height(520 * this.fontScale)
            .margin({ left: 10 * this.fontScale })
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 10 * this.fontScale }) {
          Column() { this.MindMapCanvas() }.width('100%').height(420 * this.fontScale)
          Column() { this.Inspector() }.width('100%').height(300 * this.fontScale)
        }.width('100%')
      }
    }.width('100%').padding(14 * this.fontScale).backgroundColor(UiTheme.surface)
      .border({ width: 1, color: UiTheme.border }).borderRadius(10)
  }
  build() {
    Column({ space: 10 * this.fontScale }) {
      Row({ space: 7 * this.fontScale }) {
        TextInput({ text: this.query, placeholder: '检索知识网络，命中片段会在图谱中高亮' }).fontSize(11 * this.fontScale)
          .placeholderFont({ size: 11 * this.fontScale }).layoutWeight(1).height(35 * this.fontScale)
          .backgroundColor(UiTheme.surface).borderRadius(7).onChange((value: string) => this.query = value)
          .onSubmit(() => this.search())
        Button(this.busy ? '检索中' : '检索').height(35 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary).enabled(!this.busy).onClick(() => this.search())
      }.width('100%')
      Row({ space: 6 * this.fontScale }) {
        Text(this.selectedBaseData()?.name || '未选择知识库').fontSize(10 * this.fontScale)
          .fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text('当前知识库 · 全部图表同步')
          .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
      }.width('100%')
      if (this.notice || this.chartTooltip) {
        Text(this.chartTooltip || this.notice).fontSize(9 * this.fontScale).fontColor(UiTheme.secondary)
          .width('100%').padding({ left: 9 * this.fontScale, right: 9 * this.fontScale,
            top: 6 * this.fontScale, bottom: 6 * this.fontScale })
          .backgroundColor(UiTheme.raised).borderRadius(6).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.loadError) {
        Column({ space: 8 * this.fontScale }) {
          Text(this.loadError).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          Button('重新加载').height(30 * this.fontScale).fontSize(9 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
            .onClick(() => this.refresh())
        }.width('100%').padding(16 * this.fontScale).backgroundColor('#F5F5F5').borderRadius(8)
      } else if (this.networks.length === 0) {
        this.EmptyState('知识网络为空', '导入资料并选择当前知识库后，片段会自动形成关系节点。')
      } else {
        Scroll() {
          Column({ space: 10 * this.fontScale }) {
            this.RelationshipCard()
            Column() { this.WordCloudView() }.width('100%').height(330 * this.fontScale)
            Column() { this.BarChartView() }.width('100%').height(420 * this.fontScale)
            Column() { this.PieChartView() }.width('100%').height(410 * this.fontScale)
            Column() { this.TableView() }.width('100%').height(450 * this.fontScale)
          }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 12 * this.fontScale })
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
      }
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
      .transition(UiMotion.reveal())
  }
}
