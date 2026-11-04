import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { KnowledgeGraphEdge, KnowledgeGraphNode } from '../models/KnowledgeGraphModels'
import { KnowledgeChunk, RetrievalResult, SourceCitation } from '../models/RagModels'
import { RagKnowledgeBase, RagWorkspaceArchive } from '../models/RagWorkspaceModels'
import { IntegrationService } from '../services/IntegrationService'
import { KnowledgeGraphLayoutService } from '../services/KnowledgeGraphLayoutService'
import { KnowledgeGraphView } from './KnowledgeGraphView'
import { SelectionTab } from './SelectionTab'

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

interface RagChartTone {
  line: string
  fill: string
  soft: string
}

interface ChartCardMeta {
  eyebrow: string
  title: string
  detail: string
  accent: string
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
  @State nodes: KnowledgeGraphNode[] = []
  @State selectedBase: string = ''
  @State selectedSource: string = ''
  @State selectedChunk: string = ''
  @State result: RetrievalResult | undefined = undefined
  @State graphWidth: number = 900
  @State graphHeight: number = 520
  @State graphFilter: string = 'all'
  @State chartFilter: string = ''
  @State chartDimension: string = 'course'
  @State chartTooltip: string = ''
  @State selectedPie: number = -1
  @State pieWidth: number = 420
  @State pieHeight: number = 236
  @State loadError: string = ''
  @State notice: string = ''
  @State leftColumnContentHeight: number = 0
  @State rightColumnContentHeight: number = 0
  private edges: KnowledgeGraphEdge[] = []
  private pieRender: RenderingContextSettings = new RenderingContextSettings(true)
  private pieCanvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.pieRender)
  private alive: boolean = true
  private timers: number[] = []

  aboutToAppear(): void {
    this.alive = true
    this.refresh()
  }
  aboutToDisappear(): void {
    this.alive = false
    this.timers.forEach((timer: number) => clearTimeout(timer))
    this.timers = []
  }

  private schedulePieDraw(delay: number): void {
    const timer = setTimeout(() => {
      if (this.alive) this.drawPie()
    }, delay)
    this.timers.push(timer)
  }

  private wide(): boolean { return this.viewportWidth >= 760 }
  private dashboardColumns(): number { return this.viewportWidth >= 1060 ? 2 : 1 }
  private chartCardHeight(): number {
    return Math.ceil((this.dashboardColumns() === 2 ? 318 : 326) * Math.max(1, this.fontScale))
  }

  @Builder
  StatBlock(value: string, label: string) {
    Column({ space: 5 * this.fontScale }) {
      Text(value).fontSize(24 * this.fontScale).fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.accentStrong)
      Text(label).fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  StatsFiller(height: number) {
    Column({ space: 10 * this.fontScale }) {
      Row({ space: 8 * this.fontScale }) {
        this.StatBlock(`${this.activeChunks().length}`, '知识片段')
        this.StatBlock(`${this.activeNetwork()?.sources.length || 0}`, '来源文档')
      }.width('100%')
      Row({ space: 8 * this.fontScale }) {
        this.StatBlock(`${this.courseCount()}`, '覆盖课程')
        this.StatBlock(`${this.wordCloudItems().length}`, '高频词语')
      }.width('100%')
      Stack({ alignContent: Alignment.BottomStart }) {
        Column().width('100%').height('100%')
          .linearGradient({ angle: 160,
            colors: [[UiTheme.accentPale, 0], [UiTheme.chartPale, 0.62], [UiTheme.chartLight, 1]] })
        Text('知识在于积累 · 检索、关联、沉淀')
          .fontSize(10 * this.fontScale).fontColor(UiTheme.accentStrong)
          .padding({ left: 12 * this.fontScale, right: 12 * this.fontScale,
            bottom: 10 * this.fontScale, top: 10 * this.fontScale })
          .width('100%')
      }.layoutWeight(1).width('100%').borderRadius(10)
        .clip(true)
    }.width('100%').height(height).constraintSize({ minHeight: 150 * this.fontScale })
      .padding(16 * this.fontScale)
      .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
      .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
  }

  @Builder
  StatsStrip() {
    Row({ space: 10 * this.fontScale }) {
      this.StatBlock(`${this.activeChunks().length}`, '知识片段')
      Stack() {
        Row().width(1).height(34 * this.fontScale).backgroundColor(UiTheme.softBorder)
      }.alignContent(Alignment.Center)
      this.StatBlock(`${this.activeNetwork()?.sources.length || 0}`, '来源文档')
      Stack() {
        Row().width(1).height(34 * this.fontScale).backgroundColor(UiTheme.softBorder)
      }.alignContent(Alignment.Center)
      this.StatBlock(`${this.courseCount()}`, '覆盖课程')
      Stack() {
        Row().width(1).height(34 * this.fontScale).backgroundColor(UiTheme.softBorder)
      }.alignContent(Alignment.Center)
      this.StatBlock(`${this.wordCloudItems().length}`, '高频词语')
    }.width('100%').constraintSize({ minHeight: this.chartCardHeight() })
      .justifyContent(FlexAlign.SpaceBetween).alignItems(VerticalAlign.Center)
      .padding({ left: 18 * this.fontScale, right: 18 * this.fontScale,
        top: 16 * this.fontScale, bottom: 16 * this.fontScale })
      .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
      .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
  }

  @Builder
  DashboardHeader() {
    Row({ space: 12 * this.fontScale }) {
      Column({ space: 4 * this.fontScale }) {
        Text('知识概览').fontSize(20 * this.fontScale).fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.softText)
        Text('知识网络、来源分布与检索状态一屏掌握').fontSize(10 * this.fontScale)
          .fontColor(UiTheme.softMuted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(`${this.activeChunks().length} 片段`).fontSize(9 * this.fontScale)
        .fontColor(UiTheme.accentStrong).padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(UiTheme.accentPale).border({ width: 1, color: UiTheme.accentBorder }).borderRadius(8)
    }.width('100%').padding({ left: 16 * this.fontScale, right: 16 * this.fontScale,
      top: 14 * this.fontScale, bottom: 14 * this.fontScale })
      .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
      .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
  }

  @Builder
  CardHeader(meta: ChartCardMeta, value: string = '') {
    Row({ space: 10 * this.fontScale }) {
      Row().width(4 * this.fontScale).height(36 * this.fontScale)
        .backgroundColor(this.tone(meta.accent).line).borderRadius(2)
      Column({ space: 3 * this.fontScale }) {
        Text(meta.eyebrow).fontSize(8 * this.fontScale).fontColor(UiTheme.softMuted)
          .fontWeight(FontWeight.Medium)
        Text(meta.title).fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.softText)
        Text(meta.detail).fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (value.length > 0) {
        Text(value).fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .backgroundColor(UiTheme.softSurface).borderRadius(7)
      }
    }.width('100%').alignItems(VerticalAlign.Center)
  }

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

  private courseCount(): number {
    const courses = new Set<string>()
    this.activeChunks().forEach((chunk: KnowledgeChunk) => {
      const course = chunk.course.trim()
      if (course.length > 0) courses.add(course)
    })
    return courses.size
  }

  private columnGap(): number { return 14 * this.fontScale }

  private leftFillerHeight(): number {
    return Math.max(0, Math.round(this.rightColumnContentHeight -
      this.leftColumnContentHeight - this.columnGap()))
  }

  private rightFillerHeight(): number {
    return Math.max(0, Math.round(this.leftColumnContentHeight -
      this.rightColumnContentHeight - this.columnGap()))
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
    const network = this.activeNetwork()
    if (network === undefined) {
      this.nodes = []
      this.edges = []
      return
    }
    const layout = KnowledgeGraphLayoutService.build(network.base.id, network.base.name,
      this.graphChunks(network), this.graphWidth, this.graphHeight)
    this.nodes = layout.nodes
    this.edges = layout.edges
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
  private nodeSelected(node: KnowledgeGraphNode): boolean {
    if (node.kind === 'base') return node.baseId === this.selectedBase && this.selectedSource.length === 0
    return this.selectedChunk === node.chunkId
  }
  private chunkForNode(node: KnowledgeGraphNode): KnowledgeChunk | undefined {
    return this.activeChunks().find((chunk: KnowledgeChunk) => chunk.id === node.chunkId)
  }
  private nodeHit(node: KnowledgeGraphNode): boolean {
    return node.kind === 'chunk' && this.result?.sources.some((source: SourceCitation) =>
      source.chunkId === node.chunkId) === true
  }
  private relatedNodes(): KnowledgeGraphNode[] {
    if (!this.selectedChunk) return []
    const activeId = `chunk:${this.selectedBase}:${this.selectedChunk}`
    const ids = new Set<string>()
    this.edges.forEach((edge: KnowledgeGraphEdge) => {
      if (edge.from === activeId) ids.add(edge.to)
      if (edge.to === activeId) ids.add(edge.from)
    })
    return this.nodes.filter((node: KnowledgeGraphNode) => node.kind === 'chunk' && ids.has(node.id))
  }
  private selectNode(node: KnowledgeGraphNode): void {
    this.getUIContext().animateTo({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.enterCurve }, () => {
      this.selectedBase = node.baseId
      if (node.kind === 'chunk') {
        this.selectedSource = node.sourceId
        this.selectedChunk = node.chunkId
      } else {
        this.selectedSource = ''
        this.selectedChunk = ''
      }
    })
    this.chartTooltip = `${node.title} · ${node.detail}`
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
    return [UiTheme.accent, UiTheme.chartMid, UiTheme.chartLight,
      '#819FA9', '#94AFB8', '#B3C8CF', '#C7D8DE', UiTheme.accentPale]
  }
  private tone(accent: string): RagChartTone {
    if (accent === 'dark') return { line: UiTheme.accentStrong, fill: UiTheme.accent, soft: UiTheme.accentPale }
    if (accent === 'medium') return { line: UiTheme.accent, fill: UiTheme.chartMid, soft: UiTheme.accentPale }
    return { line: UiTheme.chartMid, fill: UiTheme.chartLight, soft: UiTheme.softSurface }
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
    this.getUIContext().animateTo({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.enterCurve }, () => {
      this.chartFilter = this.chartFilter === label ? '' : label
      this.chartTooltip = this.chartFilter.length > 0
        ? `${label} · ${this.activeChunks().filter((chunk: KnowledgeChunk) => this.chartLabel(chunk) === label).length} 个知识片段`
        : '已清除图表筛选。'
    })
    this.buildMindMap()
  }
  private setChartDimension(value: string): void {
    this.getUIContext().animateTo({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.enterCurve }, () => {
      this.chartDimension = value
      this.chartFilter = ''
      this.chartTooltip = ''
      this.selectedPie = -1
    })
    this.schedulePieDraw(30)
  }
  private drawPie(): void {
    const items = this.distribution()
    const width = Math.max(260, this.pieWidth)
    const height = Math.max(190, this.pieHeight)
    this.pieCanvas.clearRect(0, 0, width, height)
    this.pieCanvas.fillStyle = UiTheme.surface
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
        this.pieCanvas.strokeStyle = UiTheme.surface
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
  @Builder
  GraphFilterButton(label: string, value: string) {
    SelectionTab({ label: label, selected: this.graphFilter === value, showIndicator: false,
      onSelect: () => {
        this.graphFilter = value
        this.chartFilter = ''
        this.buildMindMap()
      } })
  }
  @Builder
  DimensionButton(label: string, value: string) {
    SelectionTab({ label: label, selected: this.chartDimension === value, showIndicator: false,
      onSelect: () => this.setChartDimension(value) })
  }
  @Builder
  MindMapCanvas() {
    ForEach([`${this.selectedBase}:${this.graphFilter}:${this.chartFilter}:${this.result?.revision || ''}`],
      (key: string) => {
        KnowledgeGraphView({
          baseId: this.selectedBase,
          baseName: this.selectedBaseData()?.name || '当前知识库',
          chunks: this.activeNetwork() === undefined ? [] : this.graphChunks(this.activeNetwork() as BaseNetwork),
          selectedChunk: this.selectedChunk,
          hitChunkIds: this.result?.sources.map((source: SourceCitation) => source.chunkId) || [],
          onSelect: (node: KnowledgeGraphNode) => this.selectNode(node)
        }).width('100%').height('100%')
      }, (key: string) => key)
  }
  @Builder
  WordCloudView() {
    Column({ space: 12 * this.fontScale }) {
      this.CardHeader({ eyebrow: '知识概览', title: '知识词云',
        detail: '点击词语重新检索并在图谱中高亮相关片段', accent: 'medium' },
        `${this.wordCloudItems().length} 个词`)
      if (this.wordCloudItems().length === 0) {
        this.EmptyState('暂无可提取词语', '导入资料或添加图片描述后再查看词云。')
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
          ForEach(this.wordCloudItems(), (item: WordCloudItem, index: number) => {
            Text(item.term).fontSize(item.size * this.fontScale)
              .fontColor(item.color).fontWeight(index < 6 ? FontWeight.Medium : FontWeight.Regular)
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .margin(3).backgroundColor(index % 3 === 0 ? UiTheme.accentPale : Color.Transparent)
              .borderRadius(12).accessibilityText(`关键词 ${item.term}，出现 ${item.count} 次`)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.query = item.term
                this.chartTooltip = `正在检索关键词：${item.term}`
                this.search()
              })
          }, (item: WordCloudItem) => item.term)
        }.width('100%').padding(14 * this.fontScale)
      }
    }.width('100%').constraintSize({ minHeight: this.chartCardHeight() }).padding(16 * this.fontScale)
      .backgroundColor(UiTheme.surface)
      .border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
      .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
  }
  @Builder
  BarChartView() {
    Column({ space: 12 * this.fontScale }) {
        this.CardHeader({ eyebrow: '来源分析', title: '知识分布',
          detail: '按课程或标签统计节点数量，点击柱条联动筛选', accent: 'medium' }, `${this.distribution().length} 组`)
        if (this.chartFilter) {
          Button('清除当前筛选 ×').height(28 * this.fontScale).fontSize(9 * this.fontScale)
            .backgroundColor(UiTheme.accentPale).fontColor(UiTheme.accentStrong).borderRadius(7)
            .onClick(() => this.applyChartFilter(this.chartFilter))
        }
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
                Text(item.label).fontSize(10 * this.fontScale)
                  .fontColor(this.chartFilter === item.label ?
                    UiTheme.softText : UiTheme.softMuted)
                  .layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${item.value} 节点`).fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
              }.width('100%')
              Stack({ alignContent: Alignment.Start }) {
                Row().width('100%').height(8 * this.fontScale).backgroundColor(UiTheme.accentPale).borderRadius(4)
                Row().width(`${Math.max(5, item.value / this.maxDistribution() * 100)}%`)
                  .height(8 * this.fontScale).backgroundColor(item.color).borderRadius(4)
                  .opacity(this.chartFilter.length === 0 || this.chartFilter === item.label ? 1 : 0.28)
                  .animation({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.enterCurve })
              }.width('100%')
            }.width('100%').padding({ left: 11, right: 11, top: 9, bottom: 9 })
              .backgroundColor(this.chartFilter === item.label ?
                UiTheme.accentPale : UiTheme.surface)
              .border({ width: 1, color: this.chartFilter === item.label ? UiTheme.accentBorder : UiTheme.softBorder })
              .borderRadius(9).hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.applyChartFilter(item.label))
          }, (item: DistributionItem) => item.label)
        }
    }.width('100%').constraintSize({ minHeight: this.chartCardHeight() }).alignItems(HorizontalAlign.Start).padding(16 * this.fontScale)
      .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
      .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
  }
  @Builder
  PieChartView() {
    Column({ space: 12 * this.fontScale }) {
        this.CardHeader({ eyebrow: '结构分析', title: '知识维度占比',
          detail: '点击扇区或图例查看占比，并联动知识图谱筛选', accent: 'dark' },
          `${this.distribution().length} 项`)
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
              this.schedulePieDraw(20)
            })
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.distribution(), (item: DistributionItem, index: number) => {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 6 * this.fontScale }) {
                  Row().width(8 * this.fontScale).height(8 * this.fontScale)
                    .backgroundColor(item.color).borderRadius(4)
                  Text(`${item.label} ${item.value}`).fontSize(9 * this.fontScale)
                    .fontColor(this.selectedPie === index ?
                      UiTheme.softText : UiTheme.softMuted)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.height(29 * this.fontScale).padding({ left: 8, right: 8 })
                .margin({ right: 5, bottom: 5 })
                .backgroundColor(this.selectedPie === index ?
                  UiTheme.accentPale : Color.Transparent).borderRadius(6)
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
    }.width('100%').constraintSize({ minHeight: this.chartCardHeight() }).alignItems(HorizontalAlign.Start).padding(16 * this.fontScale)
      .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
      .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
  }
  @Builder
  EmptyState(title: string, detail: string) {
    Column({ space: 5 * this.fontScale }) {
      Text(title).fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.softText)
      Text(detail).fontSize(10 * this.fontScale).fontColor(UiTheme.softMuted).textAlign(TextAlign.Center)
    }.width('100%').padding(28 * this.fontScale).backgroundColor(UiTheme.softSurface).borderRadius(12)
  }
  @Builder
  TableView() {
    Column({ space: 0 }) {
      Column() {
        this.CardHeader({ eyebrow: '明细', title: '知识片段表格',
          detail: '点击行查看节点详情，命中结果会同步高亮', accent: 'medium' },
          `${this.activeChunks().length} 条`)
      }.width('100%').padding(16 * this.fontScale)
      Row() {
        Text('知识节点').width('38%').fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
        Text('来源').width('28%').fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
        Text('课程').width('22%').fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
        Text('检索').width('12%').fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
      }.width('100%').height(32 * this.fontScale).padding({ left: 9, right: 9 })
        .backgroundColor(UiTheme.softSurface).border({ width: { bottom: 1 }, color: UiTheme.softBorder })
      Column() {
          ForEach(this.nodes.filter((node: KnowledgeGraphNode) => node.kind === 'chunk'),
            (node: KnowledgeGraphNode, index: number) => {
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
              .backgroundColor(this.nodeSelected(node) || this.nodeHit(node) ? UiTheme.accentPale :
                index % 2 === 0 ? UiTheme.surface : '#F8FBFC')
              .border({ width: { bottom: 1 }, color: UiTheme.softBorder }).hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.selectNode(node))
          }, (node: KnowledgeGraphNode) => node.id)
          if (this.nodes.filter((node: KnowledgeGraphNode) => node.kind === 'chunk').length === 0) {
            Row() { this.EmptyState('暂无知识节点', '导入资料或清除图表筛选后再查看表格。') }
              .width('100%').padding(12 * this.fontScale)
          }
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: this.chartCardHeight() })
      .border({ width: 1, color: UiTheme.softBorder }).borderRadius(16).clip(true)
      .backgroundColor(UiTheme.surface)
  }
  @Builder
  Inspector() {
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
              ForEach(this.relatedNodes().slice(0, 6), (node: KnowledgeGraphNode) => {
                Button({ type: ButtonType.Normal }) {
                  Text(`${node.title} · ${node.detail}`).fontSize(8 * this.fontScale).fontColor(UiTheme.text)
                    .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.height(29 * this.fontScale).padding({ left: 8, right: 8 })
                  .backgroundColor(UiTheme.raised).width('100%').onClick(() => this.selectNode(node))
              }, (node: KnowledgeGraphNode) => node.id)
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
                })
            }, (source: SourceGroup) => source.sourceId)
        } else {
          Text('点击知识库或资料来源节点查看详情。').fontSize(9 * this.fontScale)
            .fontColor(UiTheme.muted).width('100%')
        }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(10 * this.fontScale)
      .backgroundColor(Color.Transparent)
  }
  @Builder
  RelationshipCard() {
    Column({ space: 10 * this.fontScale }) {
      this.CardHeader({ eyebrow: '知识网络', title: '知识关系图',
        detail: '每条知识片段是一个节点，单击查看详情并高亮相邻关系', accent: 'medium' },
        `${this.activeChunks().length} 节点`)
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
          Column() { this.Inspector() }.width(286 * this.fontScale)
            .margin({ left: 10 * this.fontScale })
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 10 * this.fontScale }) {
          Column() { this.MindMapCanvas() }.width('100%').height(420 * this.fontScale)
          Column() { this.Inspector() }.width('100%')
        }.width('100%')
      }
    }.width('100%').padding(16 * this.fontScale).backgroundColor(UiTheme.surface)
      .border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
      .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
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
        }.width('100%').padding(16 * this.fontScale).backgroundColor(UiTheme.softSurface).borderRadius(8)
      } else if (this.networks.length === 0) {
        this.EmptyState('知识网络为空', '导入资料并选择当前知识库后，片段会自动形成关系节点。')
      } else {
        this.DashboardHeader()
        Scroll() {
          Column({ space: 14 * this.fontScale }) {
            this.RelationshipCard()
            if (this.dashboardColumns() === 2) {
              Row({ space: this.columnGap() }) {
                Column({ space: this.columnGap() }) {
                  Column({ space: this.columnGap() }) {
                    this.BarChartView()
                    this.WordCloudView()
                  }.width('100%')
                    .onAreaChange((_oldValue: Area, newValue: Area) => {
                      const height = parseFloat(String(newValue.height))
                      if (Number.isFinite(height) && height > 0) this.leftColumnContentHeight = height
                    })
                  if (this.leftFillerHeight() > 0) {
                    this.StatsFiller(this.leftFillerHeight())
                  }
                }.layoutWeight(1)
                Column({ space: this.columnGap() }) {
                  Column({ space: this.columnGap() }) {
                    this.PieChartView()
                    this.TableView()
                  }.width('100%')
                    .onAreaChange((_oldValue: Area, newValue: Area) => {
                      const height = parseFloat(String(newValue.height))
                      if (Number.isFinite(height) && height > 0) this.rightColumnContentHeight = height
                    })
                  if (this.rightFillerHeight() > 0) {
                    this.StatsFiller(this.rightFillerHeight())
                  }
                }.layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
            } else {
              Column({ space: 14 * this.fontScale }) {
                this.BarChartView()
                this.PieChartView()
                this.WordCloudView()
                this.TableView()
                this.StatsStrip()
              }.width('100%')
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
            .padding({ right: 16 * this.fontScale, bottom: 12 * this.fontScale })
        }.layoutWeight(1).width('100%').scrollBar(BarState.On).scrollBarWidth(6)
          .scrollBarColor(UiTheme.secondary).align(Alignment.TopStart)
          .nestedScroll({
            scrollForward: NestedScrollMode.SELF_FIRST,
            scrollBackward: NestedScrollMode.SELF_FIRST
          })
      }
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
      .transition(UiMotion.reveal())
  }
}
