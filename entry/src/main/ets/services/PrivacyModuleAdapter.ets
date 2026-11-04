import { common } from '@kit.AbilityKit'
import { ModuleAdapter, ModuleItem, ModuleResult } from '../models/IntegrationModels'
import { SecureProfileResult, StudentProfile } from '../models/ProfileModels'
import { SecureProfileService } from './SecureProfileService'

export class PrivacyModuleAdapter implements ModuleAdapter {
  private context: common.UIAbilityContext
  private service: SecureProfileService = new SecureProfileService()

  constructor(context: common.UIAbilityContext) {
    this.context = context
  }

  async execute(action: string, input: string): Promise<ModuleResult> {
    if (action === 'save-profile') return this.save(input)
    if (action === 'save-demo') return this.saveDemo()
    if (action === 'load-profile') return this.load()
    if (action === 'consent-on') return this.setConsent(true)
    if (action === 'consent-off') return this.setConsent(false)
    if (action === 'consent-status') return this.consentStatus()
    if (action === 'clear-profile') return this.clear()
    return { ok: false, message: '未知隐私操作。', items: [] }
  }

  private async save(input: string): Promise<ModuleResult> {
    const parts = input.split(',').map((part: string): string => part.trim())
    if (parts.length === 0 || parts[0].length === 0) {
      return { ok: false, message: '请输入：姓名,学号,手机号。至少填写姓名。', items: [] }
    }
    const profile: StudentProfile = {
      name: parts[0], studentId: parts.length > 1 ? parts[1] : '', college: '', className: '', dorm: '',
      phone: parts.length > 2 ? parts[2] : '', email: '', emergencyName: '', emergencyPhone: '', defaultReason: ''
    }
    const result = await this.service.saveProfile(this.context, profile)
    return this.fromResult(result)
  }

  private async saveDemo(): Promise<ModuleResult> {
    const profile: StudentProfile = {
      name: '演示学生', studentId: '20250001', college: '计算机学院', className: '软件工程 1 班',
      dorm: '1 号楼 101', phone: '13800138000', email: 'demo@example.com',
      emergencyName: '紧急联系人', emergencyPhone: '13900139000', defaultReason: '课程活动'
    }
    const result = await this.service.saveProfile(this.context, profile)
    return this.fromResult(result)
  }
  private async load(): Promise<ModuleResult> {
    const result = await this.service.loadProfile(this.context)
    if (!result.ok || result.profile === undefined) return this.fromResult(result)
    const profile = result.profile
    return {
      ok: true,
      message: result.message,
      items: [
        { id: 'profile-name', title: `姓名：${profile.name}`, detail: '档案通过 HUKS 托管密钥解密，仅在当前应用沙箱读取。' },
        { id: 'profile-id', title: `学号：${this.mask(profile.studentId)}`, detail: '界面默认脱敏展示，业务使用完整值时需再次确认。' },
        { id: 'profile-phone', title: `手机号：${this.mask(profile.phone)}`, detail: '仅在用户授权的表单预填和上传流程中使用。' }
      ]
    }
  }

  private async setConsent(granted: boolean): Promise<ModuleResult> {
    await this.service.setUploadConsent(this.context, granted)
    return { ok: true, message: granted ? '已允许在发起请求前展示敏感数据上传预览。' : '已撤回上传授权；后续敏感数据不会发送。',
      items: [{ id: 'privacy-consent', title: granted ? '上传授权：已允许' : '上传授权：已撤回',
        detail: '授权只代表允许预览确认流程，不绕过每次上传前的用户确认。' }] }
  }

  private async consentStatus(): Promise<ModuleResult> {
    const granted = await this.service.hasUploadConsent(this.context)
    return { ok: true, message: '已读取本机上传授权状态。',
      items: [{ id: 'privacy-consent', title: granted ? '上传授权：已允许' : '上传授权：未允许',
        detail: '档案默认保存在本地；API Key、学号和联系方式不会写入仓库。' }] }
  }

  private async clear(): Promise<ModuleResult> {
    await this.service.clearProfile(this.context)
    return { ok: true, message: '本机加密档案已清除，上传授权状态保留。', items: [] }
  }

  private fromResult(result: SecureProfileResult): ModuleResult {
    return { ok: result.ok, message: result.message, items: [] }
  }

  private mask(value: string): string {
    if (value.length <= 4) return value.length > 0 ? '****' : '未填写'
    return `${value.slice(0, 2)}****${value.slice(value.length - 2)}`
  }
}

