# ONNX 学生编码器上鸿蒙说明

当前端侧查询编码器 `StudentQueryEmbedder` 使用确定性哈希向量（`local-hash-64`）兜底，
与 `KnowledgeService` 中炫神 / 课程离线索引的 chunk 向量同模型、同维度，因此主聊天的
RAG 已经可以离线跑“关键词 + 余弦相似度”的混合检索，不依赖在线 Embedding。

要把蒸馏得到的 MiniLM 学生模型真正跑在鸿蒙端侧，需要经过模型转换和分词器两步。鸿蒙
ArkTS 不能直接加载 ONNX；官方路径是 MindSpore Lite：先用模型转换工具把 ONNX 转成
`.ms`，再用 `@ohos.ai.mindSporeLite` 加载推理。

## 已准备的产物

- `student_encoder/student_encoder.onnx`：任务契约版本，int64 输入。
- `student_encoder/student_encoder_int32.onnx`：鸿蒙部署版本，int32 输入。
  MindSpore Lite 的算子列表不支持 int64 输入，因此必须用 int32 版本转换。
- `student_encoder/student_encoder.pt`：含 `state_dict` 与配置字典，用于重建 PyTorch 模型。

## 转换步骤

1. 在 DevEco Studio 打开 Model Converter（或使用 MindSpore Lite 模型转换工具），
   输入 `student_encoder_int32.onnx`，输出 `.ms` 模型。
2. 把 `.ms` 模型放入 `entry/src/main/resources/rawfile/`。
3. 从 HuggingFace 缓存目录
   `C:\Users\DELL\.cache\huggingface\hub\models--sentence-transformers--all-MiniLM-L6-v2\snapshots\<hash>\vocab.txt`
   复制词表到 `entry/src/main/resources/rawfile/minilm_vocab.txt`，并在 ArkTS 侧实现
   Bert 的 WordPiece 分词：小写化、按标点切分、最长匹配 wordpiece、首尾加 `[CLS]` 和
   `[SEP]`，生成 `input_ids`（int32）与 `attention_mask`（int32）。
4. 引入 `@ohos.ai.mindSporeLite`，加载 `.ms`、构建模型、写入 `input_ids` /
   `attention_mask` 两个输入张量，推理后取 `embedding` 输出，再做一次 L2 归一化。
5. 把 `StudentQueryEmbedder.embed()` 换成上述推理，`modelId` 改为与离线 chunk 向量
   一致的模型标识；离线 chunk 向量也必须用同一 MiniLM 学生编码器重新生成后写入索引。

## 参考文档

- MindSpore Lite 模型转换：`开发指南/MindSpore_Lite_Kit_昇思推理框架服务/使用MindSpore_Lite进行模型转换/mindspore-lite-converter-guidelines`
- MindSpore Lite ArkTS API：`API参考/MindSpore_Lite_Kit_昇思推理框架服务/ArkTS_API/ohos_ai_mindSporeLite_端侧AI框架_/js-apis-mindsporelite`
- 算子支持列表（int64 限制）：`开发指南/MindSpore_Lite_Kit_昇思推理框架服务/附录/MindSpore_Lite_Kit算子支持列表/mindspore-lite-supported-operators`

以上文档可用 `devecocli docs read <documentId>` 查看。
