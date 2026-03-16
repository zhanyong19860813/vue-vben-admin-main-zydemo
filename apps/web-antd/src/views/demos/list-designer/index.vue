<script setup lang="ts">
/**
 * 列表设计器 - 基于 QueryTableSchema 的可视化设计
 * 参考 company.schema.ts / employee.schema.ts
 */
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { Page } from '@vben/common-ui';
import {
  AutoComplete,
  Button,
  Card,
  Input,
  InputNumber,
  message,
  Select,
  Tabs,
  TreeSelect,
} from 'ant-design-vue';
import QueryTable from '#/components/QueryTable/index.vue';
import type { QueryTableSchema } from '#/components/QueryTable/types';
import {
  createDefaultFormSchemaItem,
  createDefaultGridColumn,
  FORM_COMPONENT_OPTIONS,
  type FormSchemaItem,
  type GridColumnItem,
  type ToolbarActionItem,
} from './list-designer.types';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { companySchema } from '#/views/EntityList/company.schema';
import { employeeSchema } from '#/views/EntityList/employee.schema';

const route = useRoute();

// ==================== 基础配置 ====================
const code = ref('');
const savedId = ref<string | null>(null); // 已保存记录的 id，用于更新
const menuid = ref(''); // 菜单ID，用于加载该菜单下已定义的按钮（vben_menu_actions）
const title = ref('列表标题');
const tableName = ref('t_base_table');
const primaryKey = ref('FID');
const saveEntityName = ref('');
const deleteEntityName = ref('');
const actionModule = ref('/src/views/EntityList/company.ts');

// ==================== 查询表单 ====================
const formSchemaList = ref<FormSchemaItem[]>([]);
const formCollapsed = ref(false);
const formSubmitOnChange = ref(true);

// ==================== 表格列 ====================
const gridColumns = ref<GridColumnItem[]>([]);
const gridPageSize = ref(10);
const sortField = ref('');
const sortOrder = ref<'asc' | 'desc'>('asc');

// ==================== 菜单列表（按名称选择） ====================
interface MenuOption { id: string; name: string; path?: string }
const menuList = ref<MenuOption[]>([]);
const loadingMenuList = ref(false);

// ==================== 工具栏（从菜单定义的按钮中选择） ====================
const toolbarActions = ref<ToolbarActionItem[]>([]);
const menuButtons = ref<Array<{ id: string; action_key: string; label: string; button_type?: string; action: string; confirm_text?: string; sort?: number }>>([]);
const loadingMenuButtons = ref(false);

// ==================== API ====================
const apiQuery = ref(backendApi('DynamicQueryBeta/queryforvben'));
const apiDelete = ref(backendApi('DataBatchDelete/BatchDelete'));
const apiExport = ref(backendApi('DynamicQueryBeta/ExportExcel'));

// ==================== 构建 Schema ====================
const designedSchema = computed<QueryTableSchema>(() => {
  const columns = gridColumns.value.map((c) => {
    if (c.type === 'checkbox' || c.type === 'seq') {
      return { type: c.type, width: c.width ?? (c.type === 'checkbox' ? 80 : 60) };
    }
    return {
      field: c.field,
      title: c.title,
      width: c.width,
      minWidth: c.minWidth,
      sortable: c.sortable,
    };
  });

  const sortConfig: any = { remote: true };
  if (sortField.value) {
    sortConfig.defaultSort = { field: sortField.value, order: sortOrder.value };
  }

  const schemaObj: QueryTableSchema & { _menuid?: string } = {
    title: title.value,
    tableName: tableName.value,
    primaryKey: primaryKey.value || 'FID',
    saveEntityName: saveEntityName.value || undefined,
    deleteEntityName: deleteEntityName.value || undefined,
    actionModule: actionModule.value || undefined,
    toolbar: {
      actions: toolbarActions.value.length ? toolbarActions.value : undefined,
    },
    form: {
      collapsed: formCollapsed.value,
      submitOnChange: formSubmitOnChange.value,
      schema: formSchemaList.value.map((f) => {
        const base: any = { component: f.component, fieldName: f.fieldName, label: f.label };
        if (f.component === 'Select' && f.componentProps) {
          base.componentProps = { ...f.componentProps };
        }
        return base;
      }),
    },
    grid: {
      columns,
      pagerConfig: { enabled: true, pageSize: gridPageSize.value },
      sortConfig,
    },
    api: {
      query: apiQuery.value,
      delete: apiDelete.value,
      export: apiExport.value,
    },
  };
  if (menuid.value) (schemaObj as any)._menuid = menuid.value;
  return schemaObj;
});

// 预览区 key：schema 变更时强制重新挂载 QueryTable，使表格列正确更新
const previewSchemaKey = computed(
  () =>
    `${previewRefreshKey.value}_${tableName.value}_${gridColumns.value.length}_${gridColumns.value.map((c) => c.field ?? c.type ?? '').join(',')}`,
);
const previewRefreshKey = ref(0);
const queryTableRef = ref<{ gridApi?: { reload?: () => void } } | null>(null);
function refreshPreview() {
  previewRefreshKey.value += 1;
  nextTick(() => {
    setTimeout(() => queryTableRef.value?.gridApi?.reload?.(), 80);
  });
}

// ==================== 表单字段操作 ====================
function addFormField() {
  formSchemaList.value.push(createDefaultFormSchemaItem(formSchemaList.value.length + 1));
  message.success('已添加查询项');
}
function removeFormField(index: number) {
  formSchemaList.value.splice(index, 1);
}

// ==================== 表格列操作 ====================
function addGridColumn() {
  gridColumns.value.push(createDefaultGridColumn(gridColumns.value.length + 1));
  message.success('已添加列');
}
function addCheckboxColumn() {
  gridColumns.value.unshift({ type: 'checkbox', width: 80 });
  message.success('已添加复选框列');
}
function addSeqColumn() {
  const hasSeq = gridColumns.value.some((c) => c.type === 'seq');
  if (hasSeq) {
    message.warning('序号列已存在');
    return;
  }
  const checkboxIdx = gridColumns.value.findIndex((c) => c.type === 'checkbox');
  gridColumns.value.splice(checkboxIdx >= 0 ? checkboxIdx + 1 : 0, 0, { type: 'seq', width: 60 });
  message.success('已添加序号列');
}
function removeGridColumn(index: number) {
  gridColumns.value.splice(index, 1);
}

// ==================== 根据表名从数据库加载表格列（表/视图结构） ====================
const loadingTableColumns = ref(false);
async function loadColumnsFromTable() {
  const name = tableName.value?.trim();
  if (!name) {
    message.warning('请先填写表名');
    return;
  }
  loadingTableColumns.value = true;
  try {
    const url = `${backendApi('TableBuilder/ListTableColumns')}?tableName=${encodeURIComponent(name)}`;
    const res = await requestClient.get<Array<{ columnName: string; dataType?: string }> | { code: number; data?: unknown; message?: string }>(url);
    // 请求客户端成功时只返回 response.data（即列数组），不是 { code, data }
    const list = Array.isArray(res)
      ? res
      : (res && typeof res === 'object' && Array.isArray((res as any).data) ? (res as any).data : []);
    if (list.length === 0) {
      message.warning('该表/视图没有列或表名不存在');
      return;
    }
    gridColumns.value = list.map((col: { columnName: string }) => ({
      field: col.columnName,
      title: col.columnName,
      sortable: true,
    }));
    message.success(`已加载 ${list.length} 列，可在「表格列」中修改列名`);
  } catch (e: any) {
    const msg = e?.response?.data?.message ?? e?.message ?? e?.data?.message ?? '加载列失败';
    message.error(msg);
  } finally {
    loadingTableColumns.value = false;
  }
}

// ==================== 加载菜单列表（vben_menus_new，用于按名称选择） ====================
async function loadMenuList() {
  loadingMenuList.value = true;
  try {
    const res = await requestClient.post<{ items: Array<{ id: string; name?: string; path?: string }> }>(
      backendApi('DynamicQueryBeta/queryforvben'),
      {
        TableName: 'vben_menus_new',
        Page: 1,
        PageSize: 500,
        SortBy: 'name',
        SortOrder: 'asc',
      },
    );
    menuList.value = (res?.items ?? []).map((r) => ({
      id: r.id,
      name: r.name ?? '',
      path: r.path ?? '',
    }));
  } catch {
    menuList.value = [];
  } finally {
    loadingMenuList.value = false;
  }
}

const menuSelectOptions = computed(() =>
  menuList.value.map((m) => ({
    label: m.path ? `${m.name} (${m.path})` : m.name,
    value: m.id,
  })),
);

/** 查询项可选的列（来自表格列配置，仅数据列）；含已有查询项引用的字段名（兼容导入/列删除后） */
const queryColumnOptions = computed(() => {
  const fromCols = gridColumns.value
    .filter((c) => c.field)
    .map((c) => ({ value: c.field!, label: `${c.title || c.field} (${c.field})` }));
  const used = new Set(fromCols.map((o) => o.value));
  const extras = formSchemaList.value
    .filter((f) => f.fieldName && !used.has(f.fieldName))
    .map((f) => ({ value: f.fieldName, label: `${f.label || f.fieldName} (${f.fieldName})` }));
  return [...fromCols, ...extras];
});

function onQueryColumnSelect(item: FormSchemaItem, field: string) {
  const col = gridColumns.value.find((c) => c.field === field);
  item.fieldName = field;
  item.label = col?.title ?? field;
}

// ==================== 加载菜单按钮（从 vben_menu_actions） ====================
async function loadMenuButtons() {
  if (!menuid.value?.trim()) {
    menuButtons.value = [];
    return;
  }
  loadingMenuButtons.value = true;
  try {
    const res = await requestClient.post<{ items: any[] }>(
      backendApi('DynamicQueryBeta/queryforvben'),
      {
        TableName: 'vben_menu_actions',
        Page: 1,
        PageSize: 100,
        SortBy: 'sort',
        SortOrder: 'asc',
        Where: {
          Logic: 'AND',
          Conditions: [{ Field: 'menu_id', Operator: 'eq', Value: menuid.value.trim() }],
          Groups: [],
        },
      },
    );
    menuButtons.value = res?.items ?? [];
  } catch {
    menuButtons.value = [];
  } finally {
    loadingMenuButtons.value = false;
  }
}

// 将菜单按钮转换为 ToolbarActionItem
function menuButtonToAction(btn: (typeof menuButtons.value)[0]): ToolbarActionItem {
  return {
    key: btn.action_key,
    label: btn.label ?? btn.action_key,
    type: (btn.button_type as any) || 'default',
    action: btn.action,
    confirm: btn.confirm_text || undefined,
    form_code: btn.form_code ?? undefined,
    requiresSelection: !!btn.requires_selection,
  };
}

// 选择菜单按钮添加到工具栏
function addSelectedMenuButton(btn: (typeof menuButtons.value)[0]) {
  if (toolbarActions.value.some((a) => a.key === btn.action_key)) {
    message.warning('该按钮已添加');
    return;
  }
  toolbarActions.value.push(menuButtonToAction(btn));
}

function removeToolbarAction(index: number) {
  toolbarActions.value.splice(index, 1);
}

function moveToolbarActionUp(index: number) {
  if (index <= 0) return;
  const list = toolbarActions.value;
  const tmp = list[index - 1];
  list[index - 1] = list[index];
  list[index] = tmp;
}

function moveToolbarActionDown(index: number) {
  const list = toolbarActions.value;
  if (index < 0 || index >= list.length - 1) return;
  const tmp = list[index + 1];
  list[index + 1] = list[index];
  list[index] = tmp;
}

watch(menuid, () => loadMenuButtons());

onMounted(() => {
  loadMenuList();
  // 从表结构设计器跳转时，URL 可能带 ?table=xxx
  const t = (route.query?.table as string) || '';
  if (t) {
    tableName.value = t;
    saveEntityName.value = t;
  }
});

// ==================== 字典树（查询项 Select 数据源） ====================
const dictionaryTreeData = ref<any[]>([]);
const DICT_ROOT = '00000000-0000-0000-0000-000000000000';
function normDictId(v: any): string {
  return String(v ?? DICT_ROOT).toLowerCase();
}
function buildDictTree(list: any[], parentId: string | null): any[] {
  const pid = normDictId(parentId ?? DICT_ROOT);
  return list
    .filter((x) => normDictId(x.parent_id ?? x.parentId) === pid)
    .sort((a, b) => (a.sort ?? 0) - (b.sort ?? 0))
    .map((x) => ({
      title: x.name || x.code || '未命名',
      value: x.id,
      key: x.id,
      children: buildDictTree(list, x.id),
    }));
}
async function loadDictionaryTree() {
  try {
    const res = await requestClient.post(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: 'vben_t_base_dictionary',
      Page: 1,
      PageSize: 5000,
      SortBy: 'sort',
      SortOrder: 'asc',
    });
    const raw = res?.data ?? res;
    const list = raw?.items ?? raw?.records ?? [];
    dictionaryTreeData.value = buildDictTree(list, null);
  } catch {
    dictionaryTreeData.value = [];
  }
}
function ensureSelectComponentProps(item: FormSchemaItem) {
  if (!item.componentProps) item.componentProps = {};
  if (item.componentProps.dataSourceType === undefined) item.componentProps.dataSourceType = 'manual';
}
function optionsToText(opts: Array<{ label?: string; value?: any }>): string {
  if (!opts?.length) return '';
  return opts
    .map((o) => {
      const v = o.value ?? o.label ?? '';
      const l = o.label ?? o.value ?? '';
      return l === v ? String(v) : `${l},${v}`;
    })
    .join('\n');
}
function textToOptions(text: string): Array<{ label: string; value: string }> {
  if (!text?.trim()) return [];
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const idx = line.indexOf(',');
      if (idx < 0) return { label: line, value: line };
      return {
        label: line.slice(0, idx).trim(),
        value: line.slice(idx + 1).trim(),
      };
    });
}

// ==================== 模板加载 ====================
function loadTemplate(name: 'company' | 'employee') {
  const schema = name === 'company' ? companySchema : employeeSchema;
  code.value = name === 'company' ? 'company_list' : 'employee_list';
  menuid.value = ''; // 模板无菜单ID
  title.value = schema.title;
  tableName.value = schema.tableName;
  primaryKey.value = schema.primaryKey ?? 'FID';
  saveEntityName.value = schema.saveEntityName ?? '';
  deleteEntityName.value = schema.deleteEntityName ?? '';
  actionModule.value = schema.actionModule ?? '';

  const formSchema = schema.form?.schema ?? [];
  formSchemaList.value = formSchema.map((s: any) => ({
    component: s.component ?? 'Input',
    fieldName: s.fieldName ?? '',
    label: s.label ?? '',
    componentProps: s.componentProps ? { ...s.componentProps } : undefined,
  }));
  formCollapsed.value = schema.form?.collapsed ?? false;
  formSubmitOnChange.value = schema.form?.submitOnChange ?? true;

  const cols = schema.grid?.columns ?? [];
  gridColumns.value = cols.map((c: any) => {
    if (c.type) return { type: c.type, width: c.width };
    return {
      field: c.field,
      title: c.title,
      width: c.width,
      minWidth: c.minWidth,
      sortable: c.sortable,
    };
  });
  gridPageSize.value = schema.grid?.pagerConfig?.pageSize ?? 10;
  const defaultSort = schema.grid?.sortConfig?.defaultSort;
  sortField.value = defaultSort?.field ?? '';
  sortOrder.value = defaultSort?.order ?? 'asc';

  toolbarActions.value = (schema.toolbar?.actions ?? []).map((a: any) => ({
    key: a.key,
    label: a.label,
    type: a.type,
    action: a.action,
    confirm: a.confirm,
    form_code: a.form_code ?? undefined,
    requiresSelection: !!a.requiresSelection,
  }));

  apiQuery.value = schema.api?.query ?? '';
  apiDelete.value = schema.api?.delete ?? '';
  apiExport.value = schema.api?.export ?? '';

  message.success(`已加载 ${name === 'company' ? '公司' : '人员'} 模板`);
}

// ==================== 从数据库加载已保存配置 ====================
interface SavedConfigItem {
  id: string;
  code: string;
  title: string;
  table_name?: string;
  schema_json: string;
}
const configSearchValue = ref('');
const savedConfigOptions = ref<Array<{ value: string; label: string; record: SavedConfigItem }>>([]);
const loadingConfigs = ref(false);

const savedConfigRawList = ref<SavedConfigItem[]>([]);

async function loadSavedConfigs(searchText = '', forceFetch = false) {
  if (!searchText || forceFetch) {
    loadingConfigs.value = true;
    try {
      const res = await requestClient.post<{ items: SavedConfigItem[]; total: number }>(
        backendApi('DynamicQueryBeta/queryforvben'),
        {
          TableName: 'vben_entitylist_desinger',
          Page: 1,
          PageSize: 100,
          SortBy: 'updated_at',
          SortOrder: 'desc',
        },
      );
      savedConfigRawList.value = res?.items ?? [];
    } catch {
      savedConfigRawList.value = [];
    } finally {
      loadingConfigs.value = false;
    }
  }
  const list = savedConfigRawList.value;
  const lower = searchText.toLowerCase().trim();
  const filtered = lower
    ? list.filter(
        (r) =>
          (r.code ?? '').toLowerCase().includes(lower) ||
          (r.title ?? '').toLowerCase().includes(lower),
      )
    : list;
  savedConfigOptions.value = filtered.map((r) => ({
    value: r.id,
    label: `${r.code || ''} - ${r.title || ''}`.trim() || r.id,
    record: r,
  }));
}

function onSelectSavedConfig(value: string) {
  const opt = savedConfigOptions.value.find((o) => o.value === value);
  if (!opt?.record?.schema_json) return;
  try {
    const parsed = JSON.parse(opt.record.schema_json) as QueryTableSchema & { _menuid?: string };
    savedId.value = opt.record.id;
    code.value = opt.record.code ?? '';
    menuid.value = (parsed as any)._menuid ?? '';
    title.value = parsed.title ?? '';
    tableName.value = parsed.tableName ?? '';
    primaryKey.value = parsed.primaryKey ?? 'FID';
    saveEntityName.value = parsed.saveEntityName ?? '';
    deleteEntityName.value = parsed.deleteEntityName ?? '';
    actionModule.value = parsed.actionModule ?? '';

    const formSchema = parsed.form?.schema ?? [];
    formSchemaList.value = formSchema.map((s: any) => ({
      component: s.component ?? 'Input',
      fieldName: s.fieldName ?? '',
      label: s.label ?? '',
      componentProps: s.componentProps ? { ...s.componentProps } : undefined,
    }));
    formCollapsed.value = parsed.form?.collapsed ?? false;
    formSubmitOnChange.value = parsed.form?.submitOnChange ?? true;

    const cols = parsed.grid?.columns ?? [];
    gridColumns.value = cols.map((c: any) => {
      if (c.type) return { type: c.type, width: c.width };
      return {
        field: c.field,
        title: c.title,
        width: c.width,
        minWidth: c.minWidth,
        sortable: c.sortable,
      };
    });
    gridPageSize.value = parsed.grid?.pagerConfig?.pageSize ?? 10;
    const defaultSort = parsed.grid?.sortConfig?.defaultSort;
    sortField.value = defaultSort?.field ?? '';
    sortOrder.value = defaultSort?.order ?? 'asc';

    toolbarActions.value = (parsed.toolbar?.actions ?? []).map((a: any) => ({
      key: a.key,
      label: a.label,
      type: a.type,
      action: a.action,
      confirm: a.confirm,
      form_code: a.form_code ?? undefined,
      requiresSelection: !!a.requiresSelection,
    }));

    apiQuery.value = parsed.api?.query ?? '';
    apiDelete.value = parsed.api?.delete ?? '';
    apiExport.value = parsed.api?.export ?? '';

    configSearchValue.value = `${opt.record.code || ''} - ${opt.record.title || ''}`.trim() || opt.record.code || '';
    message.success(`已加载配置：${opt.record.code || opt.record.title}`);
  } catch {
    message.error('解析配置失败');
  }
}

function onConfigSearch(val: string) {
  configSearchValue.value = val;
  loadSavedConfigs(val || '');
}

// ==================== JSON 导入导出 ====================
const jsonInput = ref('');
function exportJson() {
  jsonInput.value = JSON.stringify(designedSchema.value, null, 2);
  message.success('已导出到下方输入框');
}
function importJson() {
  try {
    const parsed = JSON.parse(jsonInput.value) as QueryTableSchema & { _menuid?: string };
    menuid.value = (parsed as any)._menuid ?? '';
    title.value = parsed.title ?? '';
    tableName.value = parsed.tableName ?? '';
    primaryKey.value = parsed.primaryKey ?? 'FID';
    saveEntityName.value = parsed.saveEntityName ?? '';
    deleteEntityName.value = parsed.deleteEntityName ?? '';
    actionModule.value = parsed.actionModule ?? '';

    const formSchema = parsed.form?.schema ?? [];
    formSchemaList.value = formSchema.map((s: any) => ({
      component: s.component ?? 'Input',
      fieldName: s.fieldName ?? '',
      label: s.label ?? '',
      componentProps: s.componentProps ? { ...s.componentProps } : undefined,
    }));
    formCollapsed.value = parsed.form?.collapsed ?? false;
    formSubmitOnChange.value = parsed.form?.submitOnChange ?? true;

    const cols = parsed.grid?.columns ?? [];
    gridColumns.value = cols.map((c: any) => {
      if (c.type) return { type: c.type, width: c.width };
      return {
        field: c.field,
        title: c.title,
        width: c.width,
        minWidth: c.minWidth,
        sortable: c.sortable,
      };
    });
    gridPageSize.value = parsed.grid?.pagerConfig?.pageSize ?? 10;
    const defaultSort = parsed.grid?.sortConfig?.defaultSort;
    sortField.value = defaultSort?.field ?? '';
    sortOrder.value = defaultSort?.order ?? 'asc';

    toolbarActions.value = (parsed.toolbar?.actions ?? []).map((a: any) => ({
      key: a.key,
      label: a.label,
      type: a.type,
      action: a.action,
      confirm: a.confirm,
      form_code: a.form_code ?? undefined,
      requiresSelection: !!a.requiresSelection,
    }));

    apiQuery.value = parsed.api?.query ?? '';
    apiDelete.value = parsed.api?.delete ?? '';
    apiExport.value = parsed.api?.export ?? '';

    message.success('导入成功');
  } catch {
    message.error('JSON 格式错误');
  }
}
function clearAll() {
  code.value = '';
  savedId.value = null;
  menuid.value = '';
  title.value = '列表标题';
  tableName.value = 't_base_table';
  primaryKey.value = 'FID';
  saveEntityName.value = '';
  deleteEntityName.value = '';
  actionModule.value = '/src/views/EntityList/company.ts';
  formSchemaList.value = [];
  formCollapsed.value = false;
  formSubmitOnChange.value = true;
  gridColumns.value = [];
  gridPageSize.value = 10;
  sortField.value = '';
  sortOrder.value = 'asc';
  toolbarActions.value = [];
  apiQuery.value = backendApi('DynamicQueryBeta/queryforvben');
  apiDelete.value = backendApi('DataBatchDelete/BatchDelete');
  apiExport.value = backendApi('DynamicQueryBeta/ExportExcel');
  jsonInput.value = '';
  message.info('已清空');
}

// ==================== 保存到数据库（使用通用 DataSave 接口） ====================
const saving = ref(false);
async function saveToDb() {
  if (!code.value?.trim()) {
    message.warning('请填写编码 (code)');
    return;
  }
  saving.value = true;
  try {
    const rowId = savedId.value || crypto.randomUUID();
    const row: Record<string, any> = {
      id: rowId,
      code: code.value.trim(),
      title: title.value,
      table_name: tableName.value,
      schema_json: JSON.stringify(designedSchema.value),
      updated_at: new Date().toISOString().slice(0, 19).replace('T', ' '),
    };
    if (!savedId.value) {
      row.created_at = row.updated_at;
    }
    await requestClient.post<any>(backendApi('DataSave/datasave-multi'), {
      tables: [
        {
          tableName: 'vben_entitylist_desinger',
          primaryKey: 'id',
          data: [row],
          deleteRows: [],
        },
      ],
    });
    savedId.value = rowId;
    message.success('保存成功');
  } catch (e: any) {
    message.error(e?.message || '保存失败');
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <Page>
    <div class="list-designer flex flex-col gap-2 p-4">
      <!-- 配置 + 实时预览：撑满屏幕高度，底部对齐 -->
      <div class="list-designer-main flex h-[calc(100vh-7rem)] shrink-0 items-stretch gap-4">
        <!-- 左侧配置区：固定宽度，内部 Tabs + 滚动 -->
        <Card class="flex h-full min-h-0 w-80 shrink-0 flex-col overflow-hidden" size="small">
          <template #title>
            <div class="flex flex-wrap items-center gap-2">
              <span>配置</span>
              <AutoComplete
                v-model:value="configSearchValue"
                :options="savedConfigOptions"
                :loading="loadingConfigs"
                placeholder="搜索已保存配置"
                size="small"
                class="min-w-[140px] flex-1"
                allow-clear
                @search="onConfigSearch"
                @select="onSelectSavedConfig"
                @focus="loadSavedConfigs('', true)"
              />
              <Button size="small" @click="loadTemplate('company')">公司</Button>
              <Button size="small" @click="loadTemplate('employee')">人员</Button>
            </div>
          </template>
          <div class="flex min-h-0 flex-1 flex-col overflow-hidden">
          <Tabs class="list-designer-tabs flex-1 min-h-0 overflow-hidden" size="small" type="card">
            <Tabs.TabPane key="basic" tab="基础与查询">
              <div class="min-h-0 flex-1 overflow-y-auto pr-1">
                <!-- 基础配置 -->
                <div class="flex flex-col gap-2">
                  <div>
                    <div class="mb-1 text-xs">编码 (code) <span class="text-red-500">*</span></div>
                    <Input v-model:value="code" placeholder="如 company_list" size="small" />
                  </div>
                  <div>
                    <div class="mb-1 text-xs">所属菜单</div>
                    <Select
                      v-model:value="menuid"
                      :options="menuSelectOptions"
                      placeholder="选择菜单，用于加载该菜单下已定义的按钮"
                      size="small"
                      class="w-full"
                      allow-clear
                      show-search
                      :filter-option="(input: string, opt: any) => (opt?.label ?? '').toLowerCase().includes(input.toLowerCase())"
                      :loading="loadingMenuList"
                    />
                  </div>
                  <div>
                    <div class="mb-1 text-xs">列表标题</div>
                    <Input v-model:value="title" placeholder="列表标题" size="small" />
                  </div>
                  <div>
                    <div class="mb-1 text-xs">表名 (tableName)</div>
                    <div class="flex items-center gap-2">
                      <Input
                        v-model:value="tableName"
                        placeholder="t_base_company 或视图名"
                        size="small"
                        class="flex-1"
                        @blur="() => { if (!gridColumns.length && tableName.trim()) loadColumnsFromTable(); }"
                      />
                      <Button
                        type="primary"
                        size="small"
                        :loading="loadingTableColumns"
                        @click="loadColumnsFromTable"
                      >
                        从表结构加载列
                      </Button>
                    </div>
                    <div class="mt-0.5 text-xs text-muted-foreground">
                      填写表名后失焦或点击按钮，将自动带出「表格列」，只需修改列名即可
                    </div>
                  </div>
                  <div>
                    <div class="mb-1 text-xs">主键 (primaryKey)</div>
                    <Input v-model:value="primaryKey" placeholder="FID" size="small" />
                  </div>
                  <div>
                    <div class="mb-1 text-xs">保存实体 (saveEntityName)</div>
                    <Input v-model:value="saveEntityName" placeholder="可选" size="small" />
                  </div>
                  <div>
                    <div class="mb-1 text-xs">删除实体 (deleteEntityName)</div>
                    <Input v-model:value="deleteEntityName" placeholder="可选" size="small" />
                  </div>
                  <div>
                    <div class="mb-1 text-xs">Action 模块路径</div>
                    <Input v-model:value="actionModule" placeholder="/src/views/EntityList/company.ts" size="small" />
                  </div>
                </div>

                <!-- 查询表单配置：从表格列中选择 -->
                <div class="mt-3 border-t pt-3">
                  <div class="mb-2 flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <span class="text-xs">折叠</span>
                      <Select
                        v-model:value="formCollapsed"
                        :options="[{ label: '否', value: false }, { label: '是', value: true }]"
                        size="small"
                        class="w-16"
                      />
                      <span class="text-xs">变更即查</span>
                      <Select
                        v-model:value="formSubmitOnChange"
                        :options="[{ label: '否', value: false }, { label: '是', value: true }]"
                        size="small"
                        class="w-16"
                      />
                    </div>
                    <Button size="small" type="primary" @click="addFormField">+ 添加查询项</Button>
                  </div>
                  <div v-if="!queryColumnOptions.length" class="mb-2 rounded border border-dashed p-2 text-xs text-muted-foreground">
                    请先在「表格列」中配置数据列，再在此选择查询列
                  </div>
                  <div
                    v-for="(item, i) in formSchemaList"
                    :key="i"
                    class="mb-2 flex flex-col gap-2 rounded border p-2"
                  >
                    <div class="flex flex-wrap items-center gap-1">
                      <Select
                        :value="item.fieldName"
                        :options="queryColumnOptions"
                        size="small"
                        class="min-w-[140px]"
                        placeholder="选择列"
                        allow-clear
                        @update:value="(v: string) => onQueryColumnSelect(item, v ?? '')"
                      />
                      <Select
                        v-model:value="item.component"
                        :options="FORM_COMPONENT_OPTIONS"
                        size="small"
                        class="w-24"
                        placeholder="组件"
                        @change="() => item.component === 'Select' && ensureSelectComponentProps(item)"
                      />
                      <Input v-model:value="item.label" placeholder="标签" size="small" class="w-24" />
                      <Button danger size="small" @click="removeFormField(i)">×</Button>
                    </div>
                    <div v-if="item.component === 'Select'" class="ml-0 flex flex-col gap-1 border-t pt-2">
                      <div class="flex items-center gap-2">
                        <span class="text-xs text-muted-foreground">数据源：</span>
                        <Select
                          :value="item.componentProps?.dataSourceType ?? 'manual'"
                          :options="[
                            { label: '手动配置', value: 'manual' },
                            { label: '数据字典', value: 'dictionary' },
                          ]"
                          size="small"
                          class="w-28"
                          @update:value="(v: 'manual' | 'dictionary') => {
                            ensureSelectComponentProps(item);
                            item.componentProps!.dataSourceType = v;
                            if (v === 'manual') delete item.componentProps!.dictionaryId;
                            else delete item.componentProps!.options;
                          }"
                        />
                        <TreeSelect
                          v-if="item.componentProps?.dataSourceType === 'dictionary'"
                          :value="item.componentProps?.dictionaryId"
                          :tree-data="dictionaryTreeData"
                          placeholder="选择字典"
                          size="small"
                          class="min-w-[160px]"
                          allow-clear
                          tree-default-expand-all
                          @update:value="(v: string) => {
                            ensureSelectComponentProps(item);
                            item.componentProps!.dictionaryId = v || undefined;
                          }"
                          @focus="loadDictionaryTree"
                        />
                      </div>
                      <div v-if="item.componentProps?.dataSourceType !== 'dictionary'" class="flex flex-col gap-0.5">
                        <span class="text-xs text-muted-foreground">选项（每行 label,value）：</span>
                        <Input.TextArea
                          :value="optionsToText(item.componentProps?.options ?? [])"
                          :rows="2"
                          placeholder="男,male&#10;女,female"
                          size="small"
                          class="font-mono text-xs"
                          @update:value="(v: string) => {
                            ensureSelectComponentProps(item);
                            item.componentProps!.options = textToOptions(v ?? '');
                          }"
                        />
                      </div>
                      <div v-else class="text-xs text-muted-foreground">
                        运行时从字典明细加载
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </Tabs.TabPane>

            <Tabs.TabPane key="grid" tab="表格列">
              <div class="min-h-0 flex-1 overflow-y-auto pr-1">
                <div class="mb-2 flex flex-wrap gap-1">
                  <Button size="small" @click="addCheckboxColumn">复选框</Button>
                  <Button size="small" @click="addSeqColumn">序号</Button>
                  <Button size="small" type="primary" @click="addGridColumn">+ 数据列</Button>
                </div>
                <div v-for="(col, i) in gridColumns" :key="i" class="mb-2 rounded border p-2">
                  <div v-if="col.type" class="flex items-center justify-between">
                    <span class="text-sm">{{ col.type === 'checkbox' ? '复选框' : '序号' }}</span>
                    <Button danger size="small" @click="removeGridColumn(i)">×</Button>
                  </div>
                  <div v-else class="flex flex-wrap items-center gap-1">
                    <Input v-model:value="col.field" placeholder="字段" size="small" class="w-24" />
                    <Input v-model:value="col.title" placeholder="标题" size="small" class="w-24" />
                    <InputNumber v-model:value="col.width" placeholder="宽" size="small" class="w-16" :min="60" />
                    <Select
                      v-model:value="col.sortable"
                      :options="[{ label: '可排序', value: true }, { label: '否', value: false }]"
                      size="small"
                      class="w-20"
                      allow-clear
                    />
                    <Button danger size="small" @click="removeGridColumn(i)">×</Button>
                  </div>
                </div>
              </div>
            </Tabs.TabPane>

            <Tabs.TabPane key="toolbar" tab="工具栏">
              <div class="min-h-0 flex-1 overflow-y-auto pr-1">
                <div class="mb-2 text-xs text-muted-foreground">
                  从「基础与查询」选择所属菜单后，下方展示该菜单已定义的按钮，点击添加。删除/导出由列表内置。
                </div>
                <div v-if="!menuid" class="mb-2 rounded border border-dashed p-2 text-xs text-muted-foreground">
                  选择所属菜单后可添加更多按钮；
                </div>
                <div v-else class="mb-2 flex flex-wrap gap-1">
                  <span class="text-xs self-center">可选按钮：</span>
                  <Button
                    v-for="btn in menuButtons"
                    :key="btn.id"
                    size="small"
                    :type="toolbarActions.some((a) => a.key === btn.action_key) ? 'primary' : 'default'"
                    :disabled="toolbarActions.some((a) => a.key === btn.action_key)"
                    @click="addSelectedMenuButton(btn)"
                  >
                    {{ btn.label || btn.action_key }}
                  </Button>
                  <span v-if="loadingMenuButtons" class="text-xs">加载中...</span>
                  <span v-else-if="!menuButtons.length" class="text-xs text-muted-foreground">无按钮</span>
                </div>
                <div class="mb-1 flex items-center justify-between text-xs">
                  <span>已选按钮（可上下调整顺序）：</span>
                </div>
                <div v-for="(btn, i) in toolbarActions" :key="i" class="mb-2 flex flex-col gap-1 rounded border p-2">
                  <div class="flex items-center gap-1">
                    <span class="text-xs flex-1">
                      {{ btn.label || btn.key }}
                      <span class="text-[11px] text-muted-foreground">({{ btn.action }})</span>
                    </span>
                    <Button size="small" class="px-1" @click="moveToolbarActionUp(i)" :disabled="i === 0">
                      ↑
                    </Button>
                    <Button
                      size="small"
                      class="px-1"
                      @click="moveToolbarActionDown(i)"
                      :disabled="i === toolbarActions.length - 1"
                    >
                      ↓
                    </Button>
                    <Button danger size="small" @click="removeToolbarAction(i)">×</Button>
                  </div>
                  <div class="flex flex-wrap items-center gap-3 text-xs">
                    <span class="text-muted-foreground">
                      form_code:
                      <span class="ml-1 font-mono">
                        {{ btn.form_code || '（从菜单按钮继承）' }}
                      </span>
                    </span>
                    <span class="flex items-center gap-1">
                      <span class="text-muted-foreground">需勾选行:</span>
                      <span class="font-mono">
                        {{ btn.requiresSelection ? '是' : '否' }}
                      </span>
                    </span>
                  </div>
                </div>
              </div>
            </Tabs.TabPane>

            <Tabs.TabPane key="api" tab="分页与API">
              <div class="min-h-0 flex-1 overflow-y-auto pr-1">
                <div class="mb-3 flex flex-col gap-2">
                  <div>
                    <div class="mb-1 text-xs">每页条数</div>
                    <InputNumber v-model:value="gridPageSize" :min="1" :max="100" size="small" class="w-full" />
                  </div>
                  <div>
                    <div class="mb-1 text-xs">默认排序字段</div>
                    <Input v-model:value="sortField" placeholder="field" size="small" />
                  </div>
                  <div>
                    <div class="mb-1 text-xs">默认排序方向</div>
                    <Select
                      v-model:value="sortOrder"
                      :options="[{ label: '升序', value: 'asc' }, { label: '降序', value: 'desc' }]"
                      size="small"
                      class="w-full"
                    />
                  </div>
                </div>
                <div class="mb-1 text-xs font-medium">API 地址</div>
                <div class="flex flex-col gap-2">
                  <div>
                    <div class="mb-1 text-xs">查询</div>
                    <Input v-model:value="apiQuery" size="small" />
                  </div>
                  <div>
                    <div class="mb-1 text-xs">删除</div>
                    <Input v-model:value="apiDelete" size="small" />
                  </div>
                  <div>
                    <div class="mb-1 text-xs">导出</div>
                    <Input v-model:value="apiExport" size="small" />
                  </div>
                </div>
              </div>
            </Tabs.TabPane>
          </Tabs>
          <!-- 左侧区域底部：三个按钮横向排列 -->
          <div class="mt-auto flex shrink-0 flex-wrap gap-2 border-t pt-2">
            <Button size="small" type="primary" :loading="saving" @click="saveToDb">保存到数据库</Button>
            <Button size="small" @click="exportJson">导出 JSON</Button>
            <Button danger size="small" @click="clearAll">清空</Button>
          </div>
          </div>
        </Card>

        <!-- 右侧预览 -->
        <Card class="flex h-full min-h-0 min-w-[600px] flex-1 flex-col overflow-hidden" size="small">
          <template #title>
            <div class="flex items-center justify-between">
              <span>实时预览</span>
              <Button size="small" type="link" @click="refreshPreview">刷新</Button>
            </div>
          </template>
          <div class="min-h-[400px] flex-1 rounded border border-dashed p-4">
            <QueryTable
              v-if="tableName && apiQuery"
              ref="queryTableRef"
              :key="previewSchemaKey"
              :schema="designedSchema"
            />
            <div v-else class="flex h-[300px] items-center justify-center text-muted-foreground">
              请配置表名和查询 API 后预览
            </div>
          </div>
        </Card>
      </div>

      <!-- JSON 配置 -->
      <Card class="shrink-0" size="small" title="JSON 配置 (可导入/导出 schema)">
        <Input.TextArea
          v-model:value="jsonInput"
          :rows="8"
          placeholder="点击「导出 JSON」或粘贴已有 schema 后点击「导入 JSON」"
          class="font-mono text-xs"
        />
        <div class="mt-2 flex gap-2">
          <Button size="small" type="primary" @click="importJson">导入 JSON</Button>
          <Button size="small" @click="exportJson">导出 JSON</Button>
        </div>
      </Card>
    </div>
  </Page>
</template>

<style scoped>
.list-designer-main :deep(.ant-card-body) {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
  overflow: hidden;
}
.list-designer-tabs :deep(.ant-tabs-content) {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}
.list-designer-tabs :deep(.ant-tabs-tabpane) {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}
</style>
