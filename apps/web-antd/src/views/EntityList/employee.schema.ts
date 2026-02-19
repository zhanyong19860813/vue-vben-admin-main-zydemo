import type { QueryTableSchema } from '#/components/QueryTable/types';

export const employeeSchema: QueryTableSchema = {
  title: '人员列表',

  tableName: 'v_t_employee_info',
   primaryKey: 'id',
   deleteEntityName: 't_base_employee',

  form: {
    collapsed: false,
    submitOnChange: true,
    schema: [
      { component: 'Input', fieldName: 'name', label: '姓名' },
      { component: 'Input', fieldName: 'code', label: '工号' },
    ],
  },

  grid: {
    columns: [
      { type: 'checkbox', width: 80 },
      { type: 'seq', width: 60 },
      { field: 'id', title: 'ID', minWidth: 180 },
      { field: 'name', title: '姓名', sortable: true },
      { field: 'code', title: '工号', sortable: true },
      { field: 'idcard_no', title: '身份证号', sortable: true },
      { field: 'brith_date', title: '出生日期', sortable: true },
      { field: 'mobile_no', title: '手机号', sortable: true },
    ],
    pagerConfig: { enabled: true, pageSize: 10 },
    //sortConfig: { remote: true },
     
     sortConfig: {
        remote: true,
        defaultSort: {
          field: 'code',
          order: 'asc',
        },
  },
    // SortBy: sort?.field || "Name",
    //     SortOrder: sort?.order?.toLowerCase() || "asc",
  },

  api: {
    query: 'http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben',
    delete: 'http://localhost:5155/api/DataBatchDelete/BatchDelete',
    export: 'http://127.0.0.1:5155/api/DynamicQueryBeta/ExportExcel',
  },
};
