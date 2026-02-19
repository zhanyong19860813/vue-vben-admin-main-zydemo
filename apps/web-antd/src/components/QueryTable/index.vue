<script setup lang="ts">
import { Button, Modal, message } from 'ant-design-vue';
import { ref, computed } from 'vue';
import axios from 'axios';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { requestClient } from '#/api/request';
import type { QueryTableSchema } from './types';

/**
 * props
 */
const props = defineProps<{
  schema: QueryTableSchema;
}>();

/**
 * 当前查询条件（导出用）
 */
const currentQuery = ref<Record<string, any>>({});

/**
 * ===============================
 * 1️⃣ 初始化 Grid（你原来的方式）
 * ===============================
 */
const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    ...props.schema.grid,
    proxyConfig: {
      ajax: {
        query: async ({ page, sort }, formValues) => {
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
            SortBy:
              sort?.field ||
              props.schema.grid.sortConfig?.defaultSort?.field,
            SortOrder:
              sort?.order?.toLowerCase() ||
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
 * ===============================
 * 2️⃣ 预加载 EntityList action 模块
 * ===============================
 */
const actionModules = import.meta.glob(
  '/src/views/EntityList/*.ts',
  { eager: true }
);

/**
 * ===============================
 * 3️⃣ schema toolbar action 分发
 * ===============================
 */
async function handleToolbarClick(btn: any) {
  const actionName = btn.action;
  if (!actionName) {
    message.warning('按钮未配置 action');
    return;
  }

  const entity = props.schema.tableName;
  const modulePath =props.schema.actionModule;// `/src/views/EntityList/${entity}.ts`;
  const mod: any = actionModules[modulePath];

  if (!mod || !mod.default) {
    message.error(`未找到 action 模块：${entity}.ts`);
    return;
  }

  const fn = mod.default[actionName];
  if (!fn) {
    message.error(`未找到 action：${actionName}`);
    return;
  }

  await fn({
    gridApi,
    schema: props.schema,
  });
}

/**
 * ===============================
 * 4️⃣ 默认删除（所有列表通用）
 * ===============================
 */
async function handleDelete() {
  const grid = gridApi.grid;
  if (!grid) return;

  const rows = grid.getCheckboxRecords();
  if (!rows.length) {
    message.warning('请选择要删除的数据');
    return;
  }

  const primaryKey = props.schema.primaryKey || 'FID';
  const deleteEntityName =
    props.schema.deleteEntityName || props.schema.tableName;

  Modal.confirm({
    title: '确认删除',
    content: `确认删除选中的 ${rows.length} 条数据？`,
    async onOk() {
      await axios.post(props.schema.api.delete, [
        {
          tablename: deleteEntityName,
          key: primaryKey,
          Keys: rows.map((r: any) => r[primaryKey]),
        },
      ]);

      message.success('删除成功');
      gridApi.reload();
    },
  });
}

/**
 * ===============================
 * 5️⃣ 默认导出（所有列表通用）
 * ===============================
 */
async function handleExport() {
  const sort = gridApi.grid?.getSortColumns?.()?.[0];

  const queryField = props.schema.grid.columns
    ?.filter((c: any) => c.field)
    .map((c: any) => (c.title ? `${c.field} as ${c.title}` : c.field))
    .join(',');

  const res = await axios.post(
    props.schema.api.export,
    {
      TableName: props.schema.tableName,
      SimpleWhere: currentQuery.value,
      SortBy: sort?.field || 'Name',
      SortOrder: sort?.order?.toLowerCase() || 'asc',
      QueryField: queryField,
    },
    { responseType: 'blob' }
  );

  const blob = new Blob([res.data]);
  const url = window.URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${props.schema.title}.xlsx`;
  a.click();
  window.URL.revokeObjectURL(url);
}

/**
 * 暴露 gridApi 给 slot
 */
defineExpose({ gridApi });
</script>

<template>
  <Grid :table-title="schema.title">
    <template #toolbar-tools>
      <div class="query-table-toolbar">

        <!-- ① schema 定义按钮 -->
        <div class="toolbar-left">
          <Button
            v-for="btn in schema.toolbar?.actions || []"
            :key="btn.key"
            class="mr-2"
            :type="btn.type || 'default'"
            @click="handleToolbarClick(btn)"
          >
            {{ btn.label }}
          </Button>
        </div>

        <!-- ② 默认通用按钮 -->
        <div class="toolbar-center">
          <Button
            v-if="schema.api.delete"
            danger
            class="mr-2"
            @click="handleDelete"
          >
            删除
          </Button>

          <Button
            v-if="schema.api.export"
            class="mr-2"
            @click="handleExport"
          >
            导出
          </Button>

          <Button type="primary" @click="gridApi.reload()">
            刷新
          </Button>
        </div>

        <!-- ③ 页面 slot 扩展 -->
        <div class="toolbar-right">
          <slot name="toolbar-tools" :gridApi="gridApi" />
        </div>

      </div>
    </template>
  </Grid>
</template>

<style scoped>
 .query-table-toolbar {
  display: flex;
  align-items: center;
}
.toolbar-left,
.toolbar-center,
.toolbar-right {
  display: flex;
  align-items: center;
}
.toolbar-left {
  flex: 1;
}
.toolbar-center {
  flex: 1;
  justify-content: center;
}
.toolbar-right {
  flex: 1;
  justify-content: flex-end;
}  
</style>
