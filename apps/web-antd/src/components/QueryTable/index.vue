<script setup lang="ts">
import { Button } from 'ant-design-vue';
import { ref } from 'vue';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { requestClient } from '#/api/request';
import type { QueryTableSchema } from './types';

const props = defineProps<{
  schema: QueryTableSchema;
}>();

const currentQuery = ref<Record<string, any>>({});

const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    ...props.schema.grid,
    proxyConfig: {
      ajax: {
        query: async ({ page, sort }, formValues) => {
          currentQuery.value = formValues || {};
         

          console.log('formValues', formValues);

          // 👇 关键：如果没有排序，用 schema 的 defaultSort
  const defaultSort = props.schema.grid?.sortConfig?.defaultSort;

  const sortField = sort?.field || defaultSort?.field;
  const sortOrder =sort?.order || defaultSort?.order;

             // 👇 过滤掉值为 undefined、null 或空字符串的字段
            const rawValues = formValues || {};
            const cleanWhere = Object.fromEntries(
            Object.entries(rawValues).filter(
              ([_, value]) => value !== undefined && value !== null && value !== ''
            )
          );

          console.log('cleanWhere', cleanWhere);
          

          return requestClient.post(props.schema.api.query, {
            tableName: props.schema.tableName,
            page: page.currentPage,
            pageSize: page.pageSize,
            // sortBy: sort?.field,
            // sortOrder: sort?.order,
             sortBy: sortField,
            sortOrder: sortOrder,
            SimpleWhere: cleanWhere ,
          });
        },
      },
    },
  },
  formOptions: props.schema.form,
});
</script>

<template>
  <Grid :table-title="schema.title">
    <template #toolbar-tools>
      <Button type="primary" @click="gridApi.reload()">刷新</Button>
    </template>
  </Grid>
</template>
