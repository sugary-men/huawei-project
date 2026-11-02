import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'
import { AgentTaskPage } from './AgentTaskPage'
import { SelectionTab } from './SelectionTab'
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
  build() {
    Column() {
      Column({ space: 12 * this.fontScale }) {
        Text('定时任务').fontSize(25 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
        Scroll(this.tabScroller) {
          Row({ space: 6 * this.fontScale }) {
            SelectionTab({ label: 'Agent任务', selected: this.tab === 'agent',
              itemId: 'task-center-agent', itemWidth: 92,
              onSelect: () => this.selectTab('agent', 0) })
            SelectionTab({ label: '日历', selected: this.tab === 'calendar',
              itemId: 'task-center-calendar', itemWidth: 92,
              onSelect: () => this.selectTab('calendar', 1) })
            SelectionTab({ label: '提醒', selected: this.tab === 'reminders',
              itemId: 'task-center-reminders', itemWidth: 92,
              onSelect: () => this.selectTab('reminders', 2) })
            SelectionTab({ label: '备忘录', selected: this.tab === 'memos',
              itemId: 'task-center-memos', itemWidth: 92,
              onSelect: () => this.selectTab('memos', 3) })
          }.padding(3 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
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
