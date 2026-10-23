import { ActionItem } from '../models/AppModels'

export class ToolService {
  static formSteps(): ActionItem[] {
    return [
      { title: '选择表单模板', subtitle: '等待表单服务提供模板', status: 'pending' },
      { title: '补充字段并确认', subtitle: '等待档案及字段校验', status: 'pending' },
      { title: '保存和导出草稿', subtitle: '等待草稿服务接入', status: 'pending' }
    ]
  }

  static focusSteps(): ActionItem[] {
    return [
      { title: '检查设备连接', subtitle: '蓝牙和碰一碰状态', status: 'pending' },
      { title: '开始专注', subtitle: '等待设备状态判定', status: 'pending' },
      { title: '同步专注结果', subtitle: '等待本地记录服务', status: 'pending' }
    ]
  }

  static studySteps(): ActionItem[] {
    return [
      { title: '查看课程与任务', subtitle: '等待课表和提醒服务', status: 'pending' },
      { title: '生成学习时间块', subtitle: '等待学习计划服务', status: 'pending' },
      { title: '记录每日打卡', subtitle: '等待学习记录服务', status: 'pending' }
    ]
  }

  static knowledgeSteps(): ActionItem[] {
    return [
      { title: '搜索课程资料', subtitle: '关键词与向量检索', status: 'active' },
      { title: '核对来源片段', subtitle: '课程、章节与原文', status: 'pending' },
      { title: '在对话中继续', subtitle: '将带引用上下文交给 Agent', status: 'pending' }
    ]
  }

  static careerSteps(): ActionItem[] {
    return [
      { title: '明确岗位与目标', subtitle: '产品经理 · 2027 届', status: 'completed' },
      { title: '简历诊断与优化', subtitle: '等待简历工具调用', status: 'active' },
      { title: '限时模拟面试', subtitle: '将在简历优化后开启', status: 'pending' }
    ]
  }

  static scheduleSteps(): ActionItem[] {
    return [
      { title: '同步课程与截止日期', subtitle: '本周 12 项安排', status: 'completed' },
      { title: '生成时间块', subtitle: '等待你确认优先级', status: 'active' },
      { title: '每日复盘', subtitle: '将根据完成情况调整', status: 'pending' }
    ]
  }

  static budgetSteps(): ActionItem[] {
    return [
      { title: '建立本月预算', subtitle: '生活预算 ¥1,200', status: 'completed' },
      { title: '录入消费流水', subtitle: '今日 3 笔待确认', status: 'active' },
      { title: '生成周度洞察', subtitle: '将在周日自动生成', status: 'pending' }
    ]
  }
}
