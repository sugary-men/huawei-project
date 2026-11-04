import { FeatureDefinition } from '../models/AppModels'

export const FEATURE_CATALOG: FeatureDefinition[] = [
  { id: 'home', icon: '✦', name: '智能助理', description: '目标澄清与任务推进', category: '核心' },
  { id: 'career', icon: '◫', name: '求职实验室', description: '简历与模拟面试', category: '完整流程' },
  { id: 'schedule', icon: '✓', name: '智能日程', description: '课程与任务安排', category: '完整流程' },
  { id: 'budget', icon: '¥', name: '消费洞察', description: '记账与预算分析', category: '完整流程' },
  { id: 'forms', icon: '▧', name: '表单填报', description: '模板、草稿与辅助填写', category: '完整流程' },
  { id: 'focus', icon: '◇', name: '自律魔方', description: 'BLE、NFC 与专注流程', category: '扩展模块' },
  { id: 'privacy', icon: '▣', name: '隐私与档案', description: 'HUKS 加密档案与上传授权', category: '扩展模块' },
  { id: 'health', icon: '♡', name: '健康计划', description: '饮食与运动陪伴', category: '扩展模块' },
  { id: 'weather', icon: '☀', name: '天气穿搭', description: '天气与出行建议', category: '扩展模块' },
  { id: 'study', icon: '▤', name: '学习助手', description: '资料推荐与答疑', category: '扩展模块' }
]
