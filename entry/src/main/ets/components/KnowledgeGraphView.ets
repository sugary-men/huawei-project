import { UiTheme } from '../config/UiTheme'
import {
  KnowledgeGraphEdge,
  KnowledgeGraphLayout,
  KnowledgeGraphNode
} from '../models/KnowledgeGraphModels'
import { KnowledgeChunk } from '../models/RagModels'
import { KnowledgeGraphGeometry, KnowledgeGraphNodeFrame } from '../services/KnowledgeGraphGeometry'
import { KnowledgeGraphLayoutService } from '../services/KnowledgeGraphLayoutService'

@Component
export struct KnowledgeGraphView {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop baseId: string = ''
  @Prop baseName: string = ''
  @Prop chunks: KnowledgeChunk[] = []
  @Prop @Watch('selectionChanged') selectedChunk: string = ''
  @Prop @Watch('selectionChanged') hitChunkIds: string[] = []
  @State nodes: KnowledgeGraphNode[] = []
  @State graphWidth: number = 720
  @State graphHeight: number = 520
  @State graphScale: number = 1
  @State offsetX: number = 0
  @State offsetY: number = 0
  private edges: KnowledgeGraphEdge[] = []
  private render: RenderingContextSettings = new RenderingContextSettings(true)
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.render)
  private canvasReady: boolean = false
  private pinchStartScale: number = 1
  private pinchStartDistance: number = 0
  private panStartX: number = 0
  private panStartY: number = 0
  private panOffsetX: number = 0
  private panOffsetY: number = 0
  private panMoved: boolean = false
  private alive: boolean = true
  private timers: number[] = []
  onSelect: (node: KnowledgeGraphNode) => void = () => {}

  aboutToAppear(): void {
    this.alive = true
    this.buildLayout()
  }
  aboutToDisappear(): void {
    this.alive = false
    this.timers.forEach((timer: number) => clearTimeout(timer))
    this.timers = []
  }

  selectionChanged(): void {
    if (this.canvasReady) this.drawGraph()
  }

  private buildLayout(): void {
    const layout: KnowledgeGraphLayout = KnowledgeGraphLayoutService.build(this.baseId, this.baseName,
      this.chunks, this.graphWidth, this.graphHeight)
    this.nodes = layout.nodes
    this.edges = layout.edges
    this.scheduleDraw()
  }

  private scheduleDraw(): void {
    const timer = setTimeout(() => {
      if (this.alive) this.drawGraph()
    }, 20)
    this.timers.push(timer)
  }

  private node(id: string): KnowledgeGraphNode | undefined {
    return this.nodes.find((item: KnowledgeGraphNode) => item.id === id)
  }

  private activeId(): string {
    return this.selectedChunk.length > 0
      ? `chunk:${this.baseId}:${this.selectedChunk}` : `base:${this.baseId}`
  }

  private edgeRelated(edge: KnowledgeGraphEdge): boolean {
    const active = this.activeId()
    return edge.from === active || edge.to === active
  }

  private nodeRelated(node: KnowledgeGraphNode): boolean {
    return this.edges.some((edge: KnowledgeGraphEdge) =>
      (edge.from === this.activeId() && edge.to === node.id) ||
      (edge.to === this.activeId() && edge.from === node.id))
  }

  private nodeSelected(node: KnowledgeGraphNode): boolean {
    if (node.kind === 'base') return this.selectedChunk.length === 0
    return node.chunkId === this.selectedChunk
  }

  private nodeHit(node: KnowledgeGraphNode): boolean {
    return node.kind === 'chunk' && this.hitChunkIds.includes(node.chunkId)
  }

  private nodeFrame(node: KnowledgeGraphNode): KnowledgeGraphNodeFrame {
    return KnowledgeGraphGeometry.frame(node, this.graphScale, this.offsetX, this.offsetY)
  }

  private edgeStart(node: KnowledgeGraphNode, target: KnowledgeGraphNode): number[] {
    return this.edgePoint(node, target.x + target.width / 2, target.y + target.height / 2)
  }
  private edgeEnd(node: KnowledgeGraphNode, target: KnowledgeGraphNode): number[] {
    return this.edgePoint(node, target.x + target.width / 2, target.y + target.height / 2)
  }
  private edgePoint(node: KnowledgeGraphNode, targetX: number, targetY: number): number[] {
    const centerX = node.x + node.width / 2
    const centerY = node.y + node.height / 2
    const dx = targetX - centerX
    const dy = targetY - centerY
    const factorX = Math.abs(dx) > 0 ? node.width / 2 / Math.abs(dx) : Number.MAX_VALUE
    const factorY = Math.abs(dy) > 0 ? node.height / 2 / Math.abs(dy) : Number.MAX_VALUE
    const factor = Math.min(factorX, factorY)
    return [centerX + dx * factor, centerY + dy * factor]
  }

  private drawGraph(): void {
    if (!this.canvasReady) return
    const width = Math.max(240, this.graphWidth)
    const height = Math.max(300, this.graphHeight)
    this.canvas.clearRect(0, 0, width, height)
    this.canvas.fillStyle = '#FAFAFA'
    this.canvas.fillRect(0, 0, width, height)
    this.canvas.save()
    this.canvas.translate(this.offsetX, this.offsetY)
    this.canvas.scale(this.graphScale, this.graphScale)
    this.edges.forEach((edge: KnowledgeGraphEdge) => {
      const from = this.node(edge.from)
      const to = this.node(edge.to)
      if (from === undefined || to === undefined) return
      const start = this.edgeStart(from, to)
      const end = this.edgeEnd(to, from)
      const active = this.edgeRelated(edge)
      this.canvas.beginPath()
      this.canvas.moveTo(start[0], start[1])
      this.canvas.setLineDash(edge.kind === 'semantic' ? [4, 5] : [])
      this.canvas.globalAlpha = active ? 0.95 : edge.kind === 'semantic' ? 0.32 : 0.26
      this.canvas.strokeStyle = active ? '#303030' : '#AFAFAF'
      this.canvas.lineWidth = active ? 1.8 : 0.9 + edge.weight * 0.5
      this.canvas.lineTo(end[0], end[1])
      this.canvas.stroke()
    })
    this.canvas.setLineDash([])
    this.canvas.globalAlpha = 1
    this.nodes.forEach((node: KnowledgeGraphNode) => {
      const selected = this.nodeSelected(node)
      const hit = this.nodeHit(node)
      const related = this.nodeRelated(node)
      this.canvas.beginPath()
      this.canvas.roundRect(node.x, node.y, node.width, node.height, 12)
      this.canvas.fillStyle = node.kind === 'base' ? UiTheme.primary :
        selected ? '#ECECEC' : hit ? '#F4F4F4' : UiTheme.surface
      this.canvas.fill()
      this.canvas.strokeStyle = selected ? UiTheme.primary : hit || related ? '#777777' : UiTheme.border
      this.canvas.lineWidth = selected || hit ? 1.8 : 1
      this.canvas.stroke()
      this.canvas.fillStyle = node.kind === 'base' ? UiTheme.onPrimary : UiTheme.text
      this.canvas.font = node.kind === 'base' ? '500 11px sans-serif' : '500 10px sans-serif'
      this.canvas.textAlign = 'center'
      this.canvas.textBaseline = 'middle'
      const frame = KnowledgeGraphGeometry.frame(node, 1, 0, 0)
      this.canvas.fillText(this.fitText(node.title, node.width - 18), frame.centerX, frame.centerY)
    })
    this.canvas.restore()
  }

  private fitText(value: string, maxWidth: number): string {
    if (this.canvas.measureText(value).width <= maxWidth) return value
    let content = value
    while (content.length > 1 &&
      this.canvas.measureText(`${content}…`).width > maxWidth) {
      content = content.slice(0, -1)
    }
    return `${content}…`
  }

  private selectNode(node: KnowledgeGraphNode): void {
    this.onSelect(node)
    this.scheduleDraw()
  }

  private zoomBy(value: number): void {
    this.graphScale = Math.max(0.55, Math.min(2.2, this.graphScale + value))
    this.drawGraph()
  }

  private resetView(): void {
    this.graphScale = 1
    this.offsetX = 0
    this.offsetY = 0
    this.buildLayout()
  }

  private handleCanvasTouch(event: TouchEvent): void {
    if (event.touches.length >= 2) {
      const dx = event.touches[0].x - event.touches[1].x
      const dy = event.touches[0].y - event.touches[1].y
      const distance = Math.max(1, Math.sqrt(dx * dx + dy * dy))
      if (this.pinchStartDistance <= 0) {
        this.pinchStartDistance = distance
        this.pinchStartScale = this.graphScale
      } else if (event.type === TouchType.Move) {
        this.graphScale = Math.max(0.55, Math.min(2.2,
          this.pinchStartScale * distance / this.pinchStartDistance))
        this.drawGraph()
      }
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (event.type === TouchType.Up && !this.panMoved && event.changedTouches.length > 0) {
        this.hitNode(event.changedTouches[0].x, event.changedTouches[0].y)
      }
      this.pinchStartDistance = 0
      this.panStartX = 0
      this.panStartY = 0
      this.panMoved = false
      return
    }
    if (event.touches.length !== 1) return
    const touch = event.touches[0]
    if (event.type === TouchType.Down) {
      this.panStartX = touch.x
      this.panStartY = touch.y
      this.panOffsetX = this.offsetX
      this.panOffsetY = this.offsetY
      this.panMoved = false
    } else if (event.type === TouchType.Move && this.pinchStartDistance <= 0) {
      const deltaX = touch.x - this.panStartX
      const deltaY = touch.y - this.panStartY
      if (Math.abs(deltaX) > 3 || Math.abs(deltaY) > 3) {
        this.panMoved = true
        this.offsetX = this.panOffsetX + deltaX
        this.offsetY = this.panOffsetY + deltaY
        this.drawGraph()
      }
    }
  }

  private hitNode(screenX: number, screenY: number): void {
    const selected = this.nodes.find((node: KnowledgeGraphNode) => {
      const frame = this.nodeFrame(node)
      return screenX >= frame.left && screenX <= frame.left + frame.width &&
        screenY >= frame.top && screenY <= frame.top + frame.height
    })
    if (selected !== undefined) {
      this.selectNode(selected)
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.canvas).width('100%').height('100%')
        .onReady(() => {
          this.canvasReady = true
          this.drawGraph()
        })
        .onTouch((event: TouchEvent) => this.handleCanvasTouch(event))
      Row({ space: 4 * this.fontScale }) {
        Button('−').width(26 * this.fontScale).height(26 * this.fontScale).fontSize(13 * this.fontScale)
          .padding(0).backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.border }).borderRadius(5)
          .accessibilityText('缩小知识图谱').onClick(() => this.zoomBy(-0.12))
        Text(`${Math.round(this.graphScale * 100)}%`).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
          .width(38 * this.fontScale).textAlign(TextAlign.Center)
        Button('＋').width(26 * this.fontScale).height(26 * this.fontScale).fontSize(13 * this.fontScale)
          .padding(0).backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.border }).borderRadius(5)
          .accessibilityText('放大知识图谱').onClick(() => this.zoomBy(0.12))
        Button('重置').height(26 * this.fontScale).fontSize(9 * this.fontScale)
          .backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.border }).borderRadius(5)
          .accessibilityText('重置图谱视图').onClick(() => this.resetView())
      }.padding(8 * this.fontScale).position({ x: Math.max(10, this.graphWidth - 178), y: 10 })
    }.width('100%').height('100%').backgroundColor('#FAFAFA')
      .border({ width: 1, color: UiTheme.border }).borderRadius(9).clip(true)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width = parseFloat(String(newValue.width))
        const height = parseFloat(String(newValue.height))
        const changed = (Number.isFinite(width) && Math.abs(width - this.graphWidth) > 1) ||
          (Number.isFinite(height) && Math.abs(height - this.graphHeight) > 1)
        if (Number.isFinite(width) && width > 0) this.graphWidth = width
        if (Number.isFinite(height) && height > 0) this.graphHeight = height
        if (changed) this.buildLayout()
      })
  }
}
