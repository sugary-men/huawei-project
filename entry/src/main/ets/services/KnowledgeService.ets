import { KnowledgeChunk, KnowledgeIndex, KnowledgeRepository } from '../models/RagModels'
import { LOCAL_VECTOR_MODEL, localHashVector } from './LocalVector'

export class MemoryKnowledgeRepository implements KnowledgeRepository {
  private index: KnowledgeIndex = { revision: 'empty', chunks: [] }
  snapshot(): KnowledgeIndex { return this.index }

  replace(index: KnowledgeIndex): void {
    this.index = {
      revision: index.revision,
      chunks: index.chunks.map((chunk: KnowledgeChunk): KnowledgeChunk => ({
        id: chunk.id, sourceId: chunk.sourceId, title: chunk.title,
        location: chunk.location, course: chunk.course, content: chunk.content,
        vector: chunk.vector.slice(), vectorModel: chunk.vectorModel,
        modality: chunk.modality || 'text', mediaPath: chunk.mediaPath || '',
        mediaMimeType: chunk.mediaMimeType || ''
      }))
    }
  }
}

// 给离线索引补齐端侧哈希向量，保证查询向量与 chunk 向量同模型、同维度、同口径。
function withLocalVectors(index: KnowledgeIndex): KnowledgeIndex {
  return {
    revision: index.revision,
    chunks: index.chunks.map((chunk: KnowledgeChunk): KnowledgeChunk => ({
      id: chunk.id, sourceId: chunk.sourceId, title: chunk.title, location: chunk.location,
      course: chunk.course, content: chunk.content,
      vector: localHashVector(`${chunk.title} ${chunk.content}`), vectorModel: LOCAL_VECTOR_MODEL,
      modality: chunk.modality || 'text', mediaPath: chunk.mediaPath || '',
      mediaMimeType: chunk.mediaMimeType || ''
    }))
  }
}

// 仅用于离线验收，不代表学校官方资料。正式索引由数据侧注入。
export function demoKnowledgeIndex(): KnowledgeIndex {
  const index: KnowledgeIndex = {
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
  return withLocalVectors(index)
}

// 炫神（许昊龙）公开资料，整理自公开搜索摘要，仅作离线知识库演示。
// 出生地、籍贯、家庭背景等互相矛盾或来源不足的内容已单独标注。
export function xuanShenKnowledgeIndex(): KnowledgeIndex {
  const index: KnowledgeIndex = {
    revision: 'xuan-shen-1',
    chunks: [
      { id: 'xs-1', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '基本身份', course: '炫神知识库',
        content: '炫神是中国英雄联盟游戏解说主播，本名许昊龙。他自称龙哥，粉丝群体常被称作炫家军。网络社群中也有炫狗、龙龟、口水娃等戏称。', vector: [], vectorModel: '' },
      { id: 'xs-2', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '账号与平台', course: '炫神知识库',
        content: '炫神的B站实名账号为炫神_，UID是299013902。公开资料显示他先后在斗鱼、虎牙、B站等平台活跃，不同时期的平台归属存在变化。', vector: [], vectorModel: '' },
      { id: 'xs-3', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '直播平台', course: '炫神知识库',
        content: '炫神曾在虎牙使用直播间ID 840747直播，通常下午15点前后开播。斗鱼存在Doyu丶炫神英雄联盟直播页面记录。', vector: [], vectorModel: '' },
      { id: 'xs-4', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '出生与籍贯', course: '炫神知识库',
        content: '多个自媒体资料称炫神出生于1999年4月5日。出生地存在矛盾说法，有资料称河南郑州新密市，也有资料称其自称福建福州长乐区。', vector: [], vectorModel: '' },
      { id: 'xs-5', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '福州关联', course: '炫神知识库',
        content: '炫神常被称为福州许昊龙。网络上还有福州十六中、华亚集团等说法，属于未经证实的贴吧和短视频段子，不应作为事实结论。', vector: [], vectorModel: '' },
      { id: 'xs-6', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '游戏能力', course: '炫神知识库',
        content: '炫神被称为S6赛季第一个王者，早期以杰斯、瑞文等上单英雄著称，因上路实力强曾被部分观众称为大TheShy。', vector: [], vectorModel: '' },
      { id: 'xs-7', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '口头禅与梗', course: '炫神知识库',
        content: '炫神常用芜湖芜湖、呜呼起飞等口癖，与主播大司马的芜湖梗相关。游龙当归海、围绕我打等也是网络名场面。', vector: [], vectorModel: '' },
      { id: 'xs-8', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '早期经历', course: '炫神知识库',
        content: '炫神自述曾在网吧做陪玩，自述100元一把，强调自己独立、不依赖家庭支持，电脑由自己购买。该内容属于直播自述。', vector: [], vectorModel: '' },
      { id: 'xs-9', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '2019年事件', course: '炫神知识库',
        content: '2019年炫神在峡谷之巅排位中辱骂职业选手957，被列入主播三大喷。2019年12月26日前后，虎牙主播last炫神因直播中侮辱湖南人被封禁，后有资料称平台重新开放。', vector: [], vectorModel: '' },
      { id: 'xs-10', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '2025年超雄事件', course: '炫神知识库',
        content: '2025年7月12日，炫神直播中情绪失控，说出超雄等于超级英雄、炫神一怒天地抖等言论，引发广泛争议。', vector: [], vectorModel: '' },
      { id: 'xs-11', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: 'iG声明', course: '炫神知识库',
        content: '2025年8月18日，iG电子竞技俱乐部发布严正声明，指控炫神在二路解说中长期侮辱选手，取消其LPL二路解说权并启动法律维权。', vector: [], vectorModel: '' },
      { id: 'xs-12', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '判决与道歉', course: '炫神知识库',
        content: '2026年6月12日，福州市仓山区法院判决B站主播许昊龙炫神对TheShy和Rookie构成名誉权侵权，需公开道歉并赔偿精神损害抚慰金及律师费。', vector: [], vectorModel: '' },
      { id: 'xs-13', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '后续影响', course: '炫神知识库',
        content: 'BLG俱乐部回复粉丝称，经与联盟沟通，炫神已被禁止二路直播英雄联盟相关赛事。2026年下半年出现转战王者荣耀等直播切片。', vector: [], vectorModel: '' },
      { id: 'xs-14', sourceId: 'xuan-shen', title: '炫神（许昊龙）公开资料', location: '使用建议', course: '炫神知识库',
        content: '回答争议事件时优先引用2026年6月12日福州法院生效判决。出生地、籍贯、家庭背景等信息来源质量不足，回答时应标注暂未证实。', vector: [], vectorModel: '' }
    ]
  }
  return withLocalVectors(index)
}
