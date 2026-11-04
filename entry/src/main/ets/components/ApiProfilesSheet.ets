import { common } from '@kit.AbilityKit'
import { AgentProfileArchive, AgentProfileSummary } from '../config/ApiConfig'
import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'
import { LocalAgentConfigService } from '../services/LocalAgentConfigService'
import { ApiProfileList } from './ApiProfileList'

@Component
export struct ApiProfilesSheet {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  onChanged: () => void = () => {}
  onClose: () => void = () => {}
  @State profiles: AgentProfileSummary[] = []
  @State activeId: string = ''
  @State selectedId: string = ''
  @State name: string = ''
  @State baseUrl: string = ''
  @State model: string = ''
  @State apiKey: string = ''
  @State provider: string = ''
  @State notice: string = ''
  @State readFailed: boolean = false

  private context(): common.Context { return this.getUIContext().getHostContext() as common.Context }
  aboutToAppear(): void { this.refresh() }

  private refresh(preferred: string = ''): void {
    try {
      const archive = LocalAgentConfigService.readProfiles(this.context()) || LocalAgentConfigService.empty()
      this.profiles = LocalAgentConfigService.summaries(archive)
      this.activeId = archive.activeId
      this.readFailed = false
      const id = preferred || archive.activeId || archive.items[0]?.id || ''
      if (id) this.edit(id)
      else this.add()
    } catch (_error) { this.readFailed = true; this.notice = '模型配置读取失败，原配置已保留，请重新打开后重试。' }
  }

  private edit(id: string): void {
    try {
      const profile = LocalAgentConfigService.readProfiles(this.context())?.items.find((item) => item.id === id)
      if (!profile) { this.notice = '该配置已被删除，请重新打开后重试。'; return }
      this.selectedId = profile.id; this.name = profile.name; this.baseUrl = profile.baseUrl
      this.model = profile.model; this.apiKey = profile.apiKey; this.provider = profile.provider || ''; this.notice = ''
    } catch (_error) { this.notice = '模型配置读取失败，原配置已保留。' }
  }

  private add(): void {
    this.selectedId = ''; this.name = ''; this.baseUrl = ''; this.model = ''; this.apiKey = ''; this.provider = ''; this.notice = ''
  }

  private duplicate(): void {
    this.selectedId = ''
    this.name = `${this.name || this.model} 副本`.slice(0, 60)
    this.notice = '已创建副本草稿，修改模型后保存即可；当前使用的配置保持不变。'
  }

  private save(activate: boolean): void {
    try {
      const archive = LocalAgentConfigService.save(this.context(), this.selectedId, this.name,
        { baseUrl: this.baseUrl, model: this.model, apiKey: this.apiKey }, activate, this.provider)
      const id = this.selectedId || archive.items[archive.items.length - 1].id
      this.refresh(id)
      this.onChanged()
      this.notice = activate ? '已保存并使用此模型。' : '已保存配置。'
      if (activate) this.onClose()
    } catch (error) { this.notice = (error as Error).message || '保存失败，请重试。' }
  }

  private async remove(): Promise<void> {
    const id = this.selectedId
    if (!id) return
    try {
      const fallback = this.profiles.find((profile: AgentProfileSummary) => profile.id !== id)
      const effect = this.activeId === id ? (fallback ? `删除后将切换到“${fallback.name}”。` : '删除后将停止使用模型。') : '当前使用的模型保持不变。'
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '删除模型配置',
        message: `删除“${this.name}”？${effect}其他配置和历史对话会保留。`, buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: '#666666' }] })
      if (result.index !== 1) return
      const archive: AgentProfileArchive = LocalAgentConfigService.remove(this.context(), id)
      this.refresh(archive.activeId)
      this.onChanged()
      this.notice = archive.items.length ? '已删除配置。' : '已删除全部配置，可添加新的模型。'
    } catch (error) { this.notice = (error as Error).message || '删除失败，请重试。' }
  }

  @Styles
  action() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.65) } })
    .animation({ duration: UiMotion.press, curve: UiMotion.enterCurve })
  }

  build() {
    Column({ space: 12 * this.fontScale }) {
      Row({ space: 8 * this.fontScale }) {
        Column({ space: 3 * this.fontScale }) {
          Text('模型 API').fontSize(21 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).id('api-settings-title')
          Text('保存多组配置，兼容 OpenAI Chat Completions 与 Anthropic Messages').fontSize(11 * this.fontScale).fontColor(UiTheme.muted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('关闭').action().height(36 * this.fontScale).fontSize(12 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
          .id('api-settings-close').onClick(() => this.onClose())
      }.width('100%')
      Scroll() {
        Column({ space: 10 * this.fontScale }) {
          if (!this.readFailed) {
            Row() {
              Text(`已保存 ${this.profiles.length}/20`).fontSize(12 * this.fontScale).fontColor(UiTheme.secondary).layoutWeight(1)
              Button('＋ 新增').action().height(30 * this.fontScale).fontSize(11 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
                .id('api-profile-add').enabled(this.profiles.length < LocalAgentConfigService.maxProfiles).onClick(() => this.add())
            }.width('100%')
            if (this.profiles.length > 0) {
              ApiProfileList({ profiles: this.profiles, selectedId: this.selectedId, activeId: this.activeId,
                maxHeight: 144 * this.fontScale, onSelect: (id: string) => this.edit(id) })
            } else {
              Text('尚未添加模型配置，填写下方信息后保存。').id('api-profiles-empty')
                .fontSize(11 * this.fontScale).fontColor(UiTheme.muted).lineHeight(18 * this.fontScale).width('100%')
            }
            Row() {
              Text(this.selectedId ? '编辑配置' : '新建配置').fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).layoutWeight(1)
              if (this.selectedId) {
                Button('另存为新配置').action().height(28 * this.fontScale).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).backgroundColor(UiTheme.raised)
                  .id('api-profile-duplicate').enabled(this.profiles.length < LocalAgentConfigService.maxProfiles).onClick(() => this.duplicate())
              }
            }.width('100%').margin({ top: 5 * this.fontScale })
            Text('配置名称（可选）').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
            TextInput({ text: this.name, placeholder: '例如日常对话、课程助手' }).id('api-profile-name').maxLength(60)
              .fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale }).height(40 * this.fontScale).width('100%').backgroundColor(UiTheme.surface).borderRadius(8 * this.fontScale).onChange((value: string) => this.name = value)
            Text('服务商').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
            Row({ space: 6 * this.fontScale }) {
              ForEach(['', 'openai', 'anthropic'], (value: string) => {
                Text(value === '' ? '自动判断' : value === 'openai' ? 'OpenAI 兼容' : 'Anthropic')
                  .id(`api-provider-${value === '' ? 'auto' : value}`)
                  .textAlign(TextAlign.Center).fontSize(11 * this.fontScale).height(32 * this.fontScale)
                  .layoutWeight(1).borderRadius(8 * this.fontScale)
                  .backgroundColor(this.provider === value ? UiTheme.primary : UiTheme.raised)
                  .fontColor(this.provider === value ? UiTheme.onPrimary : UiTheme.secondary)
                  .hoverEffect(HoverEffect.Highlight)
                  .onClick(() => { this.provider = value })
              }, (value: string) => value)
            }.width('100%')
            Text('服务地址').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
            TextInput({ text: this.baseUrl, placeholder: '例如 https://api.example.com/v1' }).id('api-base-url').maxLength(2048)
              .fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale }).height(40 * this.fontScale).width('100%').backgroundColor(UiTheme.surface).borderRadius(8 * this.fontScale).onChange((value: string) => this.baseUrl = value)
            Text('模型名称').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
            TextInput({ text: this.model, placeholder: '例如 qwen-plus、deepseek-chat' }).id('api-model').maxLength(160)
              .fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale }).height(40 * this.fontScale).width('100%').backgroundColor(UiTheme.surface).borderRadius(8 * this.fontScale).onChange((value: string) => this.model = value)
            Text('API Key').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
            TextInput({ text: this.apiKey, placeholder: '无鉴权服务可留空' }).id('api-key').type(InputType.Password).maxLength(8192)
              .fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale }).height(40 * this.fontScale).width('100%').backgroundColor(UiTheme.surface).borderRadius(8 * this.fontScale).onChange((value: string) => this.apiKey = value)
            Text('配置只保存在本机；对话、已选资料和附件将发送到当前选中的服务。').fontSize(10 * this.fontScale).fontColor(UiTheme.muted).lineHeight(17 * this.fontScale)
          }
          if (this.notice) { Text(this.notice).id('api-profile-notice').fontSize(12 * this.fontScale).fontColor(UiTheme.secondary).width('100%').padding(9 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8 * this.fontScale) }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ right: 12 * this.fontScale, bottom: 8 * this.fontScale })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Auto)
        .scrollBarWidth(4).scrollBarColor('#777777')
      if (!this.readFailed) {
        Row({ space: 8 * this.fontScale }) {
          Button('保存并使用').action().layoutWeight(1).height(40 * this.fontScale).fontSize(13 * this.fontScale).backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary)
            .id('api-settings-save').onClick(() => this.save(true))
          Button('仅保存').action().height(40 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.primary)
            .id('api-profile-save-only').onClick(() => this.save(false))
          if (this.selectedId) {
            Button('删除').action().height(40 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.secondary)
              .id('api-profile-delete').onClick(() => this.remove())
          }
        }.width('100%')
      }
    }.width('100%').height('100%').padding(24 * this.fontScale).alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.background)
  }
}
