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
  Tabs,
} from 'ant-design-vue';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { useVbenForm } from '#/adapter/form';

import FormTabsTablePreview from './FormTabsTablePreview.vue';
import type { TabTableConfig } from './FormTabsTablePreview.vue';

/** 明细列「库类型」常用项（可手填其它，如 varchar(50)） */
const tabColumnDbTypeOptions = [
  { value: 'uniqueidentifier', label: 'uniqueidentifier' },
  { value: 'nvarchar', label: 'nvarchar' },
  { value: 'varchar', label: 'varchar' },
  { value: 'int', label: 'int' },
  { value: 'bigint', label: 'bigint' },
  { value: 'decimal', label: 'decimal / numeric' },
  { value: 'datetime', label: 'datetime' },
  { value: 'date', label: 'date' },
  { value: 'time', label: 'time' },
  { value: 'bit', label: 'bit' },
];

/** 从 TableBuilder 返回的 dataType 推断简短库类型，写入 dbType */
function inferDbTypeHint(dataType: string): string {
  const s = String(dataType || '').trim().toLowerCase();
  if (!s) return '';
  if (s.includes('uniqueidentifier')) return 'uniqueidentifier';
  if (s.includes('nvarchar')) return 'nvarchar';
  if (s.includes('varchar') || s.includes('char') || s.includes('text')) return s.includes('n') ? 'nvarchar' : 'varchar';
  if (s.includes('bigint')) return 'bigint';
  if (s.includes('int') || s.includes('smallint') || s.includes('tinyint')) return 'int';
  if (s.includes('decimal') || s.includes('numeric') || s.includes('money') || s.includes('float') || s.includes('real'))
    return 'decimal';
  if (s.includes('datetime')) return 'datetime';
  if (s === 'date' || (s.includes('date') && !s.includes('datetime'))) return 'date';
  if (s.includes('time') && !s.includes('datetime')) return 'time';
  if (s === 'bit') return 'bit';
  return String(dataType || '').trim().slice(0, 48);
}

function mapImportedTabColumn(c: any) {
  return {
    field: c.field ?? 'field',
    title: c.title ?? '列',
    visible: c.visible !== false,
    dbType: c.dbType ?? '',
    editType: c.editType ?? 'input',
    dataSourceType: c.dataSourceType ?? 'manual',
    dictionaryId: c.dictionaryId ?? '',
    validationType:
      c.validationType ?? (String(c.rules ?? '').includes('required') ? 'required' : 'none'),
    validationPattern: c.validationPattern ?? '',
    validationMessage: c.validationMessage ?? '',
    options: c.options,
    rules: c.rules,
    remoteTableName: c.remoteTableName ?? '',
    remoteQueryFields: c.remoteQueryFields ?? '',
    remoteLabelField: c.remoteLabelField ?? '',
    remoteValueField: c.remoteValueField ?? '',
    remoteSearchFields: c.remoteSearchFields ?? '',
    remotePageSize: c.remotePageSize,
  };
}
import { resolveDictionaryInSchema } from './resolveDictionarySchema';
import {
  createDefaultSchemaItem,
  FORM_COMPONENT_OPTIONS,
  type FormDesignerSchemaItem,
  type FormLinkageConfig,
} from './form-designer.types';
import {
  FORM_DESIGNER_BEFORE_SUBMIT_SCRIPT_EXAMPLE,
  FORM_DESIGNER_ON_OPEN_SCRIPT_EXAMPLE,
} from './form-designer-script-examples';

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

// 中间「表单配置」区域的页签：表单配置 / 打开时脚本 / 保存前脚本
const activeFormTab = ref<'form' | 'onOpen' | 'beforeSubmit'>('form');

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

/** 在表单配置列表中直接修改某字段的 label，与右侧属性面板同步 */
function setItemLabel(index: number, value: string) {
  if (index < 0 || index >= schemaList.value.length) return;
  const list = schemaList.value as any[];
  list[index] = { ...list[index], label: value ?? '' };
  if (selectedIndex.value === index) editLabel.value = value ?? '';
}

// 保存配置（存库用）
const formCode = ref('');
const formTitle = ref('');
const formListCode = ref('');
// 表单级保存实体（优先于列表上的 saveEntityName/tableName）
const formSaveEntityName = ref('');
const formSavedId = ref<string | null>(null);
/** 打开弹窗时执行的脚本，可对表单控件赋值（params, formApi, request）；默认带可运行示例 */
const formOnOpenScript = ref(FORM_DESIGNER_ON_OPEN_SCRIPT_EXAMPLE);
/** 保存前脚本：校验或改写提交体；默认带可运行示例 */
const formBeforeSubmitScript = ref(FORM_DESIGNER_BEFORE_SUBMIT_SCRIPT_EXAMPLE);

function fillOnOpenScriptExample() {
  formOnOpenScript.value = FORM_DESIGNER_ON_OPEN_SCRIPT_EXAMPLE;
  message.success('已填入「打开时脚本」示例');
}

function fillBeforeSubmitScriptExample() {
  formBeforeSubmitScript.value = FORM_DESIGNER_BEFORE_SUBMIT_SCRIPT_EXAMPLE;
  message.success('已填入「保存前脚本」示例');
}

// 根据保存实体从表结构一键生成字段 / 列表列
const generatingFromTable = ref(false);
const generatingListFromTable = ref(false);
const generatingListTabIndex = ref<number>(-1);

async function fetchTableColumns(tableName: string) {
  const url = `${backendApi('TableBuilder/ListTableColumns')}?tableName=${encodeURIComponent(tableName)}`;
  const res = await requestClient.get<
    Array<{ columnName: string; dataType?: string }> | { code: number; data?: unknown; message?: string }
  >(url);
  return Array.isArray(res)
    ? res
    : (res && typeof res === 'object' && Array.isArray((res as any).data) ? (res as any).data : []);
}

function mapDataTypeToFormComponent(dataTypeRaw: string): FormDesignerSchemaItem['component'] {
  const dataType = String(dataTypeRaw || '').toLowerCase();
  if (['datetime', 'smalldatetime', 'date', 'time'].includes(dataType)) {
    return 'DatePicker' as any;
  }
  if (['int', 'bigint', 'smallint', 'tinyint', 'decimal', 'numeric', 'float', 'real', 'money'].includes(dataType)) {
    return 'InputNumber' as any;
  }
  if (dataType === 'bit') {
    return 'Switch' as any;
  }
  return 'Input';
}

function mapDataTypeToTabEditType(dataTypeRaw: string): 'input' | 'input-number' | 'date' | 'select' {
  const dataType = String(dataTypeRaw || '').toLowerCase();
  if (['datetime', 'smalldatetime', 'date', 'time'].includes(dataType)) return 'date';
  if (['int', 'bigint', 'smallint', 'tinyint', 'decimal', 'numeric', 'float', 'real', 'money'].includes(dataType)) {
    return 'input-number';
  }
  if (dataType === 'bit') return 'select';
  return 'input';
}

async function generateSchemaFromTable() {
  const name = formSaveEntityName.value?.trim();
  if (!name) {
    message.warning('请先在上方填写保存实体 (saveEntityName)');
    return;
  }
  generatingFromTable.value = true;
  try {
    const list = await fetchTableColumns(name);
    if (!list.length) {
      message.warning('该表/视图没有列或表名不存在');
      return;
    }
    // 简单映射：列名 -> 字段，类型 -> 组件
    const next: FormDesignerSchemaItem[] = list.map((col: any, idx: number) => {
      const colName = col.columnName || col.ColumnName || '';
      const component = mapDataTypeToFormComponent(col.dataType || col.DataType || '');
      return {
        fieldName: colName,
        label: colName,
        component,
        componentProps: {},
      } as FormDesignerSchemaItem;
    });
    schemaList.value = next;
    selectedIndex.value = next.length ? 0 : -1;
    message.success(`已根据表「${name}」生成 ${next.length} 个表单字段，可在右侧继续调整`);
  } catch (e: any) {
    const msg = e?.response?.data?.message ?? e?.message ?? e?.data?.message ?? '从表结构生成字段失败';
    message.error(msg);
  } finally {
    generatingFromTable.value = false;
  }
}

async function generateTabColumnsFromTable(tabIndex?: number) {
  if (layoutConfig.value.layoutType !== 'formTabsTable') {
    message.warning('请先将布局类型切换为「上表单 + 下页签」');
    return;
  }
  const idx = typeof tabIndex === 'number' ? tabIndex : selectedTabIndex.value;
  const tab = idx >= 0 ? tabsList.value[idx] : undefined;
  const name = tab?.tableName?.trim() || formSaveEntityName.value?.trim();
  if (!name) {
    message.warning('请先填写页签的明细表表名，或上方保存实体 (saveEntityName)');
    return;
  }
  generatingListFromTable.value = true;
  generatingListTabIndex.value = idx;
  try {
    const list = await fetchTableColumns(name);
    if (!list.length) {
      message.warning('该表/视图没有列或表名不存在');
      return;
    }

    const nextColumns = list.map((col: any) => {
      const colName = col.columnName || col.ColumnName || '';
      const rawDt = col.dataType || col.DataType || '';
      const editType = mapDataTypeToTabEditType(rawDt);
      return {
        field: colName,
        title: colName,
        visible: true,
        dbType: inferDbTypeHint(String(rawDt)),
        editType,
        dataSourceType: editType === 'select' ? 'manual' : undefined,
        dictionaryId: undefined,
        validationType: 'none',
        validationPattern: '',
        validationMessage: '',
        options: editType === 'select' ? '否,0\n是,1' : undefined,
      };
    });

    let nextIdx = idx;
    if (nextIdx < 0 || !tabsList.value[nextIdx]) {
      tabCounter += 1;
      tabsList.value.push({
        key: `tab_${tabCounter}`,
        tab: `${name}明细`,
        tableName: name,
        primaryKey: 'id',
        foreignKeyField: '',
        mainKeyField: '',
        columns: [],
      });
      nextIdx = tabsList.value.length - 1;
      selectedTabIndex.value = nextIdx;
    }

    tabsList.value[nextIdx].columns = nextColumns as any;
    if (!tabsList.value[nextIdx].tab?.trim()) {
      tabsList.value[nextIdx].tab = `${name}明细`;
    }
    if (!tabsList.value[nextIdx].tableName?.trim()) {
      tabsList.value[nextIdx].tableName = name;
    }
    message.success(`已为页签「${tabsList.value[nextIdx].tab}」生成 ${nextColumns.length} 个列表列`);
  } catch (e: any) {
    const msg = e?.response?.data?.message ?? e?.message ?? e?.data?.message ?? '从表结构生成列表列失败';
    message.error(msg);
  } finally {
    generatingListFromTable.value = false;
    generatingListTabIndex.value = -1;
  }
}

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
      layout?: {
        cols?: number;
        layoutType?: string;
        layout?: string;
        labelAlign?: string;
        labelWidth?: number;
        modalWidth?: number;
      };
      schema?: any[];
      tabs?: TabTableConfig[];
      saveEntityName?: string;
    };
    formSavedId.value = rec.id;
    formCode.value = rec.code ?? '';
    formTitle.value = rec.title ?? '';
    formListCode.value = rec.list_code ?? '';
    formSaveEntityName.value = parsed.saveEntityName ?? '';
    formOnOpenScript.value = parsed.onOpenScript ?? '';
    formBeforeSubmitScript.value = parsed.beforeSubmitScript ?? '';
    if (parsed.layout) {
      layoutConfig.value = {
        ...layoutConfig.value,
        cols: parsed.layout.cols ?? 2,
        layout: (parsed.layout.layout as any) ?? 'horizontal',
        labelAlign: (parsed.layout.labelAlign as any) ?? 'right',
        labelWidth: parsed.layout.labelWidth ?? 100,
        layoutType: (parsed.layout.layoutType as any) ?? 'form',
        modalWidth: parsed.layout.modalWidth ?? layoutConfig.value.modalWidth ?? 640,
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
        linkage: s.linkage,
        hideLabel: s.hideLabel,
        excludeFromSubmit: s.excludeFromSubmit,
      }));
    }
    if (Array.isArray(parsed.tabs)) {
      tabsList.value = parsed.tabs.map((t: any) => ({
        key: t.key ?? `tab_${Date.now()}`,
        tab: t.tab ?? '未命名',
        tableName: t.tableName ?? '',
        primaryKey: t.primaryKey ?? 'id',
        foreignKeyField: t.foreignKeyField ?? '',
        mainKeyField: t.mainKeyField ?? '',
        columns: Array.isArray(t.columns) ? t.columns.map((c: any) => mapImportedTabColumn(c)) : [],
      }));
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
  /** 弹窗宽度（打开 FormFromDesignerModal 时使用） */
  modalWidth: 640,
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
    tableName: '',
    primaryKey: 'id',
    foreignKeyField: '',
    mainKeyField: '',
    columns: [
      { field: 'name', title: '名称', visible: true, dbType: '', editType: 'input', validationType: 'none' },
      { field: 'value', title: '值', visible: true, dbType: '', editType: 'input', validationType: 'none' },
    ],
  });
  selectedTabIndex.value = tabsList.value.length - 1;
  message.success('已添加页签');
}

function removeTab(index: number) {
  tabsList.value.splice(index, 1);
  if (selectedTabIndex.value >= tabsList.value.length) selectedTabIndex.value = tabsList.value.length - 1;
}

/** 切到「上表单+下页签表格」时至少保证一个页签，避免运行时空白 */
watch(
  () => layoutConfig.value.layoutType,
  (t) => {
    if (t !== 'formTabsTable' || tabsList.value.length > 0) return;
    tabCounter += 1;
    tabsList.value.push({
      key: `tab_${tabCounter}`,
      tab: `页签${tabCounter}`,
      tableName: '',
      primaryKey: 'id',
      foreignKeyField: '',
      mainKeyField: '',
      columns: [
        { field: 'name', title: '名称', visible: true, dbType: '', editType: 'input', validationType: 'none' },
        { field: 'value', title: '值', visible: true, dbType: '', editType: 'input', validationType: 'none' },
      ],
    });
    selectedTabIndex.value = 0;
  },
);

function addColumn(tabIndex: number) {
  const tab = tabsList.value[tabIndex];
  if (!tab) return;
  const idx = (tab.columns?.length ?? 0) + 1;
  tab.columns = tab.columns ?? [];
  tab.columns.push({
    field: `col_${idx}`,
    title: `列${idx}`,
    visible: true,
    dbType: '',
    editType: 'input',
    dataSourceType: 'manual',
    validationType: 'none',
    validationPattern: '',
    validationMessage: '',
  });
}

function onTabColumnDataSourceTypeChange(col: any, value: 'manual' | 'dictionary') {
  col.dataSourceType = value;
  if (value === 'dictionary') {
    // 切换到字典时清空手动 options，避免配置歧义
    col.options = '';
  }
}

function onTabColumnEditTypeChange(col: any, value: any) {
  col.editType = value;
  // 当切换到数字/日期/时间时，若当前校验还是“无”，自动联动为对应校验类型
  const current = String(col.validationType ?? 'none') || 'none';
  if (current !== 'none') return;
  if (value === 'input-number') col.validationType = 'number';
  else if (value === 'date') col.validationType = 'date';
  else if (value === 'time') col.validationType = 'time';
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

// 属性编辑：控件类型、fieldName, label, rules, formItemClass, options
/** 控件类型（可修改，例如 Input 改为 InputNumber） */
const editComponent = ref<string>('Input');
const editFieldName = ref('');
const editLabel = ref('');
const editRules = ref('');
const editValidationType = ref<'none' | 'date' | 'time' | 'number' | 'email' | 'phone' | 'regex'>('none');
const editValidationPattern = ref('');
const editValidationMessage = ref('');
const editPlaceholder = ref('');
const editFormItemClass = ref('');
const editOptions = ref(''); // 格式：每行 "label,value" 或 "value"（label=value）
/** 数据源类型：
 * manual=手动配置
 * dictionary=数据字典
 * query=远程查询（仅 AutoComplete 使用）
 */
const editDataSourceType = ref<'manual' | 'dictionary' | 'query'>('manual');
/** 数据字典 ID（当 dataSourceType=dictionary 时使用） */
const editDictionaryId = ref<string>('');

/** AutoComplete 远程查询配置（componentProps.dataSourceType=query） */
const editAutoCompleteTableName = ref<string>('');
const editAutoCompleteQueryFields = ref<string>('');
const editAutoCompleteLabelField = ref<string>('');
const editAutoCompleteValueField = ref<string>('');
const editAutoCompleteSearchFields = ref<string>(''); // 逗号分隔：如 code,name（运行时按逗号拆）
const editAutoCompletePageSize = ref<number>(10);
/** 查询结果列 -> 表单 fieldName 映射（可选），多行：from,to 或 from,to */
const editAutoCompleteResponseMapText = ref<string>('');
/** 未配置 responseMap 时，是否按同名字段自动回填（默认关闭，避免 fid/FID 误伤） */
const editAutoCompleteFallbackFillSameName = ref<boolean>(false);

/** 下拉多列展示配置（可选，用于 dropdownRender 表头/列）
 * 每行：field,title  （例如 name,姓名）
 */
const editAutoCompleteDisplayColumnsText = ref<string>('');
/** 字典树数据（用于选择字典分类） */
const dictionaryTreeData = ref<any[]>([]);
/** 界面上不显示（如主键 ID，保存时仍会提交） */
const editHidden = ref(false);
/** 仅展示不保存（页面上显示，保存时不提交） */
const editExcludeFromSubmit = ref(false);

// 联动配置（通用：选值后自动填充其他字段）
const editLinkageEnabled = ref(false);
const editLinkageType = ref<'preset' | 'api'>('preset');
const editLinkagePreset = ref<'employee'>('employee');
const editLinkageApiUrl = ref('');
const editLinkageParamKey = ref('');
const editLinkageMethod = ref<'GET' | 'POST'>('GET');
/** 填充映射：每行 "API返回键,表单字段名" 如 code,工号 */
const editLinkageResponseMapText = ref('');

const selectedComponentNeedsOptions = computed(() => {
  const comp = selectedItem.value?.component as string;
  return comp && COMPONENTS_WITH_OPTIONS.includes(comp);
});

const selectedComponentNeedsTreeData = computed(() => {
  const comp = selectedItem.value?.component as string;
  return comp && COMPONENTS_WITH_TREEDATA.includes(comp);
});

/** 仅 AutoComplete 允许配置 dataSourceType=query */
const isEditingAutoComplete = computed(() => {
  return editComponent.value === 'AutoComplete';
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

/** 控件类型下拉选项（与左侧可拖拽组件一致） */
const componentTypeOptions = FORM_COMPONENT_OPTIONS.map((o) => ({ label: o.label, value: o.component }));

watch(
  selectedItem,
  (item) => {
    if (item) {
      editComponent.value = (item.component as string) ?? 'Input';
      editFieldName.value = item.fieldName ?? '';
      editLabel.value = (item.label as string) ?? '';
      editRules.value = typeof item.rules === 'string' ? item.rules : '';
      const cp = item.componentProps as any;
      editValidationType.value = (cp?.validationType as any) ?? 'none';
      editValidationPattern.value = cp?.validationPattern ?? '';
      editValidationMessage.value = cp?.validationMessage ?? '';
      editPlaceholder.value = (item.componentProps as any)?.placeholder ?? '';
      editFormItemClass.value = (item.formItemClass as string) ?? '';
      editDataSourceType.value =
        cp?.dataSourceType === 'dictionary'
          ? 'dictionary'
          : cp?.dataSourceType === 'query' && item.component === 'AutoComplete'
            ? 'query'
            : 'manual';
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

      // AutoComplete 查询配置
      if (cp?.dataSourceType === 'query') {
        editAutoCompleteTableName.value = cp?.tableName ?? '';
        editAutoCompleteQueryFields.value = cp?.queryFields ?? cp?.queryField ?? '';
        editAutoCompleteLabelField.value = cp?.labelField ?? '';
        editAutoCompleteValueField.value = cp?.valueField ?? '';
        const searchFieldRaw = cp?.searchField ?? cp?.searchFields ?? '';
        editAutoCompleteSearchFields.value = Array.isArray(searchFieldRaw)
          ? searchFieldRaw.join(',')
          : String(searchFieldRaw ?? '');
        editAutoCompletePageSize.value = Number.isFinite(Number(cp?.pageSize))
          ? Number(cp?.pageSize)
          : 10;
        if (cp?.responseMap && typeof cp.responseMap === 'object') {
          editAutoCompleteResponseMapText.value = Object.entries(cp.responseMap)
            .map(([k, v]) => `${k},${v}`)
            .join('\n');
        } else {
          editAutoCompleteResponseMapText.value = cp?.responseMapText ?? cp?.fieldMapText ?? '';
        }

          editAutoCompleteDisplayColumnsText.value = cp?.displayColumnsText ?? cp?.dropdownColumnsText ?? '';
        editAutoCompleteFallbackFillSameName.value = cp?.fallbackFillSameName === true;
      } else {
        editAutoCompleteTableName.value = '';
        editAutoCompleteQueryFields.value = '';
        editAutoCompleteLabelField.value = '';
        editAutoCompleteValueField.value = '';
        editAutoCompleteSearchFields.value = '';
        editAutoCompletePageSize.value = 10;
        editAutoCompleteResponseMapText.value = '';
          editAutoCompleteDisplayColumnsText.value = '';
        editAutoCompleteFallbackFillSameName.value = false;
      }

      editHidden.value = cp?.type === 'hidden';
      editExcludeFromSubmit.value = !!(item as any).excludeFromSubmit;
      const linkage = (item as any).linkage as FormLinkageConfig | undefined;
      editLinkageEnabled.value = linkage?.enabled ?? false;
      editLinkageType.value = linkage?.type ?? 'preset';
      editLinkagePreset.value = linkage?.preset ?? 'employee';
      editLinkageApiUrl.value = linkage?.apiUrl ?? '';
      editLinkageParamKey.value = linkage?.paramKey ?? '';
      editLinkageMethod.value = linkage?.method ?? 'GET';
      editLinkageResponseMapText.value = linkage?.responseMap
        ? Object.entries(linkage.responseMap).map(([k, v]) => `${k},${v}`).join('\n')
        : '';
    } else {
      editComponent.value = 'Input';
      editFieldName.value = '';
      editLabel.value = '';
      editRules.value = '';
      editValidationType.value = 'none';
      editValidationPattern.value = '';
      editValidationMessage.value = '';
      editPlaceholder.value = '';
      editFormItemClass.value = '';
      editOptions.value = '';
      editDataSourceType.value = 'manual';
      editDictionaryId.value = '';
      editHidden.value = false;
      editExcludeFromSubmit.value = false;
      editLinkageEnabled.value = false;
      editLinkageType.value = 'preset';
      editLinkagePreset.value = 'employee';
      editLinkageApiUrl.value = '';
      editLinkageParamKey.value = '';
      editLinkageMethod.value = 'GET';
      editLinkageResponseMapText.value = '';
      editAutoCompleteTableName.value = '';
      editAutoCompleteQueryFields.value = '';
      editAutoCompleteLabelField.value = '';
      editAutoCompleteValueField.value = '';
      editAutoCompleteSearchFields.value = '';
      editAutoCompletePageSize.value = 10;
      editAutoCompleteResponseMapText.value = '';
      editAutoCompleteDisplayColumnsText.value = '';
      editAutoCompleteFallbackFillSameName.value = false;
    }
  },
  { immediate: true },
);

function parseResponseMapText(text: string): Record<string, string> {
  const map: Record<string, string> = {};
  text.split('\n').forEach((line) => {
    const t = line.trim();
    if (!t) return;
    const i = t.indexOf(',');
    if (i >= 0) {
      map[t.slice(0, i).trim()] = t.slice(i + 1).trim();
    } else {
      map[t] = t;
    }
  });
  return map;
}

watch(
  [
    editComponent,
    editFieldName,
    editLabel,
    editRules,
    editValidationType,
    editValidationPattern,
    editValidationMessage,
    editPlaceholder,
    editFormItemClass,
    editOptions,
    editDataSourceType,
    editDictionaryId,
    editAutoCompleteTableName,
    editAutoCompleteQueryFields,
    editAutoCompleteLabelField,
    editAutoCompleteValueField,
    editAutoCompleteSearchFields,
    editAutoCompletePageSize,
    editAutoCompleteResponseMapText,
    editAutoCompleteFallbackFillSameName,
    editAutoCompleteDisplayColumnsText,
    editHidden,
    editExcludeFromSubmit,
    editLinkageEnabled,
    editLinkageType,
    editLinkagePreset,
    editLinkageApiUrl,
    editLinkageParamKey,
    editLinkageMethod,
    editLinkageResponseMapText,
  ],
  () => {
    if (!selectedItem.value) return;
    const compProps: Record<string, any> = {
      ...(selectedItem.value.componentProps ?? {}),
      placeholder: editPlaceholder.value || undefined,
    };
    if (editValidationType.value && editValidationType.value !== 'none') {
      compProps.validationType = editValidationType.value;
    } else {
      delete compProps.validationType;
    }
    if (editValidationType.value === 'regex' && editValidationPattern.value.trim()) {
      compProps.validationPattern = editValidationPattern.value.trim();
    } else {
      delete compProps.validationPattern;
    }
    if (editValidationMessage.value.trim()) {
      compProps.validationMessage = editValidationMessage.value.trim();
    } else {
      delete compProps.validationMessage;
    }
    // 解决表单预览控件宽度偏小：给非 hidden 控件补默认宽度
    if (!editHidden.value) {
      const currentStyle = typeof compProps.style === 'object' && compProps.style ? compProps.style : {};
      compProps.style = {
        ...currentStyle,
        ...(compProps.style?.width ? {} : { width: '100%' }),
      };
    }
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
        const nextDataSourceType =
          editDataSourceType.value === 'query' && !isEditingAutoComplete.value ? 'manual' : editDataSourceType.value;
        compProps.dataSourceType = nextDataSourceType;
        if (nextDataSourceType === 'dictionary' && editDictionaryId.value) {
          compProps.dictionaryId = editDictionaryId.value;
          delete compProps.options;
          delete compProps.treeData;
          // 运行时由 resolveDictionaryInSchema 填充
        } else if (nextDataSourceType === 'query' && isEditingAutoComplete.value) {
          // query：不走 options/treeData/dictionaryId
          delete compProps.dictionaryId;
          delete compProps.options;
          delete compProps.treeData;

          const tableName = editAutoCompleteTableName.value.trim();
          const queryFields = editAutoCompleteQueryFields.value.trim();
          const labelField = editAutoCompleteLabelField.value.trim();
          const valueField = editAutoCompleteValueField.value.trim();
          const searchFields = editAutoCompleteSearchFields.value.trim(); // 允许空：运行时会 fallback 到 labelField
          const pageSize = Number(editAutoCompletePageSize.value);
          const responseMapText = editAutoCompleteResponseMapText.value.trim();
          const fallbackFillSameName = editAutoCompleteFallbackFillSameName.value === true;
          const displayColumnsText = editAutoCompleteDisplayColumnsText.value.trim();

          if (tableName) compProps.tableName = tableName;
          else delete compProps.tableName;
          if (queryFields) compProps.queryFields = queryFields;
          else delete compProps.queryFields;
          if (labelField) compProps.labelField = labelField;
          else delete compProps.labelField;
          if (valueField) compProps.valueField = valueField;
          else delete compProps.valueField;
          if (searchFields) compProps.searchFields = searchFields;
          else delete compProps.searchFields;
          if (Number.isFinite(pageSize) && pageSize > 0) compProps.pageSize = pageSize;
          else delete compProps.pageSize;
          if (responseMapText) compProps.responseMapText = responseMapText;
          else delete compProps.responseMapText;

          // 是否允许“同名字段自动回填”（默认关闭）
          if (fallbackFillSameName) compProps.fallbackFillSameName = true;
          else delete compProps.fallbackFillSameName;

          if (displayColumnsText) compProps.displayColumnsText = displayColumnsText;
          else delete compProps.displayColumnsText;
        } else {
          // manual：走 options/treeData
          delete compProps.dictionaryId;
          if (selectedComponentNeedsOptions.value) {
            compProps.options = textToOptions(editOptions.value);
          }
          if (selectedComponentNeedsTreeData.value) {
            compProps.treeData = textToTreeData(editOptions.value);
          }
        }
      }
      const linkage: FormLinkageConfig | undefined = editLinkageEnabled.value
        ? {
            enabled: true,
            type: editLinkageType.value,
            preset: editLinkagePreset.value,
            apiUrl: editLinkageApiUrl.value || undefined,
            paramKey: editLinkageParamKey.value || undefined,
            method: editLinkageMethod.value,
            responseMap: Object.keys(parseResponseMapText(editLinkageResponseMapText.value)).length
              ? parseResponseMapText(editLinkageResponseMapText.value)
              : undefined,
          }
        : undefined;
      updateSelectedField({
        ...baseUpdates,
        hideLabel: false,
        component: editComponent.value || 'Input',
        componentProps: compProps,
        linkage,
      } as any);
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
    saveEntityName: formSaveEntityName.value?.trim() || undefined,
    onOpenScript: formOnOpenScript.value?.trim() || undefined,
    beforeSubmitScript: formBeforeSubmitScript.value?.trim() || undefined,
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
      linkage: item.linkage,
    }));
    if (parsed?.saveEntityName) {
      formSaveEntityName.value = parsed.saveEntityName;
    }
    if (parsed?.onOpenScript != null) formOnOpenScript.value = parsed.onOpenScript;
    if (parsed?.beforeSubmitScript != null) formBeforeSubmitScript.value = parsed.beforeSubmitScript;
    if (layout && typeof layout === 'object') {
      layoutConfig.value = { ...layoutConfig.value, ...layout };
    }
    if (parsed?.tabs && Array.isArray(parsed.tabs)) {
      tabsList.value = parsed.tabs.map((t: any) => ({
        key: t.key ?? `tab_${Date.now()}`,
        tab: t.tab ?? '未命名',
        tableName: t.tableName ?? '',
        primaryKey: t.primaryKey ?? 'id',
        foreignKeyField: t.foreignKeyField ?? '',
        mainKeyField: t.mainKeyField ?? '',
        columns: (t.columns ?? []).map((c: any) => mapImportedTabColumn(c)),
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
  formOnOpenScript.value = '';
  formBeforeSubmitScript.value = '';
  message.info('已清空');
}

// 保存到数据库 vben_form_desinger
const saving = ref(false);
function getFormSchemaPayload() {
  return {
    layout: layoutConfig.value,
    schema: schemaList.value,
    tabs: layoutConfig.value.layoutType === 'formTabsTable' ? tabsList.value : undefined,
    saveEntityName: formSaveEntityName.value?.trim() || undefined,
    onOpenScript: formOnOpenScript.value?.trim() || undefined,
    beforeSubmitScript: formBeforeSubmitScript.value?.trim() || undefined,
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
              <div class="mb-1 text-xs">保存实体 (saveEntityName)</div>
              <Input
                v-model:value="formSaveEntityName"
                placeholder="如 vben_sys_operation_log；不填则用列表的 saveEntityName 或 tableName"
                size="small"
              />
              <div class="mt-2 grid grid-cols-1 gap-2">
                <Button
                  size="small"
                  :loading="generatingFromTable"
                  @click="generateSchemaFromTable"
                >
                  从表结构一键生成字段
                </Button>
              </div>
            </div>
            <div>
              <div class="mb-1 text-xs">布局类型</div>
              <Select
                v-model:value="layoutConfig.layoutType"
                :options="[
                  { label: '纯表单（仅中间主表单）', value: 'form' },
                  {
                    label: '上表单 + 下页签（每页签内为可编辑表格）',
                    value: 'formTabsTable',
                  },
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
            <div>
              <div class="mb-1 text-xs">弹窗宽度 (modalWidth)</div>
              <InputNumber
                v-model:value="layoutConfig.modalWidth"
                :min="360"
                :max="1600"
                size="small"
                class="w-full"
              />
              <div class="mt-1 text-muted-foreground text-xs">
                点击列表「新增/编辑」打开该表单时使用此宽度
              </div>
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

      <!-- 中间：画布（栅格布局，支持拖拽放置） + 脚本页签 -->
      <Card class="min-w-72 flex-1" size="small">
        <template #title>
          <span>表单配置</span>
          <span class="ml-2 text-muted-foreground font-normal text-xs">
            {{ layoutConfig.cols }} 列
          </span>
        </template>
        <!-- destroyInactiveTabPane=false + forceRender：避免切换页签时卸载子树导致画布/脚本/右侧属性联动状态丢失 -->
        <Tabs
          v-model:activeKey="activeFormTab"
          size="small"
          type="card"
          :destroy-inactive-tab-pane="false"
        >
          <!-- 页签 1：表单配置 -->
          <Tabs.TabPane key="form" tab="表单配置" :force-render="true">
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
                ① 上方主表单区域
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
                    <Input
                      :value="item.label"
                      size="small"
                      class="min-w-0 flex-1 font-medium"
                      placeholder="标签"
                      @update:value="(v) => setItemLabel(index, v ?? '')"
                      @click.stop
                    />
                    <span v-if="(item.componentProps as any)?.type === 'hidden'" class="shrink-0 text-muted-foreground text-xs">(隐藏)</span>
                    <span v-else-if="(item as any).excludeFromSubmit" class="shrink-0 text-muted-foreground text-xs">(仅展示)</span>
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
                <span class="text-muted-foreground text-xs font-medium">② 下方页签（每页签内为表格列配置）</span>
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
                    <Input
                      v-model:value="tab.tableName"
                      placeholder="明细表名(tableName)"
                      size="small"
                      class="w-36"
                    />
                    <Input
                      v-model:value="tab.primaryKey"
                      placeholder="主键(primaryKey)"
                      size="small"
                      class="w-28"
                    />
                    <Input
                      v-model:value="tab.foreignKeyField"
                      placeholder="外键列(填主表PK)，如 FID"
                      size="small"
                      class="w-40"
                    />
                    <Input
                      v-model:value="tab.mainKeyField"
                      placeholder="主表字段(可选)"
                      size="small"
                      class="w-28"
                    />
                    <Button
                      size="small"
                      :loading="generatingListFromTable && generatingListTabIndex === ti"
                      @click.stop="generateTabColumnsFromTable(ti)"
                    >
                      从表结构一键生成列表
                    </Button>
                    <Input v-model:value="tab.key" placeholder="key" size="small" class="w-24" />
                    <Button danger size="small" @click.stop="removeTab(ti)">删</Button>
                  </div>
                  <div class="text-muted-foreground mb-1 text-xs leading-relaxed">
                    表格列：字段名=库列名，表头=界面显示。
                    <span class="font-medium">库类型</span>
                    记录该列在库中的类型（如 uniqueidentifier），便于配置 remote 的 value 与入库一致；从表结构生成时会自动带一项，可改。
                  </div>
                  <div
                    v-for="(col, ci) in tab.columns"
                    :key="ci"
                    class="mb-2 rounded border border-dashed p-2"
                  >
                    <div class="mb-1 flex flex-wrap items-center gap-1">
                      <Input
                        v-model:value="col.field"
                        placeholder="字段名(field)，如 emp_code"
                        size="small"
                        class="w-36"
                      />
                      <Input
                        v-model:value="col.title"
                        placeholder="表头(title)，如 员工编号"
                        size="small"
                        class="w-36"
                      />
                      <Select
                        :value="col.editType"
                        :options="[
                          { label: '输入框', value: 'input' },
                          { label: '数字', value: 'input-number' },
                          { label: '下拉', value: 'select' },
                          { label: '日期', value: 'date' },
                          { label: '时间', value: 'time' },
                          { label: '开关', value: 'switch' },
                          { label: '远程下拉', value: 'remote-select' },
                          { label: 'AutoComplete', value: 'autocomplete' },
                        ]"
                        placeholder="控件"
                        size="small"
                        class="w-20"
                        allow-clear
                        @change="(v) => onTabColumnEditTypeChange(col, v)"
                      />
                      <Select
                        v-model:value="col.validationType"
                        :options="[
                          { label: '无', value: 'none' },
                          { label: '必填', value: 'required' },
                          { label: '日期', value: 'date' },
                          { label: '时间', value: 'time' },
                          { label: '数字', value: 'number' },
                          { label: '邮箱', value: 'email' },
                          { label: '手机号', value: 'phone' },
                          { label: '正则', value: 'regex' },
                        ]"
                        placeholder="校验"
                        size="small"
                        class="w-24"
                      />
                      <div class="flex items-center gap-1 px-1">
                        <span class="text-muted-foreground text-xs">显示</span>
                        <Switch v-model:checked="col.visible" size="small" />
                      </div>
                      <Button danger size="small" @click.stop="removeColumn(ti, ci)">×</Button>
                    </div>
                    <div class="mb-1 flex flex-wrap items-center gap-2">
                      <span class="text-muted-foreground shrink-0 text-[11px]">库类型</span>
                      <AutoComplete
                        v-model:value="col.dbType"
                        :options="tabColumnDbTypeOptions"
                        placeholder="如 uniqueidentifier / nvarchar（可手填）"
                        size="small"
                        class="min-w-[220px] max-w-md flex-1"
                        allow-clear
                      />
                    </div>
                    <div
                      v-if="col.editType === 'remote-select' || col.editType === 'autocomplete'"
                      class="mb-1 text-[11px] leading-relaxed text-muted-foreground"
                    >
                      填<strong class="font-medium text-foreground">本列在库里真实类型</strong>，要和下面「存库字段
                      value」写进单元格的值类型一致；列是 GUID 就填
                      <code class="text-xs">uniqueidentifier</code>
                      ，且 value 必须选 ID 列（如 HC_ID），不要选名称列。
                    </div>
                    <div v-if="col.validationType && col.validationType !== 'none'" class="mb-1 grid grid-cols-2 gap-1">
                      <Input
                        v-if="col.validationType === 'regex'"
                        v-model:value="col.validationPattern"
                        placeholder="正则表达式，如 ^\\d{6}$"
                        size="small"
                        class="w-full"
                      />
                      <Input
                        v-model:value="col.validationMessage"
                        :placeholder="col.validationType === 'regex' ? '错误提示（可选）' : '错误提示（可选）'"
                        size="small"
                        class="w-full"
                      />
                    </div>
                    <div v-if="col.editType === 'select'" class="mt-1">
                      <div class="mb-1 grid grid-cols-2 gap-1">
                        <Select
                          :value="col.dataSourceType"
                          :options="[
                            { label: '手动选项', value: 'manual' },
                            { label: '数据字典', value: 'dictionary' },
                          ]"
                          size="small"
                          class="w-full"
                          @change="(v) => onTabColumnDataSourceTypeChange(col, v as any)"
                        />
                        <TreeSelect
                          v-if="col.dataSourceType === 'dictionary'"
                          v-model:value="col.dictionaryId"
                          :tree-data="dictionaryTreeData"
                          tree-default-expand-all
                          allow-clear
                          show-search
                          size="small"
                          class="w-full"
                          placeholder="选择字典ID"
                        />
                      </div>
                      <Input.TextArea
                        v-if="col.dataSourceType !== 'dictionary'"
                        v-model:value="col.options"
                        :rows="2"
                        placeholder="下拉选项：每行 label,value"
                        size="small"
                        class="font-mono text-xs"
                      />
                    </div>
                    <div
                      v-else-if="col.editType === 'remote-select' || col.editType === 'autocomplete'"
                      class="mt-1 space-y-2 rounded border border-border/50 bg-muted/15 p-2"
                    >
                      <div class="text-foreground text-xs font-medium">远程下拉 / AutoComplete</div>
                      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2 sm:gap-x-3">
                        <div class="min-w-0">
                          <div class="mb-0.5 text-xs text-foreground">数据表 remoteTableName</div>
                          <Input
                            v-model:value="col.remoteTableName"
                            placeholder="如 dbo.YourTable"
                            size="small"
                            class="w-full"
                          />
                          <p class="mt-0.5 text-[11px] leading-snug text-muted-foreground">
                            选项从哪张表（或视图）查，填库里的表名。
                          </p>
                        </div>
                        <div class="min-w-0">
                          <div class="mb-0.5 text-xs text-foreground">额外查询列 remoteQueryFields（可选）</div>
                          <Input
                            v-model:value="col.remoteQueryFields"
                            placeholder="英文逗号分隔，如 ColA,ColB"
                            size="small"
                            class="w-full"
                          />
                          <p class="mt-0.5 text-[11px] leading-snug text-muted-foreground">
                            除显示/存库/搜索外还要带出的列；不填则只查必要字段。
                          </p>
                        </div>
                        <div class="min-w-0">
                          <div class="mb-0.5 text-xs text-foreground">显示字段 label（界面给人看的）</div>
                          <Input
                            v-model:value="col.remoteLabelField"
                            placeholder="如 HC_Name"
                            size="small"
                            class="w-full"
                          />
                          <p class="mt-0.5 text-[11px] leading-snug text-muted-foreground">
                            下拉里展示的文字列名，例如假种名称。
                          </p>
                        </div>
                        <div class="min-w-0">
                          <div class="mb-0.5 text-xs text-foreground">存库字段 value（写入本明细列）</div>
                          <Input
                            v-model:value="col.remoteValueField"
                            placeholder="如 HC_ID，勿填名称列"
                            size="small"
                            class="w-full"
                          />
                          <p class="mt-0.5 text-[11px] leading-snug text-muted-foreground">
                            真正保存到本列的值，用主键/外键列（如 GUID 的 HC_ID）。填名称列会把汉字存进 GUID
                            列导致报错。
                          </p>
                        </div>
                        <div class="min-w-0">
                          <div class="mb-0.5 text-xs text-foreground">搜索列 remoteSearchFields（可选）</div>
                          <Input
                            v-model:value="col.remoteSearchFields"
                            placeholder="英文逗号分隔"
                            size="small"
                            class="w-full"
                          />
                          <p class="mt-0.5 text-[11px] leading-snug text-muted-foreground">
                            用户打字时在哪些列里模糊搜；不填时一般会按 label 字段搜。
                          </p>
                        </div>
                        <div class="min-w-0">
                          <div class="mb-0.5 text-xs text-foreground">每页条数 remotePageSize</div>
                          <InputNumber
                            v-model:value="col.remotePageSize"
                            :min="1"
                            :max="500"
                            size="small"
                            class="w-full"
                          />
                          <p class="mt-0.5 text-[11px] leading-snug text-muted-foreground">
                            每次远程请求最多拉回多少条；大一点少翻页，太大会慢。
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
                  <Button size="small" class="mt-1" @click.stop="addColumn(ti)">+ 添加列</Button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </Tabs.TabPane>

      <!-- 页签 2：打开时脚本 -->
      <Tabs.TabPane key="onOpen" tab="打开时脚本" :force-render="true">
        <div class="text-muted-foreground mb-2 text-xs leading-relaxed">
          用于<strong>弹窗已打开、默认值/编辑回填已写入后</strong>再改界面：赋值、按条件拉接口回填等。默认示例含可直接运行的
          <code class="text-xs">console.info</code>，其它段落请按需取消注释并改字段名。
        </div>
        <div class="mb-2">
          <Button size="small" @click="fillOnOpenScriptExample">填入示例脚本</Button>
        </div>
        <Input.TextArea
          v-model:value="formOnOpenScript"
          :rows="18"
          placeholder="params={ mode, initialValues, backendApi }, formApi, request(url, { method, data })"
          size="small"
          class="font-mono text-xs"
        />
      </Tabs.TabPane>

      <!-- 页签 3：保存前脚本 -->
      <Tabs.TabPane key="beforeSubmit" tab="保存前脚本" :force-render="true">
        <div class="text-muted-foreground mb-2 text-xs leading-relaxed">
          用于<strong>用户点保存且表单校验通过后、发保存请求前</strong>：做业务校验（失败则拦截）或改写提交字段（trim、补隐藏字段等）。
        </div>
        <div class="mb-2">
          <Button size="small" @click="fillBeforeSubmitScriptExample">填入示例脚本</Button>
        </div>
        <Input.TextArea
          v-model:value="formBeforeSubmitScript"
          :rows="18"
          placeholder="params={ formValues }, formApi。返回 { valid:false, message } 或 { formValues }"
          size="small"
          class="font-mono text-xs"
        />
      </Tabs.TabPane>
    </Tabs>
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
            <div class="mb-1 text-xs">控件类型 (component)</div>
            <Select
              v-model:value="editComponent"
              :options="componentTypeOptions"
              placeholder="选择控件"
              size="small"
              class="w-full"
            />
            <div class="mt-1 text-muted-foreground text-xs">
              可随时修改，如输入框改为数字输入
            </div>
          </div>
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
                :options="
                  isEditingAutoComplete
                    ? [
                        { label: '手动配置', value: 'manual' },
                        { label: '数据字典', value: 'dictionary' },
                        { label: '远程查询 (query)', value: 'query' },
                      ]
                    : [
                        { label: '手动配置', value: 'manual' },
                        { label: '数据字典', value: 'dictionary' },
                      ]
                "
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
            <div v-else-if="editDataSourceType === 'query' && isEditingAutoComplete">
              <div class="mb-1 text-xs">AutoComplete 远程查询配置</div>
              <div class="mt-2">
                <div class="mb-1 text-xs">表名 (tableName)</div>
                <Input
                  v-model:value="editAutoCompleteTableName"
                  placeholder="如 t_base_employee"
                  size="small"
                  class="w-full"
                />
              </div>
              <div class="mt-2">
                <div class="mb-1 text-xs">查询列 (queryFields)</div>
                <Input.TextArea
                  v-model:value="editAutoCompleteQueryFields"
                  :rows="3"
                  placeholder="逗号分隔：如 name,id,sex（建议包含 label/value 以及需回填的列）"
                  size="small"
                  class="font-mono text-xs"
                />
                <div class="mt-1 text-muted-foreground text-xs">
                  不填则后端默认 `SELECT *`
                </div>
              </div>
              <div class="mt-2 flex gap-2">
                <div class="flex-1">
                  <div class="mb-1 text-xs">展示列 (labelField)</div>
                  <Input
                    v-model:value="editAutoCompleteLabelField"
                    placeholder="如 name"
                    size="small"
                    class="w-full"
                  />
                </div>
                <div class="flex-1">
                  <div class="mb-1 text-xs">值列 (valueField)</div>
                  <Input
                    v-model:value="editAutoCompleteValueField"
                    placeholder="如 id"
                    size="small"
                    class="w-full"
                  />
                </div>
              </div>
              <div class="mt-2">
                <div class="mb-1 text-xs">模糊搜索列 (searchFields)</div>
                <Input
                  v-model:value="editAutoCompleteSearchFields"
                  placeholder="逗号分隔：如 code,name"
                  size="small"
                  class="w-full"
                />
                <div class="mt-1 text-muted-foreground text-xs">
                  为空时默认使用 labelField
                </div>
              </div>
              <div class="mt-2">
                <div class="mb-1 text-xs">每次查询条数 (pageSize)</div>
                <InputNumber
                  v-model:value="editAutoCompletePageSize"
                  :min="1"
                  :max="200"
                  class="w-full"
                  size="small"
                />
              </div>
              <div class="mt-2">
                <div class="mb-1 text-xs">查询结果回填映射 responseMapText（可选）</div>
                <Input.TextArea
                  v-model:value="editAutoCompleteResponseMapText"
                  :rows="4"
                  placeholder="每行：查询结果列名,表单fieldName （例如 code,employeeNo）"
                  size="small"
                  class="font-mono text-xs"
                />
              </div>
              <div class="mt-2 flex items-center justify-between rounded border border-dashed px-2 py-1">
                <span class="text-xs">未配置映射时按同名字段自动回填</span>
                <Switch v-model:checked="editAutoCompleteFallbackFillSameName" size="small" />
              </div>

              <div class="mt-2">
                <div class="mb-1 text-xs">下拉多列展示/表头 displayColumnsText（可选）</div>
                <Input.TextArea
                  v-model:value="editAutoCompleteDisplayColumnsText"
                  :rows="4"
                  placeholder="每行：列名,表头标题（例如 code,工号；name,姓名；brith_date,生日）"
                  size="small"
                  class="font-mono text-xs"
                />
                <div class="mt-1 text-muted-foreground text-xs">
                  不填时：默认用 queryFields 作为展示列；表头标题显示为列名
                </div>
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
            <div class="mb-1 text-xs">格式校验</div>
            <Select
              v-model:value="editValidationType"
              :options="[
                { label: '无', value: 'none' },
                { label: '日期', value: 'date' },
                { label: '时间', value: 'time' },
                { label: '数字', value: 'number' },
                { label: '邮箱', value: 'email' },
                { label: '手机号', value: 'phone' },
                { label: '正则表达式', value: 'regex' },
              ]"
              placeholder="可选"
              size="small"
              class="w-full"
            />
          </div>
          <div v-if="editValidationType === 'regex'">
            <div class="mb-1 text-xs">正则表达式</div>
            <Input
              v-model:value="editValidationPattern"
              placeholder="如 ^\\d{6}$"
              size="small"
              class="w-full"
            />
          </div>
          <div v-if="editValidationType !== 'none'">
            <div class="mb-1 text-xs">错误提示词（可选）</div>
            <Input
              v-model:value="editValidationMessage"
              placeholder="如：请输入正确的手机号"
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
          <!-- 联动：选值后自动填充其他字段（通用） -->
          <div class="border-border rounded border border-dashed p-2">
            <div class="mb-2 flex items-center justify-between">
              <span class="text-xs font-medium">联动（选值后自动填充其他字段）</span>
              <Switch v-model:checked="editLinkageEnabled" size="small" />
            </div>
            <template v-if="editLinkageEnabled">
              <div class="mb-2">
                <div class="mb-1 text-xs">联动类型</div>
                <Select
                  v-model:value="editLinkageType"
                  :options="[
                    { label: '预设（员工等）', value: 'preset' },
                    { label: '自定义 API', value: 'api' },
                  ]"
                  size="small"
                  class="w-full"
                />
              </div>
              <template v-if="editLinkageType === 'preset'">
                <div class="mb-2">
                  <div class="mb-1 text-xs">预设</div>
                  <Select
                    v-model:value="editLinkagePreset"
                    :options="[{ label: '员工（姓名/工号 → 工号、性别等）', value: 'employee' }]"
                    size="small"
                    class="w-full"
                  />
                </div>
              </template>
              <template v-else>
                <div class="mb-2">
                  <div class="mb-1 text-xs">API 地址</div>
                  <Input
                    v-model:value="editLinkageApiUrl"
                    placeholder="如 FormLookup/Employee 或完整 URL"
                    size="small"
                    class="w-full"
                  />
                </div>
                <div class="mb-2">
                  <div class="mb-1 text-xs">请求方式</div>
                  <Select
                    v-model:value="editLinkageMethod"
                    :options="[
                      { label: 'GET', value: 'GET' },
                      { label: 'POST', value: 'POST' },
                    ]"
                    size="small"
                    class="w-full"
                  />
                </div>
              </template>
              <div class="mb-2">
                <div class="mb-1 text-xs">参数来源字段（不填则用当前字段值）</div>
                <Input
                  v-model:value="editLinkageParamKey"
                  placeholder="表单字段名"
                  size="small"
                  class="w-full"
                />
              </div>
              <div>
                <div class="mb-1 text-xs">填充映射（API 返回键 → 表单字段名）</div>
                <Input.TextArea
                  v-model:value="editLinkageResponseMapText"
                  :rows="3"
                  placeholder="每行：API返回的键,表单字段名&#10;例：code,工号&#10;gender,性别"
                  size="small"
                  class="font-mono text-xs"
                />
              </div>
            </template>
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
