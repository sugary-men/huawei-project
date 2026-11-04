import { RagService } from './RagService'

// 端侧确定性哈希向量：与离线 chunk 向量同口径，断网时替代在线 Embedding。
// 算法：FNV-1a 哈希 + 符号交替 + log 加权 + L2 归一化。
export const LOCAL_VECTOR_MODEL: string = 'local-hash-64'
export const LOCAL_VECTOR_DIM: number = 64

export function localHashVector(text: string): number[] {
  const tokens: string[] = RagService.tokens(text)
  const vector: number[] = new Array<number>(LOCAL_VECTOR_DIM).fill(0)
  tokens.forEach((token: string, index: number): void => {
    let hash: number = 2166136261
    for (let i = 0; i < token.length; i++) {
      hash = (hash ^ token.charCodeAt(i)) * 16777619
      hash = hash >>> 0
    }
    const sign: number = index % 2 === 0 ? 1 : -1
    vector[hash % LOCAL_VECTOR_DIM] += sign * (1 + Math.log(1 + token.length))
  })
  return normalize(vector)
}

function normalize(vector: number[]): number[] {
  let norm: number = 0
  vector.forEach((value: number): void => {
    norm += value * value
  })
  if (norm <= 0) return new Array<number>(LOCAL_VECTOR_DIM).fill(0)
  const scale: number = 1 / Math.sqrt(norm)
  return vector.map((value: number): number => value * scale)
}
