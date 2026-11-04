import { common } from '@kit.AbilityKit'
import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { FocusAnalyticsArchive, FocusCategory, FocusCheckIn } from '../models/FocusAnalyticsModels'
import { ModuleItem } from '../models/IntegrationModels'
import { FocusAnalyticsService } from '../services/FocusAnalyticsService'
import { FocusWorkspaceController } from '../services/FocusWorkspaceController'

interface FocusDayPoint {
  key: string
  label: string
  count: number
  minutes: number
}

interface FocusCategoryShare {
  category: FocusCategory
  count: number
  minutes: number
  ratio: number
}

interface FocusHeatCell {
  key: string
  day: number
  count: number
  level: number
  inMonth: boolean
  today: boolean
}

interface FocusMenuOption {
  value: string
  action: () => void
}

@Component
export struct FocusWorkspacePanel {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @StorageLink('focusWorkMinutes') workMinutes: number = 25
  @StorageLink('focusBreakMinutes') breakMinutes: number = 5
  @StorageLink('focusRemainingSeconds') remainingSeconds: number = 25 * 60
  @StorageLink('focusRunning') running: boolean = false
  @StorageLink('focusPhase') phase: string = 'focus'
  @StorageLink('focusCompleted') completed: number = 0
  @StorageLink('focusWhitelistTokens') whitelistTokens: string[] = []
  @StorageLink('focusGuardNotice') guardNotice: string = ''
  @StorageLink('focusGuardActive') guardActive: boolean = false
  @StorageLink('focusGuardEnabled') guardEnabled: boolean = true
  @StorageLink('focusGuardBusy') guardBusy: boolean = false
  @StorageLink('focusSessionBusy') sessionBusy: boolean = false
  @StorageLink('focusHardwareBusy') hardwareBusy: boolean = false
  @StorageLink('focusModuleNotice') moduleNotice: string = ''
  @StorageLink('focusModuleItems') moduleItems: ModuleItem[] = []
  @Prop compact: boolean = false
  @Prop showClose: boolean = false
  @Prop viewportWidth: number = 1280
  @State analytics: FocusAnalyticsArchive = { version: 1, categories: [], checkIns: [] }
  @State selectedCategoryId: string = ''
  @State newCategoryName: string = ''
  @State categoryEditorVisible: boolean = false
  @State notice: string = ''
  @State leftColumnContentHeight: number = 0
  @State rightColumnContentHeight: number = 0
  private dailyWidth: number = 420
  private weeklyWidth: number = 420
  private pieWidth: number = 360
  private pieHeight: number = 190
  @State syncRunning: boolean = false
  private service: FocusAnalyticsService | undefined = undefined
  private syncedCompletion: number = -1
  private readonly dailyRender: RenderingContextSettings = new RenderingContextSettings(true)
  private readonly dailyCanvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.dailyRender)
  private readonly weeklyRender: RenderingContextSettings = new RenderingContextSettings(true)
  private readonly weeklyCanvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.weeklyRender)
  private readonly pieRender: RenderingContextSettings = new RenderingContextSettings(true)
  private readonly pieCanvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.pieRender)
  private timer: number = -1
  onClose: () => void = () => {}

  aboutToAppear(): void {
    this.service = new FocusAnalyticsService(this.context().filesDir)
    this.reloadAnalytics()
    this.timer = setInterval(() => this.syncCompletedSessions(), 1500)
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) clearInterval(this.timer)
    this.timer = -1
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private isWide(): boolean { return this.viewportWidth >= 900 }
  private chartCanvasHeight(): number { return 166 }
  private chartCardHeight(): number {
    return Math.max(258, Math.ceil((44 + 30) * this.fontScale + this.chartCanvasHeight()))
  }
  private heatmapCardHeight(): number {
    return Math.max(258, Math.ceil(354 * this.fontScale))
  }

  private reloadAnalytics(): void {
    if (this.service === undefined) return
    this.analytics = this.service.snapshot()
    if (!this.analytics.categories.some((item: FocusCategory) => item.id === this.selectedCategoryId)) {
      this.selectedCategoryId = this.analytics.categories[0]?.id || ''
    }
    this.syncCompletedSessions()
    this.drawCharts()
  }

  private syncCompletedSessions(): void {
    if (this.service === undefined) return
    if (this.syncedCompletion < 0) this.syncedCompletion = this.completed
    if (this.completed <= this.syncedCompletion || this.syncRunning) return
    const delta = Math.min(20, this.completed - this.syncedCompletion)
    const categoryId = this.selectedCategoryId || this.analytics.categories[0]?.id || ''
    if (!categoryId) return
    this.syncRunning = true
    const minutes = this.workMinutes
    try {
      for (let index = 0; index < delta; index++) {
        this.analytics = this.service.checkIn(categoryId, minutes, '番茄钟')
      }
      this.syncedCompletion = this.completed
      this.notice = `已完成 ${minutes} 分钟专注，已计入「${this.categoryName(categoryId)}」。`
      this.drawCharts()
    } catch (error) {
      this.notice = (error as Error).message || '打卡记录同步失败。'
    } finally {
      this.syncRunning = false
    }
  }

  private addManualCheckIn(): void {
    const category = this.selectedCategory()
    if (category === undefined) return
    try {
      if (this.service === undefined) throw new Error('自律数据服务尚未就绪。')
      this.analytics = this.service.checkIn(category.id, this.workMinutes, '手动打卡')
      this.notice = `已记录 ${this.workMinutes} 分钟「${category.name}」。`
      this.drawCharts()
    } catch (error) {
      this.notice = (error as Error).message || '打卡失败。'
    }
  }

  private addCategory(): void {
    try {
      if (this.service === undefined) throw new Error('自律数据服务尚未就绪。')
      this.analytics = this.service.addCategory(this.newCategoryName)
      const added = this.analytics.categories.find((item: FocusCategory) => item.name === this.newCategoryName.trim())
      if (added !== undefined) this.selectedCategoryId = added.id
      this.newCategoryName = ''
      this.categoryEditorVisible = false
      this.drawCharts()
    } catch (error) {
      this.notice = (error as Error).message || '添加类别失败。'
    }
  }

  private async deleteCategory(category: FocusCategory): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除自律类别',
        message: `删除「${category.name}」后，历史打卡会转移至其他类别。`,
        buttons: [{ text: '取消', color: UiTheme.secondary }, { text: '删除', color: UiTheme.danger }]
      })
      if (result.index !== 1 || this.service === undefined) return
      this.analytics = this.service.deleteCategory(category.id)
      this.selectedCategoryId = this.analytics.categories[0]?.id || ''
      this.reloadAnalytics()
    } catch (error) {
      if ((error as Error).message !== 'cancel') this.notice = (error as Error).message || '删除类别失败。'
    }
  }

  private selectedCategory(): FocusCategory | undefined {
    return this.analytics.categories.find((item: FocusCategory) => item.id === this.selectedCategoryId) ||
      this.analytics.categories[0]
  }

  private categoryMenu(): FocusMenuOption[] {
    return this.analytics.categories.map((item: FocusCategory): FocusMenuOption => ({
      value: item.name,
      action: () => {
        this.selectedCategoryId = item.id
        this.drawPie()
      }
    }))
  }

  private categoryName(id: string): string {
    return this.analytics.categories.find((item: FocusCategory) => item.id === id)?.name || '未分类'
  }

  private monochromeTone(index: number): string {
    const tones: string[] = [UiTheme.chartInk, UiTheme.chartMid, UiTheme.chartLight, UiTheme.chartPale]
    return tones[Math.max(0, index) % tones.length]
  }

  private categoryTone(id: string): string {
    const index = this.analytics.categories.findIndex((item: FocusCategory) => item.id === id)
    return this.monochromeTone(index < 0 ? 0 : index)
  }

  private dailyPoints(days: number): FocusDayPoint[] {
    const result: FocusDayPoint[] = []
    const now = new Date()
    now.setHours(12, 0, 0, 0)
    for (let offset = days - 1; offset >= 0; offset--) {
      const date = new Date(now.getTime() - offset * 86400000)
      const key = FocusAnalyticsService.dateKey(date.getTime())
      const rows = this.analytics.checkIns.filter((item: FocusCheckIn) => item.dateKey === key)
      result.push({ key: key, label: `${date.getMonth() + 1}/${date.getDate()}`,
        count: rows.length, minutes: rows.reduce((sum: number, item: FocusCheckIn) => sum + item.minutes, 0) })
    }
    return result
  }

  private categoryShares(): FocusCategoryShare[] {
    const total = Math.max(1, this.analytics.checkIns.length)
    return this.analytics.categories.map((category: FocusCategory): FocusCategoryShare => {
      const rows = this.analytics.checkIns.filter((item: FocusCheckIn) => item.categoryId === category.id)
      return { category: category, count: rows.length,
        minutes: rows.reduce((sum: number, item: FocusCheckIn) => sum + item.minutes, 0),
        ratio: rows.length / total }
    })
  }

  private todayCount(): number {
    const key = FocusAnalyticsService.dateKey(Date.now())
    return this.analytics.checkIns.filter((item: FocusCheckIn) => item.dateKey === key).length
  }

  private weekPoints(): FocusDayPoint[] {
    const points: FocusDayPoint[] = []
    const today = new Date()
    today.setHours(12, 0, 0, 0)
    const monday = new Date(today.getTime() - ((today.getDay() + 6) % 7) * 86400000)
    for (let index = 0; index < 7; index++) {
      const date = new Date(monday.getTime() + index * 86400000)
      const key = FocusAnalyticsService.dateKey(date.getTime())
      const rows = this.analytics.checkIns.filter((item: FocusCheckIn) => item.dateKey === key)
      points.push({ key: key, label: `${date.getMonth() + 1}/${date.getDate()}`,
        count: rows.length, minutes: rows.reduce((sum: number, item: FocusCheckIn) => sum + item.minutes, 0) })
    }
    return points
  }

  private monthCells(): FocusHeatCell[] {
    const cells: FocusHeatCell[] = []
    const now = new Date()
    const month = now.getMonth()
    const first = new Date(now.getFullYear(), month, 1)
    const mondayOffset = (first.getDay() + 6) % 7
    const todayKey = FocusAnalyticsService.dateKey(now.getTime())
    for (let index = 0; index < 42; index++) {
      const date = new Date(now.getFullYear(), month, 1 + index - mondayOffset, 12)
      const key = FocusAnalyticsService.dateKey(date.getTime())
      const count = this.analytics.checkIns.filter((item: FocusCheckIn) => item.dateKey === key).length
      cells.push({ key: key, day: date.getDate(), count: count,
        level: count >= 4 ? 4 : count === 3 ? 3 : count === 2 ? 2 : count === 1 ? 1 : 0,
        inMonth: date.getMonth() === month, today: key === todayKey })
    }
    return cells
  }

  private monthCheckInCount(): number {
    let total = 0
    this.monthCells().forEach((cell: FocusHeatCell) => {
      if (cell.inMonth) total += cell.count
    })
    return total
  }

  private weekCheckInCount(): number {
    let total = 0
    this.weekPoints().forEach((point: FocusDayPoint) => {
      total += point.count
    })
    return total
  }

  private monthLabel(): string {
    const now = new Date()
    return `${now.getFullYear()} 年 ${now.getMonth() + 1} 月`
  }

  private heatColor(level: number, inMonth: boolean): string {
    if (!inMonth) return UiTheme.heatOutside
    if (level === 0) return UiTheme.accentPale
    if (level === 1) return UiTheme.chartPale
    if (level === 2) return UiTheme.chartLight
    if (level === 3) return UiTheme.chartMid
    return UiTheme.chartInk
  }

  private drawDailyChart(): void {
    const points = this.dailyPoints(14)
    const width = Math.max(260, this.dailyWidth)
    const height = this.chartCanvasHeight()
    this.dailyCanvas.clearRect(0, 0, width, height)
    this.dailyCanvas.fillStyle = UiTheme.surface
    this.dailyCanvas.fillRect(0, 0, width, height)
    const left = 20, right = 10, top = 10, bottom = 28
    const chartWidth = Math.max(120, width - left - right)
    const chartHeight = Math.max(80, height - top - bottom)
    this.dailyCanvas.strokeStyle = UiTheme.chartGrid
    this.dailyCanvas.lineWidth = 1
    this.dailyCanvas.fillStyle = UiTheme.muted
    this.dailyCanvas.font = '9px HarmonyOS Sans'
    this.dailyCanvas.textAlign = 'center'
    const max = Math.max(1, ...points.map((point: FocusDayPoint) => point.count))
    for (let row = 0; row <= 3; row++) {
      const y = top + chartHeight * row / 3
      this.dailyCanvas.beginPath()
      this.dailyCanvas.moveTo(left, y)
      this.dailyCanvas.lineTo(left + chartWidth, y)
      this.dailyCanvas.stroke()
    }
    const gap = chartWidth / points.length
    const barWidth = Math.max(6, Math.min(22, gap * 0.56))
    points.forEach((point: FocusDayPoint, index: number) => {
      const barHeight = point.count === 0 ? 0 : Math.max(5, chartHeight * point.count / max)
      const x = left + gap * index + (gap - barWidth) / 2
      const y = top + chartHeight - barHeight
      this.dailyCanvas.fillStyle = index === points.length - 1 ? UiTheme.chartInk : UiTheme.chartLight
      if (barHeight > 0) {
        this.dailyCanvas.beginPath()
        this.dailyCanvas.roundRect(x, y, barWidth, barHeight, 4)
        this.dailyCanvas.fill()
      }
      if (index % 2 === 0 || index === points.length - 1) {
        this.dailyCanvas.fillStyle = UiTheme.muted
        this.dailyCanvas.fillText(point.label, x + barWidth / 2, height - 8)
      }
    })
  }

  private drawWeeklyChart(): void {
    const points = this.weekPoints()
    const width = Math.max(260, this.weeklyWidth)
    const height = this.chartCanvasHeight()
    this.weeklyCanvas.clearRect(0, 0, width, height)
    this.weeklyCanvas.fillStyle = UiTheme.surface
    this.weeklyCanvas.fillRect(0, 0, width, height)
    const left = 20, right = 14, top = 14, bottom = 28
    const chartWidth = Math.max(120, width - left - right)
    const chartHeight = Math.max(70, height - top - bottom)
    this.weeklyCanvas.strokeStyle = UiTheme.chartGrid
    this.weeklyCanvas.lineWidth = 1
    for (let row = 0; row <= 3; row++) {
      const y = top + chartHeight * row / 3
      this.weeklyCanvas.beginPath()
      this.weeklyCanvas.moveTo(left, y)
      this.weeklyCanvas.lineTo(left + chartWidth, y)
      this.weeklyCanvas.stroke()
    }
    const max = Math.max(1, ...points.map((point: FocusDayPoint) => point.count))
    const step = chartWidth / Math.max(1, points.length - 1)
    this.weeklyCanvas.beginPath()
    points.forEach((point: FocusDayPoint, index: number) => {
      const x = left + step * index
      const y = top + chartHeight - chartHeight * point.count / max
      if (index === 0) this.weeklyCanvas.moveTo(x, y)
      else this.weeklyCanvas.lineTo(x, y)
    })
    this.weeklyCanvas.strokeStyle = UiTheme.chartMid
    this.weeklyCanvas.lineWidth = 2
    this.weeklyCanvas.stroke()
    this.weeklyCanvas.font = '9px HarmonyOS Sans'
    this.weeklyCanvas.textAlign = 'center'
    points.forEach((point: FocusDayPoint, index: number) => {
      const x = left + step * index
      const y = top + chartHeight - chartHeight * point.count / max
      this.weeklyCanvas.beginPath()
      this.weeklyCanvas.arc(x, y, 4, 0, Math.PI * 2)
      this.weeklyCanvas.fillStyle = UiTheme.surface
      this.weeklyCanvas.fill()
      this.weeklyCanvas.strokeStyle = index === points.length - 1 ? UiTheme.chartInk : UiTheme.chartMid
      this.weeklyCanvas.lineWidth = 2
      this.weeklyCanvas.stroke()
      this.weeklyCanvas.fillStyle = UiTheme.muted
      this.weeklyCanvas.fillText(point.label, x, height - 8)
    })
  }

  private drawPie(): void {
    const items = this.categoryShares().filter((item: FocusCategoryShare) => item.count > 0)
    const width = Math.max(240, this.pieWidth)
    const height = Math.max(150, this.pieHeight)
    this.pieCanvas.clearRect(0, 0, width, height)
    this.pieCanvas.fillStyle = UiTheme.surface
    this.pieCanvas.fillRect(0, 0, width, height)
    const total = items.reduce((sum: number, item: FocusCategoryShare) => sum + item.count, 0)
    const cx = width / 2
    const cy = height / 2
    const radius = Math.max(48, Math.min(width, height) * 0.37)
    if (total === 0) {
      this.pieCanvas.beginPath()
      this.pieCanvas.arc(cx, cy, radius, 0, Math.PI * 2)
      this.pieCanvas.fillStyle = UiTheme.accentPale
      this.pieCanvas.fill()
      this.pieCanvas.fillStyle = UiTheme.muted
      this.pieCanvas.font = '10px HarmonyOS Sans'
      this.pieCanvas.textAlign = 'center'
      this.pieCanvas.fillText('暂无打卡数据', cx, cy + 4)
      return
    }
    let angle = -Math.PI / 2
    items.forEach((item: FocusCategoryShare, index: number) => {
      const next = angle + Math.PI * 2 * item.count / total
      this.pieCanvas.beginPath()
      this.pieCanvas.moveTo(cx, cy)
      this.pieCanvas.arc(cx, cy, radius, angle, next)
      this.pieCanvas.closePath()
      this.pieCanvas.fillStyle = this.monochromeTone(index)
      this.pieCanvas.fill()
      angle = next
    })
    this.pieCanvas.beginPath()
    this.pieCanvas.arc(cx, cy, radius * 0.58, 0, Math.PI * 2)
    this.pieCanvas.fillStyle = UiTheme.surface
    this.pieCanvas.fill()
    this.pieCanvas.fillStyle = UiTheme.text
    this.pieCanvas.font = 'bold 20px HarmonyOS Sans'
    this.pieCanvas.textAlign = 'center'
    this.pieCanvas.fillText(`${total}`, cx, cy + 2)
    this.pieCanvas.fillStyle = UiTheme.muted
    this.pieCanvas.font = '9px HarmonyOS Sans'
    this.pieCanvas.fillText('累计打卡', cx, cy + 18)
  }

  private drawCharts(): void {
    setTimeout(() => {
      this.drawDailyChart()
      this.drawWeeklyChart()
      this.drawPie()
    }, 30)
  }

  @Styles
  cardSurface() {
    .backgroundColor(UiTheme.surface)
    .border({ width: 1, color: UiTheme.softBorder })
    .borderRadius(14)
    .shadow({ radius: 7, color: UiTheme.cardShadow, offsetY: 2 })
  }

  @Styles
  buttonFeedback() {
    .borderRadius(8)
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.78) } })
    .animation({ duration: UiMotion.duration(UiMotion.press), curve: UiMotion.enterCurve })
  }

  @Builder
  HeaderContent() {
    Row({ space: 10 * this.fontScale }) {
      Column({ space: 4 * this.fontScale }) {
        Text('自律魔方').fontSize((this.compact ? 21 : 24) * this.fontScale)
          .fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
        Text('专注记录与每日趋势').fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(this.guardActive ? '设备锁生效' : '本地专注')
        .fontSize(9 * this.fontScale).fontColor(this.guardActive ? UiTheme.onAccent : UiTheme.accentStrong)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.guardActive ? UiTheme.accent : UiTheme.accentPale)
        .border({ width: 1, color: UiTheme.accentBorder }).borderRadius(8)
      if (this.showClose) {
        Button('关闭').height(32 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
          .buttonFeedback().onClick(() => this.onClose())
      }
    }.width('100%').alignItems(VerticalAlign.Center)
  }

  @Builder
  CategorySelector() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text('自律类别').fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
        .margin({ right: 7 * this.fontScale, bottom: 6 * this.fontScale })
      Row({ space: 6 * this.fontScale }) {
        Row().width(8 * this.fontScale).height(8 * this.fontScale).borderRadius(4)
          .backgroundColor(this.categoryTone(this.selectedCategory()?.id || ''))
        Text(this.selectedCategory()?.name || '选择类别').fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Stack() {
          Image($r('app.media.ic_chevron_right'))
            .width(11 * this.fontScale).height(11 * this.fontScale)
            .rotate({ angle: 90 }).attributeModifier(UiTheme.glyph(UiTheme.iconIvory))
        }.width(18 * this.fontScale).height(18 * this.fontScale)
          .backgroundColor(UiTheme.accentStrong).borderRadius(5)
      }.height(32 * this.fontScale).padding({ left: 10, right: 9 })
        .margin({ right: 7 * this.fontScale, bottom: 6 * this.fontScale })
        .backgroundColor(UiTheme.accentPale).border({ width: 1, color: UiTheme.accentBorder }).borderRadius(8)
        .bindMenu(this.categoryMenu())
      Button('新增类别').height(32 * this.fontScale).fontSize(9 * this.fontScale)
        .backgroundColor(UiTheme.surface).fontColor(UiTheme.accentStrong)
        .border({ width: 1, color: UiTheme.accentBorder }).buttonFeedback()
        .onClick(() => this.categoryEditorVisible = !this.categoryEditorVisible)
    }.width('100%')
  }

  @Builder
  CategoryEditor() {
    if (this.categoryEditorVisible) {
      Row({ space: 7 * this.fontScale }) {
        TextInput({ text: this.newCategoryName, placeholder: '例如：阅读、早起、运动' })
          .layoutWeight(1).height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.accentBorder }).borderRadius(8)
          .onChange((value: string) => this.newCategoryName = value)
          .onSubmit(() => this.addCategory())
        Button('添加').height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.accent).fontColor(UiTheme.onAccent).buttonFeedback()
          .enabled(this.newCategoryName.trim().length > 0).onClick(() => this.addCategory())
      }.width('100%').padding(9 * this.fontScale).backgroundColor(UiTheme.accentPale)
        .border({ width: 1, color: UiTheme.accentBorder }).borderRadius(10)
    }
  }

  @Builder
  CategoryChips() {
    GridRow({ columns: 3, gutter: { x: 6 * this.fontScale, y: 6 * this.fontScale } }) {
      ForEach(this.analytics.categories, (category: FocusCategory) => {
        GridCol({ span: 1 }) {
          Row({ space: 3 * this.fontScale }) {
            Row().width(7 * this.fontScale).height(7 * this.fontScale).borderRadius(4)
              .backgroundColor(this.categoryTone(category.id))
            Text(category.name).fontSize(9 * this.fontScale)
              .fontColor(this.selectedCategoryId === category.id ? UiTheme.onAccent : UiTheme.secondary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            if (category.id === this.selectedCategoryId) {
              Image($r('app.media.ic_more_horizontal'))
                .width(12 * this.fontScale).height(12 * this.fontScale)
                .attributeModifier(UiTheme.glyph(UiTheme.iconOnAccent))
                .bindMenu([{ value: '删除此类别', action: () => this.deleteCategory(category) }])
            }
          }.width('100%').height(30 * this.fontScale).padding({ left: 8, right: 7 })
            .backgroundColor(this.selectedCategoryId === category.id ? UiTheme.accent : UiTheme.accentPale)
            .border({ width: 1, color: this.selectedCategoryId === category.id ? UiTheme.accent : UiTheme.accentBorder })
            .borderRadius(8).onClick(() => this.selectedCategoryId = category.id)
        }
      }, (category: FocusCategory) => category.id)
    }.width('100%')
  }

  @Builder
  TimerCard() {
    Column({ space: 9 * this.fontScale }) {
      Stack() {
        Progress({ value: FocusWorkspaceController.progress(), total: 100, type: ProgressType.Ring })
          .width((this.compact ? 132 : 148) * this.fontScale)
          .height((this.compact ? 132 : 148) * this.fontScale)
          .color(UiTheme.accent).style({ strokeWidth: 9 * this.fontScale })
        Column({ space: 2 * this.fontScale }) {
          Text(FocusWorkspaceController.formatTime(this.remainingSeconds))
            .fontSize((this.compact ? 29 : 34) * this.fontScale)
            .fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text(this.phase === 'focus' ? '专注中' : '休息中')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
        }
      }.width('100%').height((this.compact ? 140 : 156) * this.fontScale)
      Row({ space: 8 * this.fontScale }) {
        Button('− 5').height(32 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
          .enabled(!this.running).buttonFeedback().onClick(() => FocusWorkspaceController.adjustWorkMinutes(-5))
        Text(`${this.workMinutes} 分钟`).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
        Button('+ 5').height(32 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
          .enabled(!this.running).buttonFeedback().onClick(() => FocusWorkspaceController.adjustWorkMinutes(5))
      }
      Row({ space: 8 * this.fontScale }) {
        Button(this.sessionBusy ? '处理中' : (this.running ? '暂停专注' : '开始专注'))
          .layoutWeight(1).height(38 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.onAccent).backgroundColor(UiTheme.accent)
          .enabled(!this.guardBusy && !this.sessionBusy).buttonFeedback()
          .onClick(() => FocusWorkspaceController.toggleSession(this.context()))
        Button('重置').height(38 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
          .enabled(!this.guardBusy && !this.sessionBusy).buttonFeedback()
          .onClick(() => FocusWorkspaceController.reset())
      }.width('100%')
      Text(`已完成 ${this.completed} 个番茄`).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
    }.width('100%').padding(14 * this.fontScale).alignItems(HorizontalAlign.Center).cardSurface()
  }

  @Builder
  CheckInCard() {
    Column({ space: 9 * this.fontScale }) {
      Row() {
        Column({ space: 3 * this.fontScale }) {
          Text('今日打卡').fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('专注结束后自动记录，也可以手动补记').fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(`${this.todayCount()}`).fontSize(26 * this.fontScale)
          .fontWeight(FontWeight.Medium).fontColor(UiTheme.accentStrong)
      }.width('100%')
      this.CategorySelector()
      this.CategoryChips()
      Button(`打卡 · ${this.selectedCategory()?.name || '未选择'} · ${this.workMinutes} 分钟`)
        .width('100%').height(37 * this.fontScale).fontSize(10 * this.fontScale)
        .backgroundColor(UiTheme.accent).fontColor(UiTheme.onAccent).buttonFeedback()
        .enabled(this.analytics.categories.length > 0).onClick(() => this.addManualCheckIn())
      if (this.notice) {
        Text(this.notice).fontSize(9 * this.fontScale).fontColor(UiTheme.secondary)
          .lineHeight(15 * this.fontScale).width('100%')
      }
    }.width('100%').padding(14 * this.fontScale).alignItems(HorizontalAlign.Start)
  }

  @Builder
  ChartHeader(title: string, detail: string, badge: string) {
    Row({ space: 8 * this.fontScale }) {
      Column({ space: 3 * this.fontScale }) {
        Text(title).fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          .width('100%')
        Text(detail).fontSize(9 * this.fontScale).fontColor(UiTheme.muted).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(badge).fontSize(8 * this.fontScale).fontColor(UiTheme.accentStrong)
        .padding({ left: 7, right: 7, top: 4, bottom: 4 })
        .backgroundColor(UiTheme.accentPale).border({ width: 1, color: UiTheme.accentBorder }).borderRadius(6)
    }.width('100%').height(44 * this.fontScale)
  }

  @Builder
  DailyChartCard() {
    Column() {
      this.ChartHeader('每日打卡', '最近 14 天完成次数', '柱状图')
      Canvas(this.dailyCanvas).width('100%').height(this.chartCanvasHeight())
        .onReady(() => this.drawDailyChart())
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          const width = parseFloat(String(newValue.width))
          if (Number.isFinite(width) && width > 0 && Math.abs(this.dailyWidth - width) > 1) {
            this.dailyWidth = width
            this.drawDailyChart()
          }
        })
    }.width('100%').constraintSize({ minHeight: this.chartCardHeight() })
      .padding(15 * this.fontScale).alignItems(HorizontalAlign.Start).cardSurface()
  }

  @Builder
  WeeklyChartCard() {
    Column() {
      this.ChartHeader('本周趋势', '本周一至周日打卡变化', '折线图')
      Canvas(this.weeklyCanvas).width('100%').height(this.chartCanvasHeight())
        .onReady(() => this.drawWeeklyChart())
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          const width = parseFloat(String(newValue.width))
          if (Number.isFinite(width) && width > 0 && Math.abs(this.weeklyWidth - width) > 1) {
            this.weeklyWidth = width
            this.drawWeeklyChart()
          }
        })
    }.width('100%').constraintSize({ minHeight: this.chartCardHeight() })
      .padding(15 * this.fontScale).alignItems(HorizontalAlign.Start).cardSurface()
  }

  @Builder
  HeatmapCard() {
    Column({ space: 10 * this.fontScale }) {
      this.ChartHeader('本月完成度', `${this.monthLabel()} · 颜色越深打卡越多`, '月历')
      GridRow({ columns: 7, gutter: 4 * this.fontScale }) {
        ForEach(['一', '二', '三', '四', '五', '六', '日'], (label: string) => {
          GridCol({ span: 1 }) {
            Text(label).fontSize(8 * this.fontScale).fontColor(UiTheme.muted)
              .textAlign(TextAlign.Center).width('100%')
          }
        }, (label: string) => `weekday-${label}`)
      }.width('100%')
      GridRow({ columns: 7, gutter: 4 * this.fontScale }) {
        ForEach(this.monthCells(), (cell: FocusHeatCell) => {
          GridCol({ span: 1 }) {
            Stack() {
              Column().width('100%').aspectRatio(1)
                .backgroundColor(this.heatColor(cell.level, cell.inMonth))
                .border({ width: cell.today ? 2 : 0,
                  color: cell.today ? UiTheme.accent : Color.Transparent })
                .borderRadius(6)
              Text(`${cell.day}`).fontSize(9 * this.fontScale)
                .fontColor(cell.level >= 3 ? Color.White :
                  (cell.inMonth ? UiTheme.text : UiTheme.muted))
                .opacity(cell.inMonth ? 1 : 0.55)
            }.width('100%')
          }
        }, (cell: FocusHeatCell) => cell.key)
      }.width('100%')
      Row({ space: 6 * this.fontScale }) {
        Text('少').fontSize(8 * this.fontScale).fontColor(UiTheme.muted)
        ForEach([0, 1, 2, 3, 4], (level: number) => {
          Row().width(11 * this.fontScale).height(11 * this.fontScale)
            .backgroundColor(this.heatColor(level, true)).borderRadius(3)
        }, (level: number) => `legend-${level}`)
        Text('多').fontSize(8 * this.fontScale).fontColor(UiTheme.muted)
        Blank()
        Text(`本月 ${this.monthCheckInCount()} 次打卡`)
          .fontSize(8 * this.fontScale).fontColor(UiTheme.accentStrong)
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: this.heatmapCardHeight() })
      .padding(15 * this.fontScale).alignItems(HorizontalAlign.Start).cardSurface()
  }

  @Builder
  PieChartCard() {
    Column() {
      this.ChartHeader('类别占比', '按打卡次数统计不同自律类别', `${this.categoryShares().length} 类`)
      Canvas(this.pieCanvas).width('100%').height(this.chartCanvasHeight())
        .onReady(() => this.drawPie())
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          const width = parseFloat(String(newValue.width))
          const height = parseFloat(String(newValue.height))
          if (Number.isFinite(width) && width > 0) this.pieWidth = width
          if (Number.isFinite(height) && height > 0) this.pieHeight = height
          this.drawPie()
        })
    }.width('100%').constraintSize({ minHeight: this.chartCardHeight() })
      .padding(15 * this.fontScale).alignItems(HorizontalAlign.Start).cardSurface()
  }

  @Builder
  GuardCard() {
    Column({ space: 8 * this.fontScale }) {
      Row() {
        Column({ space: 2 * this.fontScale }) {
          Text('设备专注锁').fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('按白名单限制其他应用').fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.guardEnabled })
          .enabled(!this.guardBusy)
          .onChange((value: boolean) => FocusWorkspaceController.setGuardEnabled(value))
      }.width('100%').alignItems(VerticalAlign.Center)
      Flex({ wrap: FlexWrap.Wrap }) {
        Button(this.whitelistTokens.length === 0 ? '选择 APP 白名单' : `白名单 ${this.whitelistTokens.length} 个`)
          .height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).backgroundColor(UiTheme.raised).enabled(!this.guardBusy)
          .buttonFeedback().margin({ right: 7 * this.fontScale, bottom: 7 * this.fontScale })
          .onClick(() => FocusWorkspaceController.pickWhitelist(this.context()))
        Button('查询状态').height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).backgroundColor(UiTheme.raised).enabled(!this.guardBusy)
          .buttonFeedback().margin({ right: 7 * this.fontScale, bottom: 7 * this.fontScale })
          .onClick(() => FocusWorkspaceController.queryGuard())
        Button(this.guardActive ? '重新开启' : '立即开启')
          .height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.onAccent).backgroundColor(UiTheme.accent).enabled(!this.guardBusy)
          .buttonFeedback().margin({ right: 7 * this.fontScale, bottom: 7 * this.fontScale })
          .onClick(() => FocusWorkspaceController.enableGuard(this.context()))
        Button('解除').height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
          .enabled(!this.guardBusy && this.guardActive).buttonFeedback()
          .margin({ right: 7 * this.fontScale, bottom: 7 * this.fontScale })
          .onClick(() => FocusWorkspaceController.disableGuard())
      }.width('100%')
      Text(this.guardNotice || '白名单内应用可继续使用。')
        .fontSize(9 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(15 * this.fontScale)
        .width('100%').padding(8 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
    }.width('100%').padding(12 * this.fontScale).alignItems(HorizontalAlign.Start).cardSurface()
  }

  @Builder
  HardwareCard() {
    Column({ space: 8 * this.fontScale }) {
      Column({ space: 2 * this.fontScale }) {
        Text('自律魔方硬件').fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
        Text('连接 CampusCube，或用 NFC 触发专注').fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
      }.width('100%').alignItems(HorizontalAlign.Start)
      Flex({ wrap: FlexWrap.Wrap }) {
        Button('扫描魔方').height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).backgroundColor(UiTheme.raised).enabled(!this.hardwareBusy)
          .buttonFeedback().margin({ right: 7 * this.fontScale, bottom: 7 * this.fontScale })
          .onClick(() => FocusWorkspaceController.hardwareAction('connect', this.context()))
        Button('NFC 碰一碰').height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).backgroundColor(UiTheme.raised).enabled(!this.hardwareBusy)
          .buttonFeedback().margin({ right: 7 * this.fontScale, bottom: 7 * this.fontScale })
          .onClick(() => FocusWorkspaceController.hardwareAction('nfc', this.context()))
        Button('硬件状态').height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).backgroundColor(UiTheme.raised).enabled(!this.hardwareBusy)
          .buttonFeedback().margin({ right: 7 * this.fontScale, bottom: 7 * this.fontScale })
          .onClick(() => FocusWorkspaceController.hardwareAction('hardware-status', this.context()))
        Button('模拟姿态中断').height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.text).backgroundColor(UiTheme.raised).enabled(!this.hardwareBusy)
          .buttonFeedback().margin({ right: 7 * this.fontScale, bottom: 7 * this.fontScale })
          .onClick(() => FocusWorkspaceController.hardwareAction('interrupt', this.context()))
      }.width('100%')
      if (this.moduleNotice.length > 0) {
        Text(this.moduleNotice).fontSize(9 * this.fontScale).fontColor(UiTheme.secondary)
          .lineHeight(15 * this.fontScale).width('100%').padding(8 * this.fontScale)
          .backgroundColor(UiTheme.raised).borderRadius(8)
      }
      ForEach(this.moduleItems, (item: ModuleItem) => {
        Column({ space: 2 * this.fontScale }) {
          Text(item.title).fontSize(10 * this.fontScale).fontColor(UiTheme.text).width('100%')
          Text(item.detail).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
            .lineHeight(15 * this.fontScale).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (item: ModuleItem) => item.id)
    }.width('100%').padding(12 * this.fontScale).alignItems(HorizontalAlign.Start).cardSurface()
  }

  private columnGap(): number { return 12 * this.fontScale }

  private leftFillerHeight(): number {
    return Math.max(0, Math.round(this.rightColumnContentHeight -
      this.leftColumnContentHeight - this.columnGap()))
  }

  private rightFillerHeight(): number {
    return Math.max(0, Math.round(this.leftColumnContentHeight -
      this.rightColumnContentHeight - this.columnGap()))
  }

  @Builder
  MiniStat(value: string, label: string) {
    Column({ space: 3 * this.fontScale }) {
      Text(value).fontSize(18 * this.fontScale).fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.accentStrong)
      Text(label).fontSize(8 * this.fontScale).fontColor(UiTheme.muted)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  FocusFillerCard(height: number) {
    Column({ space: 10 * this.fontScale }) {
      Row({ space: 8 * this.fontScale }) {
        this.MiniStat(`${this.todayCount()}`, '今日打卡')
        this.MiniStat(`${this.weekCheckInCount()}`, '本周打卡')
        this.MiniStat(`${this.monthCheckInCount()}`, '本月打卡')
      }.width('100%')
      Stack({ alignContent: Alignment.BottomStart }) {
        Column().width('100%').height('100%')
          .linearGradient({ angle: 160,
            colors: [[UiTheme.accentPale, 0], [UiTheme.chartPale, 0.62], [UiTheme.chartLight, 1]] })
        Text('自律给我自由 · 每一次专注都算数')
          .fontSize(10 * this.fontScale).fontColor(UiTheme.accentStrong)
          .padding({ left: 12 * this.fontScale, right: 12 * this.fontScale,
            bottom: 10 * this.fontScale, top: 10 * this.fontScale })
          .width('100%')
      }.layoutWeight(1).width('100%').borderRadius(10)
        .clip(true)
    }.width('100%').height(height).constraintSize({ minHeight: 96 * this.fontScale })
      .padding(14 * this.fontScale).alignItems(HorizontalAlign.Start).cardSurface()
  }

  @Builder
  ChartWaterfall() {
    Row({ space: 14 * this.fontScale }) {
      Column({ space: this.columnGap() }) {
        Column({ space: this.columnGap() }) {
          this.DailyChartCard()
          this.HeatmapCard()
          this.GuardCard()
        }.width('100%')
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            const height = parseFloat(String(newValue.height))
            if (Number.isFinite(height) && height > 0) this.leftColumnContentHeight = height
          })
        if (this.leftFillerHeight() > 0) {
          this.FocusFillerCard(this.leftFillerHeight())
        }
      }.layoutWeight(1)
      Column({ space: this.columnGap() }) {
        Column({ space: this.columnGap() }) {
          this.WeeklyChartCard()
          this.PieChartCard()
          this.HardwareCard()
        }.width('100%')
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            const height = parseFloat(String(newValue.height))
            if (Number.isFinite(height) && height > 0) this.rightColumnContentHeight = height
          })
        if (this.rightFillerHeight() > 0) {
          this.FocusFillerCard(this.rightFillerHeight())
        }
      }.layoutWeight(1)
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  @Builder
  FocusDashboard() {
    Scroll() {
      Column({ space: 12 * this.fontScale }) {
        this.HeaderContent()
        if (this.isWide()) {
          GridRow({ columns: 12, gutter: 12 * this.fontScale }) {
            GridCol({ span: 5 }) { this.TimerCard() }
            GridCol({ span: 7 }) { this.CheckInCard() }
          }.width('100%').alignItems(ItemAlign.Stretch)
          this.CategoryEditor()
          this.ChartWaterfall()
        } else {
          this.TimerCard()
          this.CheckInCard()
          this.CategoryEditor()
          this.DailyChartCard()
          this.WeeklyChartCard()
          this.HeatmapCard()
          this.PieChartCard()
          this.GuardCard()
          this.HardwareCard()
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: (this.compact ? 14 : 20) * this.fontScale,
          right: (this.compact ? 14 : 20) * this.fontScale,
          top: 14 * this.fontScale, bottom: 20 * this.fontScale })
    }.width('100%').height('100%').scrollBar(BarState.On).align(Alignment.TopStart)
      .scrollBarWidth(6).scrollBarColor(UiTheme.secondary).backgroundColor(UiTheme.background)
  }

  build() {
    this.FocusDashboard()
  }
}
