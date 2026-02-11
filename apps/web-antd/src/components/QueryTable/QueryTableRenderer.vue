<script setup lang="ts">
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { requestClient } from '#/api/request';
import { Button, message } from 'ant-design-vue';
import { ref } from 'vue';
import type { QueryTableSchema } from './types';

const props = defineProps<{
  schema: QueryTableSchema;
}>();

const currentQuery = ref({});

const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    ...props.schema.grid,
    proxyConfig: {
      ajax: {
        query: async ({ page, sort }, formValues) => {
          currentQuery.value = formValues;
          return requestClient.post(props.schema.api.query, {
            TableName: props.schema.tableName,
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
