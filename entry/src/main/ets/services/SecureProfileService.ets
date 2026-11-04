import { common } from '@kit.AbilityKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { preferences } from '@kit.ArkData'
import { util } from '@kit.ArkTS'
import { huks } from '@kit.UniversalKeystoreKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { EncryptedEnvelope, SecureProfileResult, StudentProfile } from '../models/ProfileModels'

export class SecureProfileService {
  private static readonly LOG_DOMAIN: number = 0xD009
  private static readonly LOG_TAG: string = 'SecureProfile'
  private static readonly STORE_NAME: string = 'campus_pilot_private'
  private static readonly PROFILE_KEY: string = 'student_profile_v1'
  private static readonly CONSENT_KEY: string = 'upload_consent_v1'
  private static readonly KEY_ALIAS: string = 'campus_pilot_profile_aes_v1'
  private static readonly AAD: string = 'CampusPilot.StudentProfile.v1'
  private store: preferences.Preferences | undefined = undefined

  async saveProfile(context: common.UIAbilityContext, profile: StudentProfile): Promise<SecureProfileResult> {
    try {
      const store = await this.openStore(context)
      await this.ensureKey()
      const plain = new util.TextEncoder('utf-8').encodeInto(JSON.stringify(profile))
      const nonce = cryptoFramework.createRandom().generateRandomSync(12).data
      const cipher = await this.crypt(true, plain, nonce)
      const envelope: EncryptedEnvelope = {
        version: 1,
        nonce: new util.Base64Helper().encodeToStringSync(nonce),
        cipherText: new util.Base64Helper().encodeToStringSync(cipher)
      }
      await store.put(SecureProfileService.PROFILE_KEY, JSON.stringify(envelope))
      await store.flush()
      return { ok: true, message: '档案已使用 HUKS 密钥加密并保存到本机。' }
    } catch (error) {
      this.logError('save encrypted profile failed', error)
      return { ok: false, message: '档案保存失败，请检查设备密钥服务与存储空间。' }
    }
  }

  async loadProfile(context: common.UIAbilityContext): Promise<SecureProfileResult> {
    try {
      const store = await this.openStore(context)
      const raw = String(await store.get(SecureProfileService.PROFILE_KEY, ''))
      if (raw.length === 0) return { ok: false, message: '本机尚未保存加密档案。' }
      const envelope = JSON.parse(raw) as EncryptedEnvelope
      if (envelope.version !== 1 || envelope.nonce.length === 0 || envelope.cipherText.length === 0) {
        return { ok: false, message: '档案密文格式无效，请重新保存。' }
      }
      const helper = new util.Base64Helper()
      const nonce = helper.decodeSync(envelope.nonce)
      const cipher = helper.decodeSync(envelope.cipherText)
      await this.ensureKey()
      const plain = await this.crypt(false, cipher, nonce)
      const json = util.TextDecoder.create('utf-8').decodeToString(plain)
      return { ok: true, message: '已从本机解密并读取档案。', profile: JSON.parse(json) as StudentProfile }
    } catch (error) {
      this.logError('load encrypted profile failed', error)
      return { ok: false, message: '档案解密失败。密钥可能已随卸载重置，请重新保存档案。' }
    }
  }

  async clearProfile(context: common.UIAbilityContext): Promise<void> {
    const store = await this.openStore(context)
    await store.delete(SecureProfileService.PROFILE_KEY)
    await store.flush()
  }

  async setUploadConsent(context: common.UIAbilityContext, granted: boolean): Promise<void> {
    const store = await this.openStore(context)
    await store.put(SecureProfileService.CONSENT_KEY, granted)
    await store.flush()
  }

  async hasUploadConsent(context: common.UIAbilityContext): Promise<boolean> {
    const store = await this.openStore(context)
    return Boolean(await store.get(SecureProfileService.CONSENT_KEY, false))
  }

  private async openStore(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    if (this.store === undefined) this.store = await preferences.getPreferences(context, SecureProfileService.STORE_NAME)
    return this.store
  }

  private async ensureKey(): Promise<void> {
    const empty: huks.HuksOptions = { properties: [] }
    let exists = false
    try {
      exists = await huks.isKeyItemExist(SecureProfileService.KEY_ALIAS, empty)
    } catch (error) {
      // HarmonyOS returns 12000011 when the key has not been generated yet.
      const business = error as BusinessError
      if (business.code !== 12000011) throw new Error(`${business.code}: ${business.message}`)
    }
    if (exists) return
    const properties: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT }
    ]
    await huks.generateKeyItem(SecureProfileService.KEY_ALIAS, { properties: properties })
  }

  private async crypt(encrypt: boolean, data: Uint8Array, nonce: Uint8Array): Promise<Uint8Array> {
    const properties: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: encrypt ? huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT : huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
      { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: new util.TextEncoder('utf-8').encodeInto(SecureProfileService.AAD) }
    ]
    let inData = data
    if (!encrypt) {
      if (data.length <= 16) throw new Error('cipher text is too short')
      properties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: data.slice(data.length - 16) })
      inData = data.slice(0, data.length - 16)
    }
    const options: huks.HuksOptions = { properties: properties, inData: inData }
    const session = await huks.initSession(SecureProfileService.KEY_ALIAS, options)
    const result = await huks.finishSession(session.handle, options)
    if (result.outData === undefined) throw new Error('HUKS returned empty data')
    return result.outData
  }

  private logError(message: string, error: Object): void {
    const business = error as BusinessError
    const detail = business.code === undefined ? JSON.stringify(error) : `${business.code}: ${business.message}`
    hilog.error(SecureProfileService.LOG_DOMAIN, SecureProfileService.LOG_TAG, `${message}: ${detail}`)
  }

}


