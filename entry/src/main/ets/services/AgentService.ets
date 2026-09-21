import { AgentMessage } from '../models/AppModels'

export class AgentService {
  static greeting(featureId: string): AgentMessage[] {
    if (featureId === 'career') {
      return [
        { role: 'agent', content: '欢迎来到求职实验室。我们会完成岗位画像、简历优化和递进式模拟面试。', meta: '已载入求职工作流' }
      ]
    }
    if (featureId === 'schedule') {
      return [{ role: 'agent', content: '我会把课程、作业与个人安排转成可执行的时间块。', meta: '日程工具已就绪' }]
    }
    if (featureId === 'budget') {
      return [{ role: 'agent', content: '账本已准备好。直接输入“午餐 18 元”，我会自动分类并更新预算。', meta: '记账工具已就绪' }]
    }
    return [{ role: 'agent', content: '告诉我你的目标，我会先澄清约束，再为你规划可执行的下一步。', meta: 'CampusPilot 已就绪' }]
  }

  static mockReply(featureId: string, prompt: string): string {
    if (featureId === 'career') return '已记录你的目标。我会先提取岗位关键词和项目证据，再生成可直接修改的简历优化清单。'
    if (featureId === 'schedule') return '我已将信息放入待安排队列。下一步会按截止日期、耗时和精力曲线生成时间块。'
    if (featureId === 'budget') return '消费已记录并归类。预算、分类占比和本周趋势会在数据面板中同步更新。'
    return `已记录「${prompt}」。需要外部信息时，我会先说明将调用的工具并征求确认。`
  }
}
