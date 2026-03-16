<script setup lang="ts">
/**
 * 表单+页签+表格 预览组件
 * 支持：新增行、删除选中行、行内编辑
 */
import { ref, watch } from 'vue';
import { Button, Tabs, message } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import type { VbenFormSchema } from '#/adapter/form';
import { resolveDictionaryInSchema } from './resolveDictionarySchema';

export interface TabTableColumn {
  field: string;
  title: string;
  /** 控件类型：input/input-number/select/date */
  editType?: 'input' | 'input-number' | 'select' | 'date';
  /** 下拉选项（editType=select 时使用），格式：每行 label,value */
  options?: string;
  /** 校验：required 必填 */
  rules?: string;
}

export interface TabTableConfig {
  key: string;
  tab: string;
  columns: TabTableColumn[];
}

const props = defineProps<{
  formSchema: VbenFormSchema[];
  tabs: TabTableConfig[];
  wrapperClass?: string;
  layout?: string;
  labelWidth?: number;
}>();

const activeKey = ref(props.tabs[0]?.key ?? '');
const tabDataMap = ref<Record<string, any[]>>({});

// 为每个 tab 初始化空数据
watch(
  () => props.tabs,
  (tabs) => {
    const map: Record<string, any[]> = {};
    tabs.forEach((t) => {
      map[t.key] = tabDataMap.value[t.key] ?? [];
    });
    tabDataMap.value = map;
    if (tabs.length && !activeKey.value) activeKey.value = tabs[0].key;
  },
  { immediate: true },
);

// 解析 options 字符串为 [{label,value}]
function parseOptions(text: string): Array<{ label: string; value: string }> {
  if (!text?.trim()) return [];
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const idx = line.indexOf(',');
      if (idx < 0) return { label: line, value: line };
      return { label: line.slice(0, idx).trim(), value: line.slice(idx + 1).trim() };
    });
}

// 根据 columns 生成 gridOptions
function buildGridOptions(tab: TabTableConfig, data: any[]) {
  const baseColumns = [
    { type: 'checkbox', width: 50 },
    { type: 'seq', width: 50 },
  ];
  const dataColumns = (tab.columns || []).map((col) => {
    const editType = col.editType ?? 'input';
    let editRender: Record<string, any> = { name: 'input' };
    if (editType === 'input-number') {
      editRender = { name: 'input', attrs: { type: 'number' } };
    } else if (editType === 'select') {
      const opts = parseOptions(col.options ?? '');
      editRender = { name: 'select', options: opts };
    } else if (editType === 'date') {
      editRender = { name: 'input', attrs: { type: 'date' } };
    } else {
      editRender = { name: 'input' };
    }
    const colDef: Record<string, any> = {
      field: col.field,
      title: col.title,
      width: 120,
      editRender,
    };
    // 校验规则
    if (col.rules?.includes('required')) {
      colDef.editRule = [{ required: true, message: `${col.title}不能为空` }];
    }
    return colDef;
  });
  return {
    data,
    columns: [...baseColumns, ...dataColumns],
    rowConfig: { keyField: 'id' },
    checkboxConfig: { checkRowKeys: [] },
    height: 280,
    editConfig: {
      trigger: 'click',
      mode: 'row',
      enabled: true,
      showStatus: true,
    },
    pagerConfig: { enabled: false },
  };
}

const currentTab = ref<TabTableConfig | null>(null);
const currentData = ref<any[]>([]);

watch(
  [activeKey, () => props.tabs],
  () => {
    const tab = props.tabs.find((t) => t.key === activeKey.value);
    currentTab.value = tab ?? null;
    currentData.value = tab ? [...(tabDataMap.value[tab.key] ?? [])] : [];
  },
  { immediate: true },
);

const [Form, formApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as any[],
  wrapperClass: props.wrapperClass ?? 'grid-cols-1 md:grid-cols-2',
  layout: (props.layout as any) ?? 'horizontal',
  commonConfig: { labelWidth: props.labelWidth ?? 100 } as any,
});

watch(
  () => props.formSchema,
  async (schema) => {
    const raw = schema ? [...schema] : [];
    const resolved = await resolveDictionaryInSchema(raw);
    formApi.setState({ schema: resolved });
  },
  { immediate: true, deep: true },
);

const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    data: [],
    columns: [],
  },
});

watch(
  [currentTab, currentData],
  () => {
    if (!currentTab.value) return;
    const opts = buildGridOptions(currentTab.value, currentData.value);
    gridApi.setState({ gridOptions: opts });
  },
  { immediate: true, deep: true },
);

function addRow() {
  if (!currentTab.value) return;
  const tab = currentTab.value;
  const newRow: Record<string, any> = { id: Date.now() };
  tab.columns.forEach((col) => {
    if (col.editType === 'input-number') newRow[col.field] = 0;
    else if (col.editType === 'date') newRow[col.field] = '';
    else newRow[col.field] = '';
  });
  const data = tabDataMap.value[tab.key] ?? [];
  data.push(newRow);
  tabDataMap.value = { ...tabDataMap.value, [tab.key]: data };
  currentData.value = [...data];
  gridApi.setState({ gridOptions: { ...buildGridOptions(tab, data) } });
  message.success('已新增一行');
}

function deleteRows() {
  if (!currentTab.value) return;
  const rows = gridApi.grid?.getCheckboxRecords?.() ?? [];
  if (!rows.length) {
    message.warning('请先勾选要删除的行');
    return;
  }
  const tab = currentTab.value;
  const data = (tabDataMap.value[tab.key] ?? []).filter(
    (r) => !rows.some((row: any) => row.id === r.id),
  );
  tabDataMap.value = { ...tabDataMap.value, [tab.key]: data };
  currentData.value = [...data];
  gridApi.setState({ gridOptions: { ...buildGridOptions(tab, data) } });
  gridApi.grid?.clearCheckboxRow?.();
  message.success('已删除');
}
</script>

<template>
  <div class="form-tabs-table-preview">
    <div v-if="formSchema.length" class="mb-4">
      <Form />
    </div>
    <div v-if="tabs.length" class="mt-4">
      <Tabs v-model:activeKey="activeKey" type="card">
        <Tabs.TabPane v-for="tab in tabs" :key="tab.key" :tab="tab.tab">
          <div class="py-2">
            <div class="mb-2 flex gap-2">
              <Button size="small" type="primary" @click="addRow">新增</Button>
              <Button size="small" danger @click="deleteRows">删除</Button>
            </div>
            <Grid />
          </div>
        </Tabs.TabPane>
      </Tabs>
    </div>
  </div>
</template>
