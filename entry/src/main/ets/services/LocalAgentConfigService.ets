import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { AgentApiSettings } from '../config/ApiConfig'

export class LocalAgentConfigService {
  static async load(context: common.UIAbilityContext): Promise<AgentApiSettings | undefined> {
    try {
      const rawFile: Uint8Array = await context.resourceManager.getRawFileContent('local_api.json')
      const text = util.TextDecoder.create().decodeToString(rawFile)
      const settings = JSON.parse(text) as AgentApiSettings
      if (typeof settings.baseUrl !== 'string' || typeof settings.model !== 'string' || typeof settings.apiKey !== 'string') {
        return undefined
      }
      if (settings.baseUrl.trim().length === 0 || settings.model.trim().length === 0) return undefined
      return settings
    } catch (error) {
      return undefined
    }
  }
}
