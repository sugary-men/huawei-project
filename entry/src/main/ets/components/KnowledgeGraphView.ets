import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import {
  KnowledgeGraphEdge,
  KnowledgeGraphLayout,
  KnowledgeGraphNode
} from '../models/KnowledgeGraphModels'
import { KnowledgeChunk } from '../models/RagModels'
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
  private draggingNodeId: string = ''
  private dragStartX: number = 0
  private dragStartY: number = 0
  onSelect: (node: KnowledgeGraphNode) => void = () => {}

  aboutToAppear(): void {
    this.buildLayout()
  }

  selectionChanged(): void {
    if (this.canvasReady) this.drawGraph()
  }

  private buildLayout(): void {
    const layout: KnowledgeGraphLayout = KnowledgeGraphLayoutService.build(this.baseId, this.baseName,
      this.chunks, this.graphWidth, this.graphHeight)
    this.nodes = layout.nodes
    this.edges = layout.edges
    setTimeout(() => this.drawGraph(), 20)
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

  private nodeLeft(node: KnowledgeGraphNode): number {
    return node.x * this.graphScale + this.offsetX
  }
  private nodeTop(node: KnowledgeGraphNode): number {
    return node.y * this.graphScale + this.offsetY
  }
  private nodeWidth(node: KnowledgeGraphNode): number {
    return node.width * this.graphScale
  }
  private nodeHeight(node: KnowledgeGraphNode): number {
    return node.height * this.graphScale
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
    this.canvas.restore()
  }

  private selectNode(node: KnowledgeGraphNode): void {
    this.onSelect(node)
    setTimeout(() => this.drawGraph(), 20)
  }

  private startDrag(node: KnowledgeGraphNode): void {
    this.draggingNodeId = node.id
    this.dragStartX = node.x
    this.dragStartY = node.y
  }

  private updateDrag(node: KnowledgeGraphNode, event: GestureEvent): void {
    node.x = this.dragStartX + event.offsetX / this.graphScale
    node.y = this.dragStartY + event.offsetY / this.graphScale
    KnowledgeGraphLayoutService.avoidOverlap(node, this.nodes, this.graphWidth, this.graphHeight)
    this.nodes = this.nodes.slice()
    this.drawGraph()
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
      this.pinchStartDistance = 0
      this.panStartX = 0
      this.panStartY = 0
      return
    }
    if (event.touches.length !== 1) return
    const touch = event.touches[0]
    if (event.type === TouchType.Down) {
      this.panStartX = touch.x
      this.panStartY = touch.y
      this.panOffsetX = this.offsetX
      this.panOffsetY = this.offsetY
    } else if (event.type === TouchType.Move && this.pinchStartDistance <= 0) {
      this.offsetX = this.panOffsetX + touch.x - this.panStartX
      this.offsetY = this.panOffsetY + touch.y - this.panStartY
      this.drawGraph()
    }
  }

  @Builder
  NodeCard(node: KnowledgeGraphNode) {
    Button({ type: ButtonType.Normal }) {
      if (node.kind === 'base') {
        Row({ space: 7 * this.fontScale }) {
          Text('◇').fontSize(13 * this.fontScale).fontColor(UiTheme.onPrimary)
          Column({ space: 2 * this.fontScale }) {
            Text(node.title).fontSize(10 * this.fontScale).fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.onPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(node.detail).fontSize(7 * this.fontScale).fontColor('#D2D2D2')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
      } else {
        Column({ space: 2 * this.fontScale }) {
          Row({ space: 4 * this.fontScale }) {
            if (this.nodeHit(node)) {
              Text('●').fontSize(7 * this.fontScale).fontColor(UiTheme.text)
            }
            Text(node.title).fontSize(8 * this.fontScale).fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }.width('100%')
          Text(node.detail).fontSize(7 * this.fontScale).fontColor(UiTheme.muted)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
    }.width(this.nodeWidth(node)).height(this.nodeHeight(node)).padding({ left: 8, right: 8 })
      .backgroundColor(node.kind === 'base' ? UiTheme.primary :
        this.nodeSelected(node) ? '#ECECEC' : this.nodeHit(node) ? '#F4F4F4' : UiTheme.surface)
      .border({
        width: this.nodeSelected(node) || this.nodeHit(node) ? 2 : 1,
        color: this.nodeSelected(node) ? UiTheme.primary : this.nodeHit(node) ? '#777777' : UiTheme.border
      })
      .borderRadius(node.kind === 'base' ? 8 : 14)
      .position({ x: this.nodeLeft(node), y: this.nodeTop(node) })
      .shadow({ radius: this.nodeSelected(node) ? 8 : 0, color: '#18000000', offsetY: 2 })
      .accessibilityText(node.kind === 'base' ? `知识库 ${node.title}` : `知识节点 ${node.title} ${node.detail}`)
      .onClick(() => this.selectNode(node))
      .gesture(
        PanGesture({ fingers: 1, distance: 3 })
          .onActionStart(() => this.startDrag(node))
          .onActionUpdate((event: GestureEvent) => this.updateDrag(node, event))
          .onActionEnd(() => this.draggingNodeId = '')
          .onActionCancel(() => this.draggingNodeId = '')
      )
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.canvas).width('100%').height('100%')
        .onReady(() => {
          this.canvasReady = true
          this.drawGraph()
        })
        .onTouch((event: TouchEvent) => this.handleCanvasTouch(event))
      ForEach(this.nodes, (node: KnowledgeGraphNode) => {
        this.NodeCard(node)
      }, (node: KnowledgeGraphNode) => node.id)
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
