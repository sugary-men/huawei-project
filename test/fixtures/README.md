# 离线测试素材

本目录中的 JSON 和 PNG 均由 `generate.cjs` 使用 Node.js 内置模块生成，不需要网络或第三方依赖。

## 一键生成

```powershell
node test/fixtures/generate.cjs
node test/fixtures/verify.cjs
```

## 文件

- `library.json`：12 份资料，覆盖文本和图片两种资料形态。
- `knowledge-graph.json`：120 个知识节点、1 个根节点及关系边，包含坐标、标签、来源和正文。
- `rag-workspace.seed.json`：本地模式的 RAG 工作区示例，用于验证“先建库、后配置在线 Embedding”。
- `images/knowledge-card-01.png` 至 `04.png`：程序生成的 PNG 编号占位图。
- `manifest.json`：数据规模与文件清单。

数据时间戳固定，重复执行生成器会得到相同结构。替换为真实数据时，保持 `knowledge-graph.json` 中 `nodes`、`edges` 和 `library.json` 的字段结构即可。
