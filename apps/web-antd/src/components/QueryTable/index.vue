<script setup lang="ts">
import { Button, Modal, message } from 'ant-design-vue';
//  import ModalWrapper from '#/components/ModalWrapper.vue';
import { computed, ref, watch, defineAsyncComponent, h, onBeforeUnmount } from 'vue';
import FormTabsTableContent from '#/components/FormTabsTableModal/FormTabsTableContent.vue';
import FormFromDesignerModal from '#/views/EntityList/FormFromDesignerModal.vue';
import type { TabTableItem } from '#/components/FormTabsTableModal/types';
import axios from 'axios';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { backendApi } from '#/api/constants';
import { recordOperationLog } from '#/api/operationLog';
import { requestClient } from '#/api/request';
import { resolveDictionaryInSchema } from '#/views/demos/form-designer/resolveDictionarySchema';
import type { QueryTableSchema } from './types';

import { getCurrentInstance } from 'vue'

const vm = getCurrentInstance();
 
 
import {   createApp } from 'vue';
 
//import { Modal } from 'ant-design-vue';

/**
 * props
 */
const props = defineProps<{
  schema: QueryTableSchema;
}>();

/**
 * 当前查询条件
 */
const currentQuery = ref<Record<string, any>>({});

/**
 * 工具栏按钮（合并 toolbar.actions + 无配置时的公共按钮兜底）
 */
const toolbarActionsForRender = computed(() => {
  const actions = props.schema.toolbar?.actions ?? [];
  if (actions.length > 0) return actions;
  // 向后兼容：无 toolbar.actions 时，若有 api 则显示公共按钮
  const fallback: any[] = [];
  if (props.schema.api?.delete) fallback.push({ key: 'deleteSelected', label: '删除', action: 'deleteSelected' });
  if (props.schema.api?.export) fallback.push({ key: 'export', label: '导出', action: 'export' });
  fallback.push({ key: 'reload', label: '刷新', action: 'reload', type: 'primary' });
  return fallback;
});

/** 解析查询表单 schema 中的数据字典（Select 等控件的 options） */
const resolvedFormOptions = ref<any>({ schema: [], collapsed: false, submitOnChange: true });
watch(
  () => props.schema?.form,
  async (form) => {
    if (!form) {
      resolvedFormOptions.value = { schema: [], collapsed: false, submitOnChange: true };
      return;
    }
    const rawSchema = form.schema ?? [];
    const hasDict = rawSchema.some(
      (s: any) => s?.componentProps?.dataSourceType === 'dictionary' && s?.componentProps?.dictionaryId,
    );
    const schema = hasDict ? await resolveDictionaryInSchema([...rawSchema]) : rawSchema;
    resolvedFormOptions.value = { ...form, schema };
  },
  { immediate: true, deep: true },
);

/**
 * ===============================
 * 1️⃣ 初始化 Grid
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
  formOptions: computed(() => resolvedFormOptions.value),
});

/**
 * ===============================
 * 2️⃣ 预加载 action 模块（仍然 eager）
 * ===============================
 */
const actionModules = import.meta.glob(
  '/src/views/EntityList/*.ts',
  { eager: true }
);

/**
 * ===============================
 * 3️⃣ 打开弹窗（只在当前组件内部）
 * ===============================
 */
/**
 * ===============================
 * 3️⃣ 打开弹窗（修复版）
 * ===============================
 */
async function openModal(componentPath: string, modalProps?: Record<string, any>) {
  return new Promise((resolve) => {
    const AsyncComp = defineAsyncComponent(() =>
      import(`/src/views/${componentPath}.vue`)
    )

    const modalInstance = Modal.confirm({
      title: modalProps?.title || '',
      icon: null,
      width: 800,
      footer: null,
      content: () => {
        const vnode = h(AsyncComp, {
          ...(modalProps || {}),
          onSuccess: (data: any) => {
            resolve(data || 'success')
            modalInstance.destroy()
          },
          onCancel: () => {
            resolve('cancel')
            modalInstance.destroy()
          }
        })

        // ⭐ 关键
        if (vm) {
          vnode.appContext = vm.appContext
        }

        return vnode
      },
    })
  })
}

/**
 * 按 form_code 加载表单设计器配置，打开 FormFromDesignerModal
 */
async function openFormFromDesignerModal(
  formCode: string,
  options?: { initialValues?: Record<string, any>; title?: string }
) {
  const res = await requestClient.post<{
    items: Array<{ schema_json?: string; code?: string; title?: string }>;
  }>(backendApi('DynamicQueryBeta/queryforvben'), {
    TableName: 'vben_form_desinger',
    Page: 1,
    PageSize: 1,
    SortBy: 'updated_at',
    SortOrder: 'desc',
    Where: {
      Logic: 'AND',
      Conditions: [{ Field: 'code', Operator: 'eq', Value: formCode.trim() }],
      Groups: [],
    },
  });
  const items = res?.items ?? [];
  const rec = items[0];
  if (!rec?.schema_json) {
    message.warning(`未找到 code 为「${formCode}」的表单配置`);
    return;
  }
  const parsed = JSON.parse(rec.schema_json) as {
    layout?: { cols?: number; labelWidth?: number; labelAlign?: string };
    schema?: any[];
  };
  const formSchema = Array.isArray(parsed?.schema) ? parsed.schema : [];
  const saveEntityName = props.schema.saveEntityName ?? props.schema.tableName ?? '';
  const primaryKey = props.schema.primaryKey ?? 'id';

  let modalInstance: any = null;
  modalInstance = Modal.confirm({
    title: options?.title ?? rec.title ?? '表单',
    icon: null,
    width: 640,
    footer: null,
    content: () => {
      const vnode = h(FormFromDesignerModal, {
        formSchema,
        saveEntityName,
        primaryKey,
        formTitle: rec.title ?? '表单',
        layout: parsed.layout,
        initialValues: options?.initialValues,
        onSuccess: () => {
          modalInstance?.destroy?.();
          gridApi.reload();
        },
        onCancel: () => modalInstance?.destroy?.(),
      });
      if (vm) vnode.appContext = vm.appContext;
      return vnode;
    },
  });
}

/**
 * ===============================
 * 4️⃣ toolbar 分发（核心改造点）
 * ===============================
 */
async function handleToolbarClick(btn: any) {
  const actionName = btn.action;
  recordOperationLog({
    actionType: 'button_click',
    target: btn.key || actionName,
    description: `点击: ${btn.label || actionName} (${props.schema.tableName || ''})`,
  });

  // 1️⃣ 尝试执行 actionModule 中的 handler
  const modulePath = props.schema.actionModule;
  const mod: any = modulePath ? actionModules[modulePath] : null;
  const fn = actionName ? mod?.default?.[actionName] : null;

  if (fn) {
    const result = await fn({ gridApi, schema: props.schema, btn });
    if (result?.type === 'openModal') {
      await openModal(result.component, {
        ...result.props,
        width: result.props?.width || 800,
        style: { height: result.props?.height || '500px' },
      });
      gridApi.reload();
      return;
    }
    if (result?.type === 'openFormTabsTableModal') {
      openFormTabsTableModal({
        title: result.title || '表单 + 页签 + 表格',
        formSchema: result.formSchema,
        tabs: result.tabs,
        width: result.width,
      });
      return;
    }
    if (result?.type === 'openFormFromDesigner') {
      await openFormFromDesignerModal(result.formCode, {
        initialValues: result.initialValues,
        title: result.title,
      });
      return;
    }
    return;
  }

  // 2️⃣ 无自定义 handler：若按钮有 form_code，自动按 form_code 打开表单
  const formCode = btn.form_code ?? btn.formCode;
  if (formCode?.trim()) {
    const requiresSelection = btn.requiresSelection ?? btn.requires_selection;
    let initialValues: Record<string, any> | undefined;
    if (requiresSelection) {
      const rows = gridApi.grid?.getCheckboxRecords?.() ?? [];
      if (!rows.length) {
        message.warning('请先选择一条数据');
        return;
      }
      initialValues = rows[0];
    }
    await openFormFromDesignerModal(formCode, { initialValues, title: btn.label });
    return;
  }

  message.warning(`未配置 action 模块或 form_code，无法处理按钮「${btn.label}」`);
}
 

/**
 * ===============================
 * 5️⃣ 删除
 * ===============================
 */
async function handleDelete() {
  recordOperationLog({
    actionType: 'button_click',
    target: 'deleteSelected',
    description: `点击: 删除 (${props.schema.tableName || ''})`,
  });
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
 * 6️⃣ 导出
 * ===============================
 */
async function handleExport() {
  recordOperationLog({
    actionType: 'button_click',
    target: 'export',
    description: `点击: 导出 (${props.schema.tableName || ''})`,
  });
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
 * FormTabsTable 弹窗 - 使用 Modal.confirm 动态创建，避免影响路由切换
 */
let formTabsTableModalInstance: any = null;

onBeforeUnmount(() => {
  formTabsTableModalInstance?.destroy?.();
  formTabsTableModalInstance = null;
});

interface OpenFormTabsTableOptions {
  title?: string;
  formSchema: any[];
  tabs: TabTableItem[];
  width?: number;
}

function openFormTabsTableModal(options: OpenFormTabsTableOptions) {
  const { title = '表单 + 页签 + 表格', formSchema, tabs, width = 900 } = options;

  formTabsTableModalInstance = Modal.confirm({
    title,
    icon: null,
    width,
    footer: null,
    content: () => {
      const vnode = h(FormTabsTableContent, {
        formSchema,
        tabs,
        onSuccess: () => {
          formTabsTableModalInstance?.destroy?.();
          formTabsTableModalInstance = null;
          gridApi.reload();
        },
        onCancel: () => {
          formTabsTableModalInstance?.destroy?.();
          formTabsTableModalInstance = null;
        },
      });
      if (vm) {
        vnode.appContext = vm.appContext;
      }
      return vnode;
    },
  });
}

/**
 * 暴露 gridApi
 */
defineExpose({ gridApi });
</script>

<template>
  <Grid :table-title="schema.title">
    <template #toolbar-tools>
      <div class="query-table-toolbar">
        <div class="toolbar-left">
          <!-- 公共按钮（删除/导出/刷新）与自定义按钮统一从 toolbar.actions 渲染；无配置时向后兼容显示 -->
          <template v-for="btn in toolbarActionsForRender" :key="btn.key">
            <Button
              v-if="btn.action === 'deleteSelected' && schema.api?.delete"
              danger
              class="mr-2"
              @click="handleDelete"
            >
              {{ btn.label || '删除' }}
            </Button>
            <Button
              v-else-if="(btn.action === 'export' || btn.action === 'expol') && schema.api?.export"
              class="mr-2"
              @click="handleExport"
            >
              {{ btn.label || '导出' }}
            </Button>
            <Button
              v-else-if="btn.action === 'reload'"
              type="primary"
              class="mr-2"
              @click="gridApi.reload()"
            >
              {{ btn.label || '刷新' }}
            </Button>
            <Button
              v-else
              class="mr-2"
              :type="btn.type || 'default'"
              @click="handleToolbarClick(btn)"
            >
              {{ btn.label }}
            </Button>
          </template>
        </div>

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
  justify-content: space-between;
  flex-wrap: nowrap; /* 不换行 */
  width: 100%;
}

.toolbar-left,
.toolbar-center,
.toolbar-right {
  display: flex;
  align-items: center;
}

.toolbar-left {
  gap: 8px;
}

.toolbar-center {
  gap: 8px;
}

.toolbar-right {
  gap: 8px;
}
 </style>
