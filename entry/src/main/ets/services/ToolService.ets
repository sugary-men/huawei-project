import { ActionItem } from '../models/AppModels'

export class ToolService {
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
