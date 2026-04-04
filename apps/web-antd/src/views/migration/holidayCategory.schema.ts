/**
 * 老系统：考勤管理 → 考勤基础资料 → 假别设定
 * 实体 v_att_lst_HolidayCategory，列来自 t_set_datagrid
 */
import type { QueryTableSchema } from '#/components/QueryTable/types';
import { backendApi } from '#/api/constants';

export const holidayCategorySchema: QueryTableSchema = {
  title: '假别设定（迁移测试）',

  tableName: 'v_att_lst_HolidayCategory',
  primaryKey: 'FID',

  toolbar: {
    actions: [],
  },

  form: {
    collapsed: false,
    submitOnChange: false,
    schema: [
      { component: 'Input', fieldName: 'HC_ID', label: '假别代号' },
      { component: 'Input', fieldName: 'HC_Name', label: '假别说明' },
    ],
  },

  grid: {
    columns: [
      { type: 'checkbox', width: 50 },
      { type: 'seq', width: 50 },
      { field: 'HC_ID', title: '假别代号', width: 100, sortable: true },
      { field: 'HC_Name', title: '假别说明', minWidth: 140, sortable: true, showOverflow: true },
      { field: 'HC_Min', title: '最小请假值', width: 110, sortable: true },
      { field: 'HC_Max', title: '最大请假值', width: 110, sortable: true },
      { field: 'HC_Unit', title: '假别单位', width: 100 },
      { field: 'HC_LegalNum', title: '法定数', width: 90, sortable: true },
      { field: 'HC_FailureTime', title: '失效日期', width: 120, sortable: true },
      { field: 'HC_ApplyPeriod', title: '申请期限', width: 100, sortable: true },
      { field: 'HC_Paidleave', title: '是否有薪假', width: 110, sortable: true },
    ],
    pagerConfig: { enabled: true, pageSize: 20 },
    sortConfig: {
      remote: true,
      defaultSort: { field: 'HC_ID', order: 'asc' },
    },
  },

  api: {
    query: backendApi('DynamicQueryBeta/queryforvben'),
  },
};
