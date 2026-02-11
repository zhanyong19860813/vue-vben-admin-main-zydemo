import type { QueryTableSchema } from '#/components/QueryTable/types';

export const companySchema: QueryTableSchema = {
  title: '公司列表',

  tableName: 't_base_company',

  form: {
    collapsed: false,
    submitOnChange: true,
    schema: [
      { component: 'Input', fieldName: 'Name', label: '公司名' },
      { component: 'Input', fieldName: 'Location', label: '地址' },
    ],
  },

  grid: {
    columns: [
      { type: 'checkbox', width: 80 },
      { type: 'seq', width: 60 },
      { field: 'FID', title: 'ID', minWidth: 180 },
      { field: 'Name', title: '公司名', sortable: true },
      { field: 'SimpleName', title: '简称', sortable: true },
      { field: 'Location', title: '地址', sortable: true },
    ],
    pagerConfig: { enabled: true, pageSize: 10 },
    //sortConfig: { remote: true },
     
     sortConfig: {
        remote: true,
        defaultSort: {
          field: 'Name',
          order: 'asc',
        },
  },
    // SortBy: sort?.field || "Name",
    //     SortOrder: sort?.order?.toLowerCase() || "asc",
  },

  api: {
    query: 'http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben',
    delete: '/api/DataBatchDelete/BatchDelete',
    export: '/api/DynamicQueryBeta/ExportExcel',
  },
};
