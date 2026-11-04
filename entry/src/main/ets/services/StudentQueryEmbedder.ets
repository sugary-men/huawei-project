import { QueryEmbedder } from '../models/RagModels'
import { LOCAL_VECTOR_MODEL, localHashVector } from './LocalVector'

// 端侧查询编码器：当前用确定性哈希向量兜底，保证离线可用且与 chunk 向量同口径。
// 蒸馏得到的 MiniLM 学生模型（student_encoder.onnx）需先用 MindSpore Lite 转换工具转为 .ms，
// 并把输入改成 int32 后，再替换本类 embed 实现。具体步骤见同目录 ONNX_INTEGRATION.md。
export class StudentQueryEmbedder implements QueryEmbedder {
  modelId: string = LOCAL_VECTOR_MODEL

  async embed(query: string): Promise<number[]> {
    return localHashVector(query)
  }
}
