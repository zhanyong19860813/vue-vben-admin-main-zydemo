// components/QueryTable/useQueryTable.ts
import { ref } from 'vue';
import { requestClient } from '#/api/request';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import type { QueryTableSchema } from './types';

export function useQueryTable(schema: QueryTableSchema) {
  const currentQuery = ref({});

  const [Grid, gridApi] = useVbenVxeGrid({
    gridOptions: {
      ...schema.grid,
      proxyConfig: {
        ajax: {
          query: async ({ page, sort }, formValues) => {
            currentQuery.value = formValues;

            return requestClient.post(schema.api.query, {
              TableName: schema.tableName,
              Page: page.currentPage,
              PageSize: page.pageSize,
              SortBy: sort?.field,
              SortOrder: sort?.order,
              SimpleWhere: formValues,
            });
          },
        },
      },
    },
    formOptions: schema.form,
  });

  return {
    Grid,
    gridApi,
    currentQuery,
    reload: () => gridApi.reload(),
    query: () => gridApi.query(),
  };
}
