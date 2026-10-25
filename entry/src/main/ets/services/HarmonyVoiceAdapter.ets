import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { speechRecognizer, textToSpeech } from '@kit.CoreSpeechKit'
import { util } from '@kit.ArkTS'
import { VoiceAdapter, VoiceObserver } from '../models/IntegrationModels'

export class HarmonyVoiceAdapter implements VoiceAdapter {
  private context: common.UIAbilityContext
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined
  private speaker: textToSpeech.TextToSpeechEngine | undefined = undefined
  private observer: VoiceObserver | undefined = undefined
  private session: string = ''
  private text: string = ''
  private startResolve: (() => void) | undefined = undefined
  private startReject: ((error: Error) => void) | undefined = undefined
  private stopResolve: ((text: string) => void) | undefined = undefined
  private stopReject: ((error: Error) => void) | undefined = undefined
  private startTimer: number = -1
  private stopTimer: number = -1
  private speakResolve: (() => void) | undefined = undefined
  private speakReject: ((error: Error) => void) | undefined = undefined
  private generation: number = 0

  constructor(context: common.UIAbilityContext) { this.context = context }

  async start(observer?: VoiceObserver): Promise<void> {
    if (this.session) {
      try { this.engine?.cancel(this.session) } catch (_error) {}
      this.finish()
    }
    const generation = ++this.generation
    const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, ['ohos.permission.MICROPHONE'])
    if (generation !== this.generation) throw new Error('语音输入已取消。')
    if (permission.authResults[0] !== 0) throw new Error('麦克风权限未开启，请在系统设置中允许后重试。')
    try {
      if (this.engine === undefined) this.engine = await speechRecognizer.createEngine({ language: 'zh-CN', online: 1,
        extraParams: { locate: 'CN', recognizerMode: 'short' } })
    } catch (_error) { throw new Error('当前设备的中文语音识别引擎不可用，请在支持 Core Speech 的真机上使用。') }
    if (generation !== this.generation) throw new Error('语音输入已取消。')
    const id = util.generateRandomUUID()
    this.session = id
    this.text = ''
    this.observer = observer
    const started = new Promise<void>((resolve, reject) => { this.startResolve = resolve; this.startReject = reject })
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (sessionId: string, _event: string): void => {
        if (sessionId !== this.session) return
        clearTimeout(this.startTimer)
        this.startResolve?.()
        this.startResolve = undefined
        this.startReject = undefined
      },
      onEvent: (_sessionId: string, _code: number, _event: string): void => {},
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void => {
        if (sessionId !== this.session) return
        this.text = result.result.slice(0, 4000)
        this.observer?.onPartial(this.text)
        if (result.isLast) this.finish()
      },
      onComplete: (sessionId: string, _event: string): void => { if (sessionId === this.session) this.finish() },
      onError: (sessionId: string, code: number, _message: string): void => {
        if (sessionId !== this.session) return
        this.finish(code === 1002200012 ? '麦克风权限未开启。' : `语音识别失败（${code}），请检查麦克风后重试。`)
      }
    }
    this.engine.setListener(listener)
    this.startTimer = setTimeout(() => {
      if (this.session === id) { try { this.engine?.cancel(id) } catch (_error) {}; this.finish('语音识别启动超时，请重试。') }
    }, 10000)
    try {
      // recognitionMode=0 lets the system engine capture the microphone directly.
      this.engine.startListening({ sessionId: id,
        audioInfo: { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 },
        extraParams: { recognitionMode: 0, vadBegin: 10000, vadEnd: 1500, maxAudioDuration: 60000 } })
    } catch (_error) { this.finish('麦克风启动失败，请关闭其他占用麦克风的应用后重试。') }
    return started
  }

  async stop(): Promise<string> {
    if (!this.session) return this.text
    const id = this.session
    const result = new Promise<string>((resolve, reject) => { this.stopResolve = resolve; this.stopReject = reject })
    this.stopTimer = setTimeout(() => {
      if (this.session === id) { try { this.engine?.cancel(id) } catch (_error) {}; this.finish('语音识别结果等待超时，请重试。') }
    }, 8000)
    try { this.engine?.finish(id) } catch (_error) { this.finish('语音识别结束失败，请重试。') }
    return result
  }

  private finish(error: string = ''): void {
    if (!this.session) return
    this.session = ''
    clearTimeout(this.startTimer)
    clearTimeout(this.stopTimer)
    const observer = this.observer
    this.observer = undefined
    if (error) {
      this.startReject?.(new Error(error))
      this.stopReject?.(new Error(error))
      observer?.onError(error)
    } else {
      // Empty audio can complete before onStart on some devices.
      this.startResolve?.()
      this.stopResolve?.(this.text)
      observer?.onComplete(this.text)
    }
    this.startResolve = undefined
    this.startReject = undefined
    this.stopResolve = undefined
    this.stopReject = undefined
  }

  async cancel(): Promise<void> {
    this.generation++
    if (!this.session) return
    try { this.engine?.cancel(this.session) } catch (_error) {}
    this.finish()
  }

  async speak(text: string): Promise<void> {
    await this.stopSpeaking()
    if (this.speaker === undefined) {
      try { this.speaker = await textToSpeech.createEngine({ language: 'zh-CN', person: 0, online: 1 }) }
      catch (_error) { throw new Error('当前设备的中文朗读引擎不可用。') }
    }
    const id = util.generateRandomUUID()
    const finished = new Promise<void>((resolve, reject) => { this.speakResolve = resolve; this.speakReject = reject })
    this.speaker.setListener({
      onStart: (_id: string, _response: textToSpeech.StartResponse): void => {},
      onComplete: (requestId: string, _response: textToSpeech.CompleteResponse): void => {
        if (requestId === id) { this.speakResolve?.(); this.speakResolve = undefined }
      },
      onStop: (requestId: string, _response: textToSpeech.StopResponse): void => {
        if (requestId === id) { this.speakResolve?.(); this.speakResolve = undefined }
      },
      onError: (requestId: string, _code: number, _message: string): void => {
        if (requestId === id) { this.speakResolve = undefined; this.speakReject?.(new Error('语音朗读失败，请重试。')); this.speakReject = undefined }
      }
    })
    try { this.speaker.speak(text.slice(0, 9000), { requestId: id }) }
    catch (_error) { this.speakResolve = undefined; this.speakReject?.(new Error('语音朗读启动失败。')); this.speakReject = undefined }
    return finished
  }

  async stopSpeaking(): Promise<void> {
    try { this.speaker?.stop() } catch (_error) {}
    this.speakResolve?.()
    this.speakResolve = undefined
    this.speakReject = undefined
  }
}
