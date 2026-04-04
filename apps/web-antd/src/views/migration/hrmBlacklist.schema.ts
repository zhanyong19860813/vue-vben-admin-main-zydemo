/**
 * 老系统菜单「人事管理应用黑名单」迁移测试
 * 数据来源：t_sys_function.entity_name = v_HRMBlacklist，列来自 t_set_datagrid（按 entity 汇总）
 */
import type { QueryTableSchema } from '#/components/QueryTable/types';
import { backendApi } from '#/api/constants';

export const hrmBlacklistSchema: QueryTableSchema = {
  title: '人事管理应用黑名单（迁移测试）',

  tableName: 'v_HRMBlacklist',
  primaryKey: 'id',

  toolbar: {
    actions: [],
  },

  form: {
    collapsed: false,
    submitOnChange: false,
    schema: [
      { component: 'Input', fieldName: 'name', label: '姓名' },
      { component: 'Input', fieldName: 'emp_id', label: '工号' },
      { component: 'Input', fieldName: 'procedure_name', label: '应用名称' },
    ],
  },

  grid: {
    columns: [
      { type: 'checkbox', width: 50 },
      { type: 'seq', width: 50 },
      { field: 'id', title: 'id', minWidth: 200, showOverflow: true },
      { field: 'name', title: '姓名', width: 100, sortable: true },
      { field: 'emp_id', title: '工号', width: 100, sortable: true },
      { field: 'long_name', title: '部门', minWidth: 120, showOverflow: true },
      { field: 'procedure_name', title: '应用名称', minWidth: 160, showOverflow: true },
      { field: 'modify_emp', title: '修改人', width: 100 },
      { field: 'modify_time', title: '修改时间', width: 160, sortable: true },
    ],
    pagerConfig: { enabled: true, pageSize: 10 },
    sortConfig: {
      remote: true,
      defaultSort: { field: 'modify_time', order: 'desc' },
    },
  },

  api: {
    query: backendApi('DynamicQueryBeta/queryforvben'),
  },
};
