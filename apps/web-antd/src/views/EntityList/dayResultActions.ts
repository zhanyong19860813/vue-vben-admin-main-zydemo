/**
 * 考勤日结果：执行日结（打开弹窗，调用 dbo.att_pro_DayResult）
 * 列表 schema 需配置 actionModule: '/src/views/EntityList/dayResultActions.ts'
 */
import type { QueryTableActionContext } from '#/components/QueryTable/types';

export default {
  async executeDaySettlement(_ctx: QueryTableActionContext) {
    return {
      type: 'openModal' as const,
      component: 'attendance/DayResultSettlementModal',
      props: { title: '执行日结', width: 960 },
    };
  },
};
