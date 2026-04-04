<script setup lang="ts">
import { Button, Modal, message } from 'ant-design-vue';
//  import ModalWrapper from '#/components/ModalWrapper.vue';
import {
  computed,
  ref,
  watch,
  defineAsyncComponent,
  h,
  nextTick,
  onBeforeUnmount,
  onMounted,
} from 'vue';
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
import { enhanceQueryTableGrid } from './queryTableGridEnhance';
import { normalizeDesignerGridAggFunc } from './normalizeDesignerGridAggFunc';

/** 默认铺满内容区高度、表体内部滚动；schema.grid.fillViewportHeight === false 时使用原 height/maxHeight */
function prepareQueryTableGrid(grid: Record<string, any> | undefined) {
  const merged = enhanceQueryTableGrid(normalizeDesignerGridAggFunc(grid ?? {}));
  if (merged.fillViewportHeight === false) {
    const { fillViewportHeight: _f, ...rest } = merged;
    return rest;
  }
  const { height: _h, maxHeight: _m, fillViewportHeight: _f, ...rest } = merged;
  return rest;
}

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
    ...prepareQueryTableGrid(props.schema.grid as any),
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

/** 页签打开后等价于点一次「收起」：须在 Grid mount 且注入 formApi 之后再调，成功后才标记完成 */
let queryFormDefaultCollapsedDone = false;
let queryFormCollapseRetryTimer: ReturnType<typeof setTimeout> | null = null;

function clearQueryFormCollapseRetry() {
  if (queryFormCollapseRetryTimer != null) {
    clearTimeout(queryFormCollapseRetryTimer);
    queryFormCollapseRetryTimer = null;
  }
}

function tryApplyQueryFormCollapsed(): boolean {
  const api = gridApi.formApi as { setState?: (s: Record<string, unknown>) => void } | undefined;
  if (typeof api?.setState !== 'function') return false;
  api.setState({ collapsed: true });
  nextTick(scheduleApplyQueryTableGridHeight);
  return true;
}

/** 等当前渲染周期与 VxeGrid 挂载后再试；失败则短时重试，避免过早调用无效 */
function scheduleQueryFormDefaultCollapse() {
  if (queryFormDefaultCollapsedDone) return;
  const schema = resolvedFormOptions.value?.schema;
  if (!Array.isArray(schema) || schema.length === 0) return;

  clearQueryFormCollapseRetry();

  let attempts = 0;
  const maxAttempts = 40;
  const intervalMs = 80;

  const step = () => {
    if (queryFormDefaultCollapsedDone) {
      clearQueryFormCollapseRetry();
      return;
    }
    if (tryApplyQueryFormCollapsed()) {
      queryFormDefaultCollapsedDone = true;
      clearQueryFormCollapseRetry();
      return;
    }
    attempts++;
    if (attempts >= maxAttempts) {
      clearQueryFormCollapseRetry();
      return;
    }
    queryFormCollapseRetryTimer = setTimeout(step, intervalMs);
  };

  nextTick(() => {
    nextTick(() => {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          setTimeout(() => {
            setTimeout(step, 150);
          }, 0);
        });
      });
    });
  });
}

watch(
  () => props.schema.tableName,
  () => {
    queryFormDefaultCollapsedDone = false;
    clearQueryFormCollapseRetry();
  },
);

watch(
  () => resolvedFormOptions.value?.schema,
  (schema) => {
    if (!Array.isArray(schema) || schema.length === 0) return;
    scheduleQueryFormDefaultCollapse();
  },
  { flush: 'post' },
);

/** 默认按视口自适应高度；grid.fillViewportHeight === false 时用 schema 里的 height/maxHeight */
const fillViewportEnabled = computed(
  () => (props.schema.grid as Record<string, any> | undefined)?.fillViewportHeight !== false,
);

const layoutRef = ref<HTMLElement | null>(null);
let layoutResizeObserver: ResizeObserver | null = null;
let layoutRaf = 0;
/** FormTabsTable 弹窗实例，卸载时销毁 */
let formTabsTableModalInstance: any = null;

function measureQueryTableViewportHeight(): number {
  const el = layoutRef.value;
  if (!el) return 0;
  const rect = el.getBoundingClientRect();
  const fromParent = Math.floor(rect.height);
  if (fromParent >= 120) return fromParent;
  const top = rect.top;
  return Math.max(0, Math.floor(window.innerHeight - top - 12));
}

function applyQueryTableGridViewportHeight() {
  if (!fillViewportEnabled.value) return;
  const h = measureQueryTableViewportHeight();
  const px = Math.max(260, h);
  gridApi.setGridOptions({ height: px });
  nextTick(() => {
    try {
      gridApi.grid?.recalculate?.();
    } catch {
      /* ignore */
    }
  });
}

function scheduleApplyQueryTableGridHeight() {
  cancelAnimationFrame(layoutRaf);
  layoutRaf = requestAnimationFrame(() => {
    layoutRaf = 0;
    applyQueryTableGridViewportHeight();
  });
}

onMounted(() => {
  nextTick(() => {
    scheduleApplyQueryTableGridHeight();
    layoutResizeObserver = new ResizeObserver(() => scheduleApplyQueryTableGridHeight());
    if (layoutRef.value) {
      layoutResizeObserver.observe(layoutRef.value);
    }
    window.addEventListener('resize', scheduleApplyQueryTableGridHeight);
    scheduleQueryFormDefaultCollapse();
  });
});

onBeforeUnmount(() => {
  formTabsTableModalInstance?.destroy?.();
  formTabsTableModalInstance = null;
  clearQueryFormCollapseRetry();
  layoutResizeObserver?.disconnect();
  layoutResizeObserver = null;
  window.removeEventListener('resize', scheduleApplyQueryTableGridHeight);
  cancelAnimationFrame(layoutRaf);
});

watch(
  () => [fillViewportEnabled.value, resolvedFormOptions.value, props.schema?.grid],
  () => nextTick(scheduleApplyQueryTableGridHeight),
  { deep: true },
);

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
  <div ref="layoutRef" class="query-table-layout">
    <Grid class="query-table-vben-grid" :table-title="schema.title">
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
  </div>
</template>
<style scoped>
/* 占满布局内容区：外层不滚动，由 vxe 表体承担纵向滚动 */
.query-table-layout {
  display: flex;
  flex-direction: column;
  flex: 1 1 0%;
  min-height: 0;
  height: 100%;
  width: 100%;
  overflow: hidden;
}

.query-table-layout :deep(.query-table-vben-grid) {
  display: flex;
  flex-direction: column;
  flex: 1 1 0%;
  min-height: 0;
  overflow: hidden;
}

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
