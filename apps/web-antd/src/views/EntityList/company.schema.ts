import type { QueryTableSchema } from '#/components/QueryTable/types';
import { backendApi } from '#/api/constants';

export const companySchema: QueryTableSchema = {
  title: '公司列表1',

  tableName: 't_base_company',

  saveEntityName: 't_base_company',
  primaryKey: 'FID',

    actionModule: '/src/views/EntityList/company.ts',

  toolbar: {
    actions: [
      {
        key: 'add',
        label: '新增',
        type: 'primary',
        action: 'add',
      },
      {
        key: 'reload',
        label: '刷新',
        action: 'reload',
      },
    ],
  },

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
    query: backendApi('DynamicQueryBeta/queryforvben'),
    delete: backendApi('DataBatchDelete/BatchDelete'),
    export: backendApi('DynamicQueryBeta/ExportExcel'),
  },
};
