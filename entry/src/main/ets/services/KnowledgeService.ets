import { KnowledgeChunk, KnowledgeIndex, KnowledgeRepository } from '../models/RagModels'

export class MemoryKnowledgeRepository implements KnowledgeRepository {
  private index: KnowledgeIndex = { revision: 'empty', chunks: [] }
  snapshot(): KnowledgeIndex { return this.index }

  replace(index: KnowledgeIndex): void {
    this.index = {
      revision: index.revision,
      chunks: index.chunks.map((chunk: KnowledgeChunk): KnowledgeChunk => ({
        id: chunk.id, sourceId: chunk.sourceId, title: chunk.title,
        location: chunk.location, course: chunk.course, content: chunk.content,
        vector: chunk.vector.slice(), vectorModel: chunk.vectorModel
      }))
    }
  }
}

// 仅用于离线验收，不代表学校官方资料。正式索引由 M7 数据侧注入。
export function demoKnowledgeIndex(): KnowledgeIndex {
  return {
    revision: 'demo-1',
    chunks: [
      { id: 'se-1', sourceId: 'se', title: '软件工程复习样例', location: '第 1 节 · 需求分析', course: '软件工程',
        content: '需求分析需要明确用户、使用场景、功能需求和非功能需求。每项需求应包含可验证的验收条件，并维护需求与测试之间的追踪关系。', vector: [], vectorModel: '' },
      { id: 'se-2', sourceId: 'se', title: '软件工程复习样例', location: '第 2 节 · 软件测试', course: '软件工程',
        content: '黑盒测试根据输入与预期输出设计用例，可使用等价类划分和边界值分析。白盒测试关注程序内部路径与覆盖率。测试报告应记录环境、步骤、预期结果和实际结果。', vector: [], vectorModel: '' },
      { id: 'ds-1', sourceId: 'ds', title: '数据结构复习样例', location: '第 1 节 · 栈和队列', course: '数据结构',
        content: '栈采用后进先出，队列采用先进先出。栈可用于括号匹配和函数调用，队列可用于广度优先搜索。顺序栈应检查空栈与容量边界。', vector: [], vectorModel: '' },
      { id: 'ds-2', sourceId: 'ds', title: '数据结构复习样例', location: '第 2 节 · 二叉树遍历', course: '数据结构',
        content: '二叉树前序遍历先访问根，再访问左子树和右子树；中序遍历依次访问左子树、根、右子树；后序遍历先访问左右子树，最后访问根。', vector: [], vectorModel: '' },
      { id: 'guide-1', sourceId: 'guide', title: '校园助手使用样例', location: '知识库说明', course: '使用指南',
        content: '知识库回答展示引用编号、资料标题、章节和原文。资料不足时应补充课程资料；需要联网查询时由数据侧兜底服务处理，当前离线模式不会自动联网。', vector: [], vectorModel: '' }
    ]
  }
}
