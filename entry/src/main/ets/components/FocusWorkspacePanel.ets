import { common } from '@kit.AbilityKit'
import { UiTheme } from '../config/UiTheme'
import { ModuleItem } from '../models/IntegrationModels'
import { FocusWorkspaceController } from '../services/FocusWorkspaceController'

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
  @StorageLink('focusHardwareBusy') hardwareBusy: boolean = false
  @StorageLink('focusModuleNotice') moduleNotice: string = ''
  @StorageLink('focusModuleItems') moduleItems: ModuleItem[] = []
  @Prop compact: boolean = false
  @Prop showClose: boolean = false
  onClose: () => void = () => {}

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  build() {
    Scroll() {
      Column({ space: (this.compact ? 10 : 14) * this.fontScale }) {
        Row() {
          Column({ space: 4 * this.fontScale }) {
            Text('自律魔方').fontSize((this.compact ? 19 : 24) * this.fontScale)
              .fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            Text('番茄钟 + 健康使用设备专注锁').fontSize(11 * this.fontScale)
              .fontColor(UiTheme.muted)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text(this.guardActive ? '设备锁生效中' : '本地番茄钟')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.secondary)
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor(UiTheme.raised).borderRadius(7)
          if (this.showClose) {
            Button('关闭').height(30 * this.fontScale).fontSize(10 * this.fontScale)
              .backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
              .margin({ left: 6 }).onClick(() => this.onClose())
          }
        }.width('100%').alignItems(VerticalAlign.Center)

        Column({ space: 10 * this.fontScale }) {
          Progress({ value: FocusWorkspaceController.progress(), total: 100, type: ProgressType.Ring })
            .width((this.compact ? 160 : 210) * this.fontScale)
            .height((this.compact ? 160 : 210) * this.fontScale)
            .color(UiTheme.primary).style({ strokeWidth: 12 * this.fontScale })
          Text(FocusWorkspaceController.formatTime(this.remainingSeconds))
            .fontSize((this.compact ? 34 : 42) * this.fontScale)
            .fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text(this.phase === 'focus' ? '专注中' : '休息中')
            .fontSize(12 * this.fontScale).fontColor(UiTheme.secondary)
          Row({ space: 10 * this.fontScale }) {
            Button('− 5').height(36 * this.fontScale).fontSize(11 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
              .enabled(!this.running).onClick(() => FocusWorkspaceController.adjustWorkMinutes(-5))
            Text(`${this.workMinutes} / ${this.breakMinutes} 分钟`).fontSize(11 * this.fontScale)
              .fontColor(UiTheme.secondary)
            Button('+ 5').height(36 * this.fontScale).fontSize(11 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
              .enabled(!this.running).onClick(() => FocusWorkspaceController.adjustWorkMinutes(5))
          }
          Row({ space: 8 * this.fontScale }) {
            Button(this.running ? '暂停专注' : '开始专注')
              .layoutWeight(1).height(42 * this.fontScale).fontSize(12 * this.fontScale)
              .fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary)
              .enabled(!this.guardBusy)
              .onClick(() => FocusWorkspaceController.toggleSession(this.context()))
            Button('重置').height(42 * this.fontScale).fontSize(11 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
              .onClick(() => FocusWorkspaceController.reset())
          }.width('100%')
          Text(`已完成 ${this.completed} 个番茄`).fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
        }.width('100%').padding({ top: 14, bottom: 14 }).alignItems(HorizontalAlign.Center)
          .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.border }).borderRadius(10)

        Column({ space: 9 * this.fontScale }) {
          Row() {
            Column({ space: 3 * this.fontScale }) {
              Text('设备专注锁').fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium)
                .fontColor(UiTheme.text)
              Text('按白名单限制其他应用，数据与左栏页面同步。').fontSize(9 * this.fontScale)
                .fontColor(UiTheme.muted)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.guardEnabled })
              .onChange((value: boolean) => FocusWorkspaceController.setGuardEnabled(value))
          }.width('100%').alignItems(VerticalAlign.Center)
          Row({ space: 8 * this.fontScale }) {
            Button(this.whitelistTokens.length === 0 ? '选择 APP 白名单' : `白名单 ${this.whitelistTokens.length} 个`)
              .height(36 * this.fontScale).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
              .enabled(!this.guardBusy)
              .onClick(() => FocusWorkspaceController.pickWhitelist(this.context()))
            Button('查询状态').height(36 * this.fontScale).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
              .enabled(!this.guardBusy).onClick(() => FocusWorkspaceController.queryGuard())
          }.width('100%')
          Row({ space: 8 * this.fontScale }) {
            Button(this.guardActive ? '重新开启设备锁' : '立即开启设备锁')
              .height(36 * this.fontScale).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary)
              .enabled(!this.guardBusy)
              .onClick(() => FocusWorkspaceController.enableGuard(this.context()))
            Button('解除设备锁').height(36 * this.fontScale).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
              .enabled(!this.guardBusy && this.guardActive)
              .onClick(() => FocusWorkspaceController.disableGuard())
          }.width('100%')
          Text(this.guardNotice || '白名单内应用可继续使用，名单外应用在设定时长内被限制访问。')
            .fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(16 * this.fontScale)
            .width('100%').padding(9 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
        }.width('100%').padding(12 * this.fontScale).alignItems(HorizontalAlign.Start)
          .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.border }).borderRadius(10)

        Column({ space: 9 * this.fontScale }) {
          Column({ space: 3 * this.fontScale }) {
            Text('自律魔方硬件').fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.text)
            Text('连接 CampusCube，或用 NFC 标签触发专注').fontSize(9 * this.fontScale)
              .fontColor(UiTheme.muted)
          }.width('100%').alignItems(HorizontalAlign.Start)
          Row({ space: 8 * this.fontScale }) {
            Button('扫描魔方').layoutWeight(1).height(36 * this.fontScale).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
              .enabled(!this.hardwareBusy)
              .onClick(() => FocusWorkspaceController.hardwareAction('connect', this.context()))
            Button('NFC 碰一碰').layoutWeight(1).height(36 * this.fontScale).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
              .enabled(!this.hardwareBusy)
              .onClick(() => FocusWorkspaceController.hardwareAction('nfc', this.context()))
          }.width('100%')
          Row({ space: 8 * this.fontScale }) {
            Button('硬件状态').layoutWeight(1).height(36 * this.fontScale).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
              .enabled(!this.hardwareBusy)
              .onClick(() => FocusWorkspaceController.hardwareAction('hardware-status', this.context()))
            Button('模拟姿态中断').layoutWeight(1).height(36 * this.fontScale).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
              .enabled(!this.hardwareBusy)
              .onClick(() => FocusWorkspaceController.hardwareAction('interrupt', this.context()))
          }.width('100%')
          if (this.moduleNotice.length > 0) {
            Text(this.moduleNotice).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
              .lineHeight(16 * this.fontScale).width('100%').padding(9 * this.fontScale)
              .backgroundColor(UiTheme.raised).borderRadius(8)
          }
          ForEach(this.moduleItems, (item: ModuleItem) => {
            Column({ space: 3 * this.fontScale }) {
              Text(item.title).fontSize(10 * this.fontScale).fontColor(UiTheme.text).width('100%')
              Text(item.detail).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
                .lineHeight(15 * this.fontScale).width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start)
          }, (item: ModuleItem) => item.id)
        }.width('100%').padding(12 * this.fontScale).alignItems(HorizontalAlign.Start)
          .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.border }).borderRadius(10)
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: this.compact ? 14 : 22, right: this.compact ? 14 : 22, top: 16, bottom: 18 })
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
  }
}
