<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { Page } from '@vben/common-ui';
import {
  AutoComplete,
  Button,
  Card,
  Input,
  InputNumber,
  message,
  Select,
  Switch,
  TreeSelect,
} from 'ant-design-vue';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { useVbenForm } from '#/adapter/form';

import FormTabsTablePreview from './FormTabsTablePreview.vue';
import type { TabTableConfig } from './FormTabsTablePreview.vue';
import { resolveDictionaryInSchema } from './resolveDictionarySchema';
import {
  createDefaultSchemaItem,
  FORM_COMPONENT_OPTIONS,
  type FormDesignerSchemaItem,
} from './form-designer.types';

const schemaList = ref<FormDesignerSchemaItem[]>([] as any);
const selectedIndex = ref<number>(-1);
const addCounter = ref(0);

const selectedItem = computed(() => {
  const i = selectedIndex.value;
  return i >= 0 && i < schemaList.value.length ? schemaList.value[i] : null;
});

function addField(component: string, atIndex?: number) {
  addCounter.value += 1;
  const item = createDefaultSchemaItem(component, addCounter.value);
  const list = schemaList.value as any[];
  const idx = atIndex ?? list.length;
  list.splice(idx, 0, item);
  selectedIndex.value = idx;
  message.success(`已添加 ${component}`);
}

function handleDragStart(e: DragEvent, component: string) {
  e.dataTransfer!.setData('text/plain', component);
  e.dataTransfer!.effectAllowed = 'copy';
}

function handleDrop(e: DragEvent, dropIndex?: number) {
  e.preventDefault();
  e.stopPropagation();
  isDragOver.value = false;
  dropInsertIndex.value = -1;
  const component = e.dataTransfer?.getData('text/plain');
  if (!component) return;
  const list = schemaList.value as any[];
  const idx = dropIndex ?? list.length;
  addField(component, idx);
}

function handleDragOver(e: DragEvent, insertIndex?: number) {
  e.preventDefault();
  e.dataTransfer!.dropEffect = 'copy';
  isDragOver.value = true;
  dropInsertIndex.value = insertIndex ?? schemaList.value.length;
}

function handleDragLeave() {
  isDragOver.value = false;
  dropInsertIndex.value = -1;
}

const isDragOver = ref(false);
const dropInsertIndex = ref(-1);

const canvasGridClass = computed(() => {
  const cols = layoutConfig.value.cols;
  return `grid gap-2 ${cols === 1 ? 'grid-cols-1' : cols === 2 ? 'grid-cols-2' : cols === 3 ? 'grid-cols-3' : 'grid-cols-4'}`;
});

function removeField(index: number) {
  schemaList.value.splice(index, 1);
  if (selectedIndex.value >= schemaList.value.length) {
    selectedIndex.value = schemaList.value.length - 1;
  } else if (selectedIndex.value >= index && selectedIndex.value > 0) {
    selectedIndex.value -= 1;
  }
}

function moveUp(index: number) {
  if (index <= 0) return;
  const list = schemaList.value;
  const a = list[index - 1];
  const b = list[index];
  if (a && b) {
    list[index - 1] = b;
    list[index] = a;
    selectedIndex.value = index - 1;
  }
}

function moveDown(index: number) {
  if (index >= schemaList.value.length - 1) return;
  const list = schemaList.value;
  const a = list[index];
  const b = list[index + 1];
  if (a && b) {
    list[index] = b;
    list[index + 1] = a;
    selectedIndex.value = index + 1;
  }
}

function updateSelectedField(updates: Partial<FormDesignerSchemaItem>) {
  const i = selectedIndex.value;
  if (i >= 0 && i < schemaList.value.length) {
    (schemaList.value as any[])[i] = {
      ...schemaList.value[i],
      ...updates,
    };
  }
}

// 保存配置（存库用）
const formCode = ref('');
const formTitle = ref('');
const formListCode = ref('');
const formSavedId = ref<string | null>(null);

// 已保存表单配置（下拉选择）
interface SavedFormRecord {
  id: string;
  code?: string;
  title?: string;
  schema_json?: string;
  list_code?: string;
}
const savedFormConfigs = ref<SavedFormRecord[]>([]);
const savedFormOptions = ref<{ value: string; label: string; record?: SavedFormRecord }[]>([]);
const configSearchValue = ref('');
const loadingFormConfigs = ref(false);

async function loadSavedFormConfigs(keyword: string, force = false) {
  if (!force && savedFormConfigs.value.length > 0 && !keyword) {
    filterFormOptions(keyword);
    return;
  }
  loadingFormConfigs.value = true;
  try {
    const res = await requestClient.post<{ items: SavedFormRecord[]; total?: number }>(
      backendApi('DynamicQueryBeta/queryforvben'),
      {
        TableName: 'vben_form_desinger',
        Page: 1,
        PageSize: 100,
        SortBy: 'updated_at',
        SortOrder: 'desc',
      },
    );
    savedFormConfigs.value = res?.items ?? [];
    filterFormOptions(keyword);
  } catch {
    savedFormConfigs.value = [];
    savedFormOptions.value = [];
  } finally {
    loadingFormConfigs.value = false;
  }
}

function filterFormOptions(keyword: string) {
  const k = (keyword ?? '').toLowerCase().trim();
  const list = k
    ? savedFormConfigs.value.filter(
        (r) =>
          (r.code ?? '').toLowerCase().includes(k) ||
          (r.title ?? '').toLowerCase().includes(k),
      )
    : savedFormConfigs.value;
  savedFormOptions.value = list.map((r) => ({
    value: `${r.code ?? ''} - ${r.title ?? ''}`,
    label: `${r.code ?? ''} - ${r.title ?? ''}`,
    record: r,
  }));
}

function onSelectSavedForm(value: string) {
  const opt = savedFormOptions.value.find((o) => o.value === value);
  const rec = opt?.record;
  if (!rec?.schema_json) return;
  try {
    const parsed = JSON.parse(rec.schema_json) as {
      layout?: { cols?: number; layoutType?: string; layout?: string; labelAlign?: string; labelWidth?: number };
      schema?: any[];
      tabs?: TabTableConfig[];
    };
    formSavedId.value = rec.id;
    formCode.value = rec.code ?? '';
    formTitle.value = rec.title ?? '';
    formListCode.value = rec.list_code ?? '';
    if (parsed.layout) {
      layoutConfig.value = {
        ...layoutConfig.value,
        cols: parsed.layout.cols ?? 2,
        layout: (parsed.layout.layout as any) ?? 'horizontal',
        labelAlign: (parsed.layout.labelAlign as any) ?? 'right',
        labelWidth: parsed.layout.labelWidth ?? 100,
        layoutType: (parsed.layout.layoutType as any) ?? 'form',
      };
    }
    if (Array.isArray(parsed.schema)) {
      schemaList.value = parsed.schema.map((s: any) => ({
        fieldName: s.fieldName ?? `field_${Date.now()}`,
        label: s.label ?? '',
        component: s.component ?? 'Input',
        componentProps: s.componentProps ?? {},
        rules: s.rules,
        formItemClass: s.formItemClass,
        defaultValue: s.defaultValue,
      }));
    }
    if (Array.isArray(parsed.tabs)) {
      tabsList.value = parsed.tabs;
    }
    selectedIndex.value = -1;
    message.success('已加载');
  } catch {
    message.error('解析配置失败');
  }
}

// 全局布局配置
const layoutConfig = ref({
  cols: 2,
  layout: 'horizontal' as 'horizontal' | 'vertical' | 'inline',
  labelAlign: 'right' as 'left' | 'right',
  labelWidth: 100,
  layoutType: 'form' as 'form' | 'formTabsTable',
});

// 表单+页签+表格 配置
const tabsList = ref<TabTableConfig[]>([]);
const selectedTabIndex = ref(-1);
let tabCounter = 0;

function addTab() {
  tabCounter += 1;
  tabsList.value.push({
    key: `tab_${tabCounter}`,
    tab: `页签${tabCounter}`,
    columns: [
      { field: 'name', title: '名称', editType: 'input' },
      { field: 'value', title: '值', editType: 'input' },
    ],
  });
  selectedTabIndex.value = tabsList.value.length - 1;
  message.success('已添加页签');
}

function removeTab(index: number) {
  tabsList.value.splice(index, 1);
  if (selectedTabIndex.value >= tabsList.value.length) selectedTabIndex.value = tabsList.value.length - 1;
}

function addColumn(tabIndex: number) {
  const tab = tabsList.value[tabIndex];
  if (!tab) return;
  const idx = (tab.columns?.length ?? 0) + 1;
  tab.columns = tab.columns ?? [];
  tab.columns.push({
    field: `col_${idx}`,
    title: `列${idx}`,
    editType: 'input',
  });
}

function removeColumn(tabIndex: number, colIndex: number) {
  tabsList.value[tabIndex]?.columns?.splice(colIndex, 1);
}

const wrapperClassMap: Record<number, string> = {
  1: 'grid-cols-1',
  2: 'grid-cols-1 md:grid-cols-2',
  3: 'grid-cols-1 md:grid-cols-2 lg:grid-cols-3',
  4: 'grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4',
};

// 需要 options 的组件类型
const COMPONENTS_WITH_OPTIONS = [
  'Select',
  'RadioGroup',
  'CheckboxGroup',
  'AutoComplete',
  'Cascader',
];
// TreeSelect 使用 treeData
const COMPONENTS_WITH_TREEDATA = ['TreeSelect'];
// 支持数据源配置的组件（可选手动填写或数据字典）
const COMPONENTS_WITH_DATASOURCE = [...COMPONENTS_WITH_OPTIONS, ...COMPONENTS_WITH_TREEDATA];

// 属性编辑：fieldName, label, rules, formItemClass, options
const editFieldName = ref('');
const editLabel = ref('');
const editRules = ref('');
const editPlaceholder = ref('');
const editFormItemClass = ref('');
const editOptions = ref(''); // 格式：每行 "label,value" 或 "value"（label=value）
/** 数据源类型：manual=手动配置，dictionary=数据字典 */
const editDataSourceType = ref<'manual' | 'dictionary'>('manual');
/** 数据字典 ID（当 dataSourceType=dictionary 时使用） */
const editDictionaryId = ref<string>('');
/** 字典树数据（用于选择字典分类） */
const dictionaryTreeData = ref<any[]>([]);
/** 界面上不显示（如主键 ID，保存时仍会提交） */
const editHidden = ref(false);
/** 仅展示不保存（页面上显示，保存时不提交） */
const editExcludeFromSubmit = ref(false);

const selectedComponentNeedsOptions = computed(() => {
  const comp = selectedItem.value?.component as string;
  return comp && COMPONENTS_WITH_OPTIONS.includes(comp);
});

const selectedComponentNeedsTreeData = computed(() => {
  const comp = selectedItem.value?.component as string;
  return comp && COMPONENTS_WITH_TREEDATA.includes(comp);
});

/** 支持数据源配置（手动/数据字典）的组件 */
const selectedComponentNeedsDataSource = computed(() => {
  const comp = selectedItem.value?.component as string;
  return comp && COMPONENTS_WITH_DATASOURCE.includes(comp);
});

function optionsToText(opts: Array<{ label?: string; value: any }>): string {
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

function textToTreeData(text: string): Array<{ title: string; value: string; key: string }> {
  const opts = textToOptions(text);
  return opts.map((o) => ({ title: o.label, value: o.value, key: o.value }));
}

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
function toTreeSelectOptions(nodes: any[]): any[] {
  return nodes.map((n) => ({
    ...n,
    children: n.children?.length ? toTreeSelectOptions(n.children) : undefined,
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
    const tree = buildDictTree(list, null);
    dictionaryTreeData.value = toTreeSelectOptions(tree);
  } catch {
    dictionaryTreeData.value = [];
  }
}

const formItemClassOptions = [
  { label: '默认 (1列)', value: '' },
  { label: '占 2 列', value: 'md:col-span-2' },
  { label: '占 3 列', value: 'md:col-span-3' },
  { label: '占满整行', value: 'col-span-full' },
];

watch(
  selectedItem,
  (item) => {
    if (item) {
      editFieldName.value = item.fieldName ?? '';
      editLabel.value = (item.label as string) ?? '';
      editRules.value = typeof item.rules === 'string' ? item.rules : '';
      editPlaceholder.value = (item.componentProps as any)?.placeholder ?? '';
      editFormItemClass.value = (item.formItemClass as string) ?? '';
      const cp = item.componentProps as any;
      editDataSourceType.value = cp?.dataSourceType === 'dictionary' ? 'dictionary' : 'manual';
      editDictionaryId.value = cp?.dictionaryId ?? '';
      const opts = cp?.options;
      const treeData = cp?.treeData;
      if (Array.isArray(opts)) {
        editOptions.value = optionsToText(opts);
      } else if (Array.isArray(treeData)) {
        editOptions.value = treeData
          .map((t: any) => (t.title === t.value ? t.title : `${t.title},${t.value}`))
          .join('\n');
      } else {
        editOptions.value = '';
      }
      editHidden.value = cp?.type === 'hidden';
      editExcludeFromSubmit.value = !!(item as any).excludeFromSubmit;
    } else {
      editFieldName.value = '';
      editLabel.value = '';
      editRules.value = '';
      editPlaceholder.value = '';
      editFormItemClass.value = '';
      editOptions.value = '';
      editDataSourceType.value = 'manual';
      editDictionaryId.value = '';
      editHidden.value = false;
      editExcludeFromSubmit.value = false;
    }
  },
  { immediate: true },
);

watch(
  [
    editFieldName,
    editLabel,
    editRules,
    editPlaceholder,
    editFormItemClass,
    editOptions,
    editDataSourceType,
    editDictionaryId,
    editHidden,
    editExcludeFromSubmit,
  ],
  () => {
    if (!selectedItem.value) return;
    const compProps: Record<string, any> = {
      ...(selectedItem.value.componentProps ?? {}),
      placeholder: editPlaceholder.value || undefined,
    };
    const baseUpdates: any = {
      fieldName: editFieldName.value,
      label: editLabel.value,
      rules: editRules.value || undefined,
      formItemClass: editFormItemClass.value || undefined,
      excludeFromSubmit: editExcludeFromSubmit.value,
    };
    if (editHidden.value) {
      compProps.type = 'hidden';
      updateSelectedField({
        ...baseUpdates,
        hideLabel: true,
        component: 'Input',
        componentProps: compProps,
      });
    } else {
      delete compProps.type;
      if (selectedComponentNeedsDataSource.value) {
        compProps.dataSourceType = editDataSourceType.value;
        if (editDataSourceType.value === 'dictionary' && editDictionaryId.value) {
          compProps.dictionaryId = editDictionaryId.value;
          delete compProps.options;
          delete compProps.treeData;
          // 运行时由 resolveDictionaryInSchema 填充
        } else {
          delete compProps.dictionaryId;
          if (selectedComponentNeedsOptions.value) {
            compProps.options = textToOptions(editOptions.value);
          }
          if (selectedComponentNeedsTreeData.value) {
            compProps.treeData = textToTreeData(editOptions.value);
          }
        }
      }
      updateSelectedField({
        ...baseUpdates,
        hideLabel: false,
        componentProps: compProps,
      });
    }
  },
  { deep: true },
);

// JSON 导入导出（含布局配置、页签表格）
const jsonInput = ref('');
function exportJson() {
  const payload = {
    layout: layoutConfig.value,
    schema: schemaList.value,
    tabs: layoutConfig.value.layoutType === 'formTabsTable' ? tabsList.value : undefined,
  };
  jsonInput.value = JSON.stringify(payload, null, 2);
  message.success('已复制到下方输入框');
}

function importJson() {
  try {
    const parsed = JSON.parse(jsonInput.value);
    let arr: any[] = [];
    let layout: any = null;
    // 支持多种格式
    if (parsed?.schema && Array.isArray(parsed.schema)) {
      arr = parsed.schema;
      layout = parsed.layout;
    } else if (Array.isArray(parsed)) {
      const formLayout = parsed.find((p: any) => p?.type === 'form');
      arr = formLayout?.schema ?? parsed;
      if (formLayout?.cols) layout = { ...layoutConfig.value, cols: formLayout.cols };
    } else if (parsed?.type === 'form' && Array.isArray(parsed.schema)) {
      arr = parsed.schema;
      if (parsed.cols) layout = { ...layoutConfig.value, cols: parsed.cols };
    } else {
      arr = [parsed];
    }
    schemaList.value = arr.map((item: any) => ({
      fieldName: item.fieldName ?? `field_${Date.now()}`,
      label: item.label ?? '未命名',
      component: item.component ?? 'Input',
      componentProps: item.componentProps ?? {},
      rules: item.rules,
      defaultValue: item.defaultValue,
      formItemClass: item.formItemClass,
      hideLabel: item.componentProps?.type === 'hidden' ? true : item.hideLabel,
      excludeFromSubmit: item.excludeFromSubmit,
    }));
    if (layout && typeof layout === 'object') {
      layoutConfig.value = { ...layoutConfig.value, ...layout };
    }
    if (parsed?.tabs && Array.isArray(parsed.tabs)) {
      tabsList.value = parsed.tabs.map((t: any) => ({
        key: t.key ?? `tab_${Date.now()}`,
        tab: t.tab ?? '未命名',
        columns: (t.columns ?? []).map((c: any) => ({
          field: c.field ?? 'field',
          title: c.title ?? '列',
          editType: c.editType ?? 'input',
          options: c.options,
          rules: c.rules,
        })),
      }));
    }
    selectedIndex.value = -1;
    message.success('导入成功');
  } catch (e) {
    message.error('JSON 格式错误');
  }
}

function clearAll() {
  schemaList.value = [];
  selectedIndex.value = -1;
  tabsList.value = [];
  jsonInput.value = '';
  message.info('已清空');
}

// 保存到数据库 vben_form_desinger
const saving = ref(false);
function getFormSchemaPayload() {
  return {
    layout: layoutConfig.value,
    schema: schemaList.value,
    tabs: layoutConfig.value.layoutType === 'formTabsTable' ? tabsList.value : undefined,
  };
}

async function saveToDb() {
  if (!formCode.value?.trim()) {
    message.warning('请填写表单编码 (code)');
    return;
  }
  saving.value = true;
  try {
    const payload = getFormSchemaPayload();
    const rowId = formSavedId.value || crypto.randomUUID();
    const row: Record<string, any> = {
      id: rowId,
      code: formCode.value.trim(),
      title: formTitle.value.trim() || '',
      schema_json: JSON.stringify(payload),
      list_code: formListCode.value.trim() || '',
      updated_at: new Date().toISOString().slice(0, 19).replace('T', ' '),
    };
    if (!formSavedId.value) {
      row.created_at = row.updated_at;
    }
    await requestClient.post<any>(backendApi('DataSave/datasave-multi'), {
      tables: [
        {
          tableName: 'vben_form_desinger',
          primaryKey: 'id',
          data: [row],
          deleteRows: [],
        },
      ],
    });
    formSavedId.value = rowId;
    message.success('保存成功');
    loadSavedFormConfigs(''); // 刷新下拉选项
  } catch (e: any) {
    message.error(e?.message || e?.data?.message || '保存失败');
  } finally {
    saving.value = false;
  }
}

// 预览表单 - schema 和布局变化时通过 setState 更新
const [PreviewForm, formApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as any[],
  wrapperClass: 'grid-cols-1 md:grid-cols-2',
  layout: 'horizontal',
  commonConfig: { labelWidth: 100 } as any,
});

// 预览表单：解析数据字典后更新 schema
const resolvedPreviewSchema = ref<any[]>([]);
watch(
  schemaList,
  async (list) => {
    const hasDict = (list || []).some(
      (s: any) => (s?.componentProps?.dataSourceType === 'dictionary' && s?.componentProps?.dictionaryId),
    );
    if (hasDict) {
      resolvedPreviewSchema.value = await resolveDictionaryInSchema([...(list || [])]);
    } else {
      resolvedPreviewSchema.value = [...(list || [])];
    }
    formApi.setState({ schema: resolvedPreviewSchema.value as any });
  },
  { immediate: true, deep: true },
);

watch(
  layoutConfig,
  (cfg) => {
    formApi.setState({
      wrapperClass: wrapperClassMap[cfg.cols] ?? wrapperClassMap[2],
      layout: cfg.layout,
      commonConfig: {
        labelAlign: cfg.labelAlign,
        labelWidth: cfg.labelWidth,
      } as any,
    });
  },
  { immediate: true, deep: true },
);

onMounted(() => {
  loadSavedFormConfigs('', true);
  loadDictionaryTree();
});
</script>

<template>
  <Page description="基于 VbenFormSchema 的可视化表单设计器，支持拖拽配置、JSON 导入导出" title="表单设计器">
  <div class="form-designer flex flex-col gap-4 p-4">
    <!-- 上排：三列布局 -->
    <div class="flex flex-1 gap-4">
      <!-- 左侧：组件面板 + 布局设置 -->
      <div class="flex w-56 shrink-0 flex-col gap-3">
        <Card size="small">
          <template #title>
            <div class="flex flex-wrap items-center gap-2">
              <span>布局设置</span>
              <AutoComplete
                v-model:value="configSearchValue"
                :options="savedFormOptions"
                :loading="loadingFormConfigs"
                placeholder="选择已保存配置"
                size="small"
                class="min-w-[120px] flex-1"
                allow-clear
                :filter-option="() => true"
                @search="(v) => filterFormOptions(String(v ?? ''))"
                @select="(val: any) => onSelectSavedForm(String(val ?? ''))"
                @focus="loadSavedFormConfigs('', true)"
              />
            </div>
          </template>
          <div class="flex flex-col gap-3">
            <div>
              <div class="mb-1 text-xs">表单编码 (code) <span class="text-red-500">*</span></div>
              <Input v-model:value="formCode" placeholder="如 company_add" size="small" />
            </div>
            <div>
              <div class="mb-1 text-xs">表单标题</div>
              <Input v-model:value="formTitle" placeholder="弹窗标题" size="small" />
            </div>
            <div>
              <div class="mb-1 text-xs">关联列表编码 (list_code)</div>
              <Input
                v-model:value="formListCode"
                placeholder="与列表设计器的 code 一致，用于新增按钮弹出此表单"
                size="small"
              />
            </div>
            <div>
              <div class="mb-1 text-xs">布局类型</div>
              <Select
                v-model:value="layoutConfig.layoutType"
                :options="[
                  { label: '纯表单', value: 'form' },
                  { label: '表单+页签+表格', value: 'formTabsTable' },
                ]"
                size="small"
                class="w-full"
              />
            </div>
            <div>
              <div class="mb-1 text-xs">栅格列数</div>
              <Select
                v-model:value="layoutConfig.cols"
                :options="[
                  { label: '1 列', value: 1 },
                  { label: '2 列', value: 2 },
                  { label: '3 列', value: 3 },
                  { label: '4 列', value: 4 },
                ]"
                size="small"
                class="w-full"
              />
            </div>
            <div>
              <div class="mb-1 text-xs">表单布局</div>
              <Select
                v-model:value="layoutConfig.layout"
                :options="[
                  { label: '水平 (horizontal)', value: 'horizontal' },
                  { label: '垂直 (vertical)', value: 'vertical' },
                  { label: '行内 (inline)', value: 'inline' },
                ]"
                size="small"
                class="w-full"
              />
            </div>
            <div>
              <div class="mb-1 text-xs">标签对齐</div>
              <Select
                v-model:value="layoutConfig.labelAlign"
                :options="[
                  { label: '左对齐', value: 'left' },
                  { label: '右对齐', value: 'right' },
                ]"
                size="small"
                class="w-full"
              />
            </div>
            <div>
              <div class="mb-1 text-xs">标签宽度</div>
              <InputNumber
                v-model:value="layoutConfig.labelWidth"
                :min="60"
                :max="300"
                size="small"
                class="w-full"
              />
            </div>
          </div>
        </Card>
        <Card title="组件库（可拖拽到表单区域）" size="small">
          <div class="flex flex-col gap-1">
            <div
              v-for="opt in FORM_COMPONENT_OPTIONS"
              :key="opt.component"
              draggable="true"
              class="cursor-grab active:cursor-grabbing rounded border border-transparent px-2 py-1 text-center hover:border-primary/50 hover:bg-primary/5"
              @click="addField(opt.component)"
              @dragstart="handleDragStart($event, opt.component)"
            >
              {{ opt.label }}
            </div>
          </div>
        </Card>
      </div>

      <!-- 中间：画布（栅格布局，支持拖拽放置） -->
      <Card class="min-w-72 flex-1" size="small">
        <template #title>
          <span>表单配置</span>
          <span class="ml-2 text-muted-foreground font-normal text-xs">
            {{ layoutConfig.cols }} 列
          </span>
        </template>
        <div
          :class="[
            'min-h-[200px] rounded border-2 transition-colors',
            isDragOver ? 'border-primary bg-primary/5' : 'border-dashed border-border',
          ]"
          @dragover="handleDragOver($event)"
          @dragleave="handleDragLeave"
          @drop="handleDrop($event)"
        >
          <!-- 空状态 -->
          <div
            v-if="schemaList.length === 0 && (layoutConfig.layoutType !== 'formTabsTable' || tabsList.length === 0)"
            class="flex h-[180px] items-center justify-center text-muted-foreground"
          >
            从左侧拖拽或点击组件添加到此处
          </div>

          <!-- 表单+页签+表格 模式：完整布局呈现在表单配置区 -->
          <div v-else class="flex flex-col gap-3 p-2">
            <!-- 1. 表单区域 -->
            <div v-if="schemaList.length > 0">
              <div
                v-if="layoutConfig.layoutType === 'formTabsTable'"
                class="mb-2 text-muted-foreground text-xs font-medium"
              >
                表单区域
              </div>
              <div :class="['grid gap-2', canvasGridClass]">
                <div
                  v-for="(item, index) in schemaList"
                  :key="item.fieldName"
                  :class="[
                    'flex min-h-[52px] cursor-pointer flex-col justify-center rounded border p-2 transition-all',
                    selectedIndex === index
                      ? 'border-primary bg-primary/5'
                      : 'border-border hover:border-primary/50',
                    dropInsertIndex === index ? 'ring-2 ring-primary ring-offset-1' : '',
                    item.formItemClass || '',
                  ]"
                  @click="selectedIndex = index"
                  @dragover="handleDragOver($event, index)"
                  @dragleave="handleDragLeave"
                  @drop.stop="handleDrop($event, index)"
                >
                  <div class="flex items-center gap-2">
                    <span class="w-6 shrink-0 text-muted-foreground">{{ index + 1 }}</span>
                    <span class="min-w-0 flex-1 truncate font-medium">
                      {{ item.label }}
                      <span v-if="(item.componentProps as any)?.type === 'hidden'" class="ml-1 text-muted-foreground">(隐藏)</span>
                      <span v-else-if="(item as any).excludeFromSubmit" class="ml-1 text-muted-foreground">(仅展示)</span>
                    </span>
                    <span class="shrink-0 text-muted-foreground text-xs">{{ item.component }}</span>
                    <div class="flex shrink-0 gap-1">
                      <Button size="small" @click.stop="moveUp(index)">↑</Button>
                      <Button size="small" @click.stop="moveDown(index)">↓</Button>
                      <Button danger size="small" @click.stop="removeField(index)">删</Button>
                    </div>
                  </div>
                  <div v-show="dropInsertIndex === index" class="mt-1 text-primary text-xs">
                    松开插入到此
                  </div>
                </div>
                <!-- 表单末尾追加区域 -->
                <div
                  :class="[
                    'col-span-full flex min-h-[52px] items-center justify-center rounded border-2 border-dashed transition-all',
                    dropInsertIndex === schemaList.length
                      ? 'border-primary bg-primary/10'
                      : 'border-transparent hover:border-primary/30',
                  ]"
                  @click.stop
                  @dragover="handleDragOver($event, schemaList.length)"
                  @dragleave="handleDragLeave"
                  @drop.stop="handleDrop($event, schemaList.length)"
                >
                  <span
                    :class="[
                      'text-xs',
                      dropInsertIndex === schemaList.length ? 'text-primary' : 'text-muted-foreground',
                    ]"
                  >
                    拖拽到此处追加表单字段
                  </span>
                </div>
              </div>
            </div>

            <!-- 空表单时提示添加（formTabsTable 模式） -->
            <div
              v-else-if="layoutConfig.layoutType === 'formTabsTable'"
              class="border-border flex min-h-[60px] items-center justify-center rounded border-2 border-dashed py-4 text-muted-foreground text-sm"
            >
              从左侧拖拽或点击组件添加表单字段
            </div>

            <!-- 2. 页签+表格区域（仅 formTabsTable 模式） -->
            <div v-if="layoutConfig.layoutType === 'formTabsTable'" class="border-border rounded border pt-2">
              <div class="mb-2 flex items-center justify-between px-2">
                <span class="text-muted-foreground text-xs font-medium">页签 + 表格</span>
                <Button size="small" type="primary" @click="addTab">+ 添加页签</Button>
              </div>
              <div v-if="tabsList.length === 0" class="border-border mx-2 mb-2 flex min-h-[60px] items-center justify-center rounded border-2 border-dashed py-4 text-muted-foreground text-sm">
                点击「添加页签」添加表格页签
              </div>
              <div v-else class="space-y-2 px-2 pb-2">
                <div
                  v-for="(tab, ti) in tabsList"
                  :key="tab.key"
                  :class="[
                    'rounded border p-2',
                    selectedTabIndex === ti ? 'border-primary bg-primary/5' : 'border-border',
                  ]"
                  @click="selectedTabIndex = ti"
                >
                  <div class="mb-2 flex items-center gap-2">
                    <Input v-model:value="tab.tab" placeholder="页签名" size="small" class="flex-1" />
                    <Input v-model:value="tab.key" placeholder="key" size="small" class="w-24" />
                    <Button danger size="small" @click.stop="removeTab(ti)">删</Button>
                  </div>
                  <div class="text-muted-foreground mb-1 text-xs">表格列</div>
                  <div
                    v-for="(col, ci) in tab.columns"
                    :key="ci"
                    class="mb-2 rounded border border-dashed p-2"
                  >
                    <div class="mb-1 flex flex-wrap items-center gap-1">
                      <Input v-model:value="col.field" placeholder="字段" size="small" class="w-20" />
                      <Input v-model:value="col.title" placeholder="标题" size="small" class="w-20" />
                      <Select
                        v-model:value="col.editType"
                        :options="[
                          { label: '输入框', value: 'input' },
                          { label: '数字', value: 'input-number' },
                          { label: '下拉', value: 'select' },
                          { label: '日期', value: 'date' },
                        ]"
                        placeholder="控件"
                        size="small"
                        class="w-20"
                        allow-clear
                      />
                      <Select
                        v-model:value="col.rules"
                        :options="[
                          { label: '无', value: '' },
                          { label: '必填', value: 'required' },
                        ]"
                        placeholder="校验"
                        size="small"
                        class="w-16"
                        allow-clear
                      />
                      <Button danger size="small" @click.stop="removeColumn(ti, ci)">×</Button>
                    </div>
                    <div v-if="col.editType === 'select'" class="mt-1">
                      <Input.TextArea
                        v-model:value="col.options"
                        :rows="2"
                        placeholder="下拉选项：每行 label,value"
                        size="small"
                        class="font-mono text-xs"
                      />
                    </div>
                  </div>
                  <Button size="small" class="mt-1" @click.stop="addColumn(ti)">+ 添加列</Button>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div class="mt-3 flex flex-wrap gap-2">
          <Button size="small" @click="exportJson">导出 JSON</Button>
          <Button size="small" type="primary" :loading="saving" @click="saveToDb">保存</Button>
          <Button danger size="small" @click="clearAll">清空</Button>
        </div>
      </Card>

      <!-- 右侧：属性面板 -->
      <Card class="w-64 shrink-0" title="属性配置" size="small">
        <div v-if="!selectedItem" class="text-muted-foreground text-sm">
          选中左侧字段进行配置
        </div>
        <div v-else class="flex flex-col gap-3">
          <div>
            <div class="mb-1 text-xs">字段名 (fieldName)</div>
            <Input v-model:value="editFieldName" placeholder="字段名" size="small" />
          </div>
          <div>
            <div class="mb-1 text-xs">标签 (label)</div>
            <Input v-model:value="editLabel" placeholder="标签" size="small" />
          </div>
          <div>
            <div class="mb-1 text-xs">占位符 (placeholder)</div>
            <Input
              v-model:value="editPlaceholder"
              placeholder="占位符"
              size="small"
            />
          </div>
          <template v-if="selectedComponentNeedsDataSource">
            <div>
              <div class="mb-1 text-xs">数据源类型</div>
              <Select
                v-model:value="editDataSourceType"
                :options="[
                  { label: '手动配置', value: 'manual' },
                  { label: '数据字典', value: 'dictionary' },
                ]"
                size="small"
                class="w-full"
              />
            </div>
            <div v-if="editDataSourceType === 'dictionary'">
              <div class="mb-1 text-xs">选择数据字典</div>
              <TreeSelect
                v-model:value="editDictionaryId"
                :tree-data="dictionaryTreeData"
                placeholder="请选择字典分类"
                size="small"
                class="w-full"
                allow-clear
                tree-default-expand-all
                @focus="loadDictionaryTree"
              />
              <div class="mt-1 text-muted-foreground text-xs">
                运行时从字典明细加载选项
              </div>
            </div>
            <div v-else>
              <div class="mb-1 text-xs">下拉选项 (options)</div>
              <Input.TextArea
                v-model:value="editOptions"
                :rows="4"
                placeholder="每行一项：label,value 或 仅value"
                size="small"
                class="font-mono text-xs"
              />
              <div class="mt-1 text-muted-foreground text-xs">
                例：男,male 或 选项A
              </div>
            </div>
          </template>
          <div>
            <div class="mb-1 text-xs">校验规则 (rules)</div>
            <Select
              v-model:value="editRules"
              :options="[
                { label: '必填 (required)', value: 'required' },
                { label: '选择必填 (selectRequired)', value: 'selectRequired' },
              ]"
              allow-clear
              placeholder="可选"
              size="small"
              class="w-full"
            />
          </div>
          <div>
            <div class="mb-1 text-xs">列宽 / 跨列 (formItemClass)</div>
            <Select
              v-model:value="editFormItemClass"
              :options="formItemClassOptions"
              allow-clear
              placeholder="默认"
              size="small"
              class="w-full"
            />
          </div>
          <div class="flex items-center justify-between">
            <div class="text-xs">界面上不显示</div>
            <Switch v-model:checked="editHidden" size="small" />
          </div>
          <div v-if="editHidden" class="text-muted-foreground text-xs">
            该字段保存时会提交，但不展示给用户（适合主键 ID 等）
          </div>
          <div class="flex items-center justify-between">
            <div class="text-xs">仅展示不保存</div>
            <Switch v-model:checked="editExcludeFromSubmit" size="small" />
          </div>
          <div v-if="editExcludeFromSubmit" class="text-muted-foreground text-xs">
            页面上显示，但保存时不会提交（适合说明、提示信息等）
          </div>
        </div>
      </Card>
    </div>

    <!-- 底部：预览 -->
    <Card title="实时预览" size="small">
      <div class="rounded border border-dashed p-4">
        <template v-if="layoutConfig.layoutType === 'formTabsTable'">
          <FormTabsTablePreview
            :form-schema="(schemaList as any)"
            :tabs="tabsList"
            :wrapper-class="wrapperClassMap[layoutConfig.cols]"
            :layout="layoutConfig.layout"
            :label-width="layoutConfig.labelWidth"
          />
        </template>
        <PreviewForm v-else />
      </div>
    </Card>

    <!-- JSON 配置 -->
    <Card title="JSON 配置 (可导入已有 schema)" size="small">
      <Input.TextArea
        v-model:value="jsonInput"
        :rows="6"
        placeholder="点击「导出 JSON」或粘贴已有 schema 后点击「导入 JSON」"
        class="font-mono text-xs"
      />
      <div class="mt-2 flex flex-wrap gap-2">
        <Button size="small" type="primary" @click="importJson">
          导入 JSON
        </Button>
        <Button size="small" @click="exportJson">导出 JSON</Button>
        <Button size="small" type="primary" :loading="saving" @click="saveToDb">保存</Button>
      </div>
    </Card>
  </div>
  </Page>
</template>
