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

          return requestClient.post(props.schema.api.query, {
            tableName: props.schema.tableName,
            page: page.currentPage,
            pageSize: page.pageSize,
            sortBy: sort?.field,
            sortOrder: sort?.order,
            where: formValues,
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
