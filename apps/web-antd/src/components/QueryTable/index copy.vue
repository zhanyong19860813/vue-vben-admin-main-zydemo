<script setup lang="ts">
import { Button, message } from 'ant-design-vue';
import { ref } from 'vue';
import axios from 'axios';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { requestClient } from '#/api/request';
import type { QueryTableSchema } from './types';

const props = defineProps<{
  schema: QueryTableSchema;
}>();

const currentQuery = ref<Record<string, any>>({});

/**
 * 初始化 Grid
 */
const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    ...props.schema.grid,
    proxyConfig: {
      ajax: {
        query: async ({ page, sort }, formValues) => {

          // 🔥 过滤空值
          const cleanWhere = Object.fromEntries(
            Object.entries(formValues || {}).filter(
              ([_, v]) => v !== undefined && v !== null && v !== ''
            )
          );

          currentQuery.value = cleanWhere;

          return requestClient.post(props.schema.api.query, {
            TableName: props.schema.tableName,
            Page: page.currentPage,
            PageSize: page.pageSize,
            SortBy: sort?.field || props.schema.grid.sortConfig?.defaultSort?.field,
            SortOrder: sort?.order?.toLowerCase() ||
              props.schema.grid.sortConfig?.defaultSort?.order ||
              'asc',
            SimpleWhere: cleanWhere,
          });
        },
      },
    },
  },
  formOptions: props.schema.form,
});

/**
 * 通用删除
 */
const handleDelete = async () => {
  if (!props.schema.api.delete) return;

  const grid = gridApi.grid;
  if (!grid) return;

  const rows = grid.getCheckboxRecords();

  if (!rows.length) {
    message.warning('请选择要删除的数据');
    return;
  }

  await axios.post(props.schema.api.delete, [
    {
      tablename: props.schema.tableName,
      key: 'FID', // 🔥 默认主键
      Keys: rows.map((r: any) => r.FID),
    },
  ]);

  message.success('删除成功');
  gridApi.reload();
};

/**
 * 通用导出（所见即所得）
 */
const handleExport = async () => {
  if (!props.schema.api.export) return;

  const sort = gridApi.grid?.getSortColumns?.()?.[0];

   // ① 构建 QueryField（如果后端支持的话）
  const queryField = props.schema.grid.columns
  ?.filter((c: any) => c.field)
  .map((c: any) => {
    // 如果有标题就用标题
    if (c.title) {
      return `${c.field} as ${c.title}`;
    }
    return c.field;
  })
  .join(',');

  const res = await axios.post(
    props.schema.api.export,
    {
      TableName: props.schema.tableName,

      // 🔥 当前查询条件
      SimpleWhere: currentQuery.value,

      // 🔥 当前排序
      SortBy: sort?.field || 'Name',
      SortOrder: sort?.order?.toLowerCase() || 'asc',

      // 🔥 当前列
      QueryField:  queryField,

        
    },
    { responseType: 'blob' }
  );

  const blob = new Blob([res.data]);
  const url = window.URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${props.schema.title}.xlsx`;
  a.click();
};
</script>

<template>
  <Grid :table-title="schema.title">
    <template #toolbar-tools>

      <!-- 删除 -->
      <Button
        v-if="schema.api.delete"
        danger
        @click="handleDelete"
      >
        删除
      </Button>

      <!-- 导出 -->
      <Button
        v-if="schema.api.export"
        class="ml-2"
        @click="handleExport"
      >
        导出
      </Button>

      <!-- 刷新 -->
      <Button
        class="ml-2"
        type="primary"
        @click="gridApi.reload()"
      >
        刷新
      </Button>

    </template>
  </Grid>
</template>
