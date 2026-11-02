import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'
import { AgentTaskPage } from './AgentTaskPage'
import { SystemSchedulePanel } from './SystemSchedulePanel'

@Component
export struct TaskCenterPage {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop initialTab: string = 'agent'
  @State tab: string = 'agent'
  @State tabBarWidth: number = 360
  private readonly tabScroller: Scroller = new Scroller()
  aboutToAppear(): void { this.tab = this.initialTab }
  private selectTab(id: string, index: number): void {
    this.tab = id
    const tabWidth = 96 * this.fontScale
    const offset = Math.max(0, index * tabWidth - this.tabBarWidth / 2 + tabWidth / 2)
    this.tabScroller.scrollTo({
      xOffset: offset,
      yOffset: 0,
      animation: {
        duration: UiMotion.duration(UiMotion.fast),
        curve: UiMotion.moveCurve,
        canOverScroll: false
      }
    })
  }
  @Builder
  Tab(label: string, id: string, index: number) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 * this.fontScale }) {
        Text(label).fontSize(12 * this.fontScale)
          .fontColor(this.tab === id ? UiTheme.surface : UiTheme.text)
        Row().width(this.tab === id ? 18 * this.fontScale : 0)
          .height(2 * this.fontScale)
          .backgroundColor(this.tab === id ? UiTheme.surface : Color.Transparent)
          .borderRadius(1)
      }.height(34 * this.fontScale).justifyContent(FlexAlign.Center)
    }.width(92 * this.fontScale).height(38 * this.fontScale).borderRadius(7 * this.fontScale)
      .backgroundColor(this.tab === id ? UiTheme.primary : UiTheme.raised).fontColor(this.tab === id ? UiTheme.surface : UiTheme.text)
      .hoverEffect(HoverEffect.Highlight)
      .stateStyles({ normal: { .opacity(1).scale({ x: 1, y: 1 }) }, pressed: { .opacity(0.78).scale({ x: 0.98, y: 0.98 }) } })
      .animation({ duration: UiMotion.duration(UiMotion.press), curve: UiMotion.enterCurve })
      .id(`task-center-${id}`).onClick(() => this.selectTab(id, index))
  }
  build() {
    Column() {
      Column({ space: 12 * this.fontScale }) {
        Text('定时任务').fontSize(25 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
        Scroll(this.tabScroller) {
          Row({ space: 6 * this.fontScale }) {
            this.Tab('Agent任务', 'agent', 0)
            this.Tab('日历', 'calendar', 1)
            this.Tab('提醒', 'reminders', 2)
            this.Tab('备忘录', 'memos', 3)
          }.padding({ left: 1, right: 1 })
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring).nestedScroll({
            scrollForward: NestedScrollMode.SELF_FIRST,
            scrollBackward: NestedScrollMode.SELF_FIRST
          })
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            const width = parseFloat(String(newValue.width))
            if (Number.isFinite(width) && width > 0) this.tabBarWidth = width
          })
        Text(this.tab === 'agent' ? '这里是Agent到期执行的任务；已安排的日程和响铃提醒请在“日历 / 提醒”查看。'
          : this.tab === 'reminders' ? '同时显示本应用代理提醒与日历提醒，打开页面自动读取。' : this.tab === 'calendar' ? '显示系统授权范围内的日程，包含对话中创建的日历提醒。' : '本机保存的备忘录，可编辑并通过系统分享。')
          .fontSize(11 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
      }.width('100%').padding(22 * this.fontScale).border({ width: { bottom: 1 }, color: UiTheme.border })
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.tab === 'agent') { AgentTaskPage().width('100%').height('100%').transition(UiMotion.page()) }
        else {
          ForEach([this.tab], (tab: string) => { SystemSchedulePanel({ embedded: true, initialTab: tab })
            .width('100%').height('100%').transition(UiMotion.page()) }, (tab: string) => tab)
        }
      }.layoutWeight(1).width('100%').clip(true)
    }.width('100%').height('100%').backgroundColor(UiTheme.background).id('task-center-page')
  }
}
