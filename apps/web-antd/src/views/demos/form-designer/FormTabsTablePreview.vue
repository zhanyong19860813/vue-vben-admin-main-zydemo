<script setup lang="ts">
/**
 * 上表单 + 下页签表格 预览组件（也可仅渲染页签表格：showForm=false 由外层提供表单）
 * 支持：新增行、删除选中行、行内编辑
 */
import { ref, watch } from 'vue';
import { Button, Tabs, message } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import type { VbenFormSchema } from '#/adapter/form';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { resolveDictionaryInSchema } from './resolveDictionarySchema';

export interface TabTableColumn {
  field: string;
  title: string;
  /**
   * 对应数据库列类型说明（如 uniqueidentifier、nvarchar、datetime），仅配置与文档；
   * 运行时可据此做校验/提示（与 editType、remoteValueField 等配合）。
   */
  dbType?: string;
  /** 是否展示该列（false=隐藏，但数据仍参与提交） */
  visible?: boolean;
  /** 控件类型：input/input-number/select/date/switch/time/remote-select/autocomplete */
  editType?: 'input' | 'input-number' | 'select' | 'date' | 'switch' | 'time' | 'remote-select' | 'autocomplete';
  /** select 的数据源类型：manual=手填 options，dictionary=按字典ID加载 */
  dataSourceType?: 'manual' | 'dictionary';
  /** select 且 dataSourceType=dictionary 时使用 */
  dictionaryId?: string;
  /** 列校验类型 */
  validationType?: 'none' | 'required' | 'date' | 'time' | 'number' | 'email' | 'phone' | 'regex';
  /** validationType=regex 时使用 */
  validationPattern?: string;
  /** 错误提示（可选） */
  validationMessage?: string;
  /** 下拉选项（editType=select 时使用），格式：每行 label,value */
  options?: string;
  /** 远程数据源配置（remote-select/autocomplete 时使用） */
  remoteTableName?: string;
  remoteQueryFields?: string;
  remoteLabelField?: string;
  remoteValueField?: string;
  remoteSearchFields?: string;
  remotePageSize?: number;
  /** 校验：required 必填 */
  rules?: string;
}

export interface TabTableConfig {
  key: string;
  tab: string;
  /** 明细表表名（可选，供保存前脚本按多表落库） */
  tableName?: string;
  /** 明细表主键（默认 id） */
  primaryKey?: string;
  /** 主从关联：明细中外键列名（如 FID），保存时用主表主键写入每行 */
  foreignKeyField?: string;
  /** 外键取值来自主表哪个字段（不填则与列表 primaryKey 一致，如 FID） */
  mainKeyField?: string;
  columns: TabTableColumn[];
}

const props = withDefaults(
  defineProps<{
    formSchema: VbenFormSchema[];
    tabs: TabTableConfig[];
    /** false 时不渲染内部表单（用于 FormFromDesignerModal：外层已有主表单） */
    showForm?: boolean;
    wrapperClass?: string;
    layout?: string;
    labelWidth?: number;
  }>(),
  { showForm: true },
);

const activeKey = ref(props.tabs[0]?.key ?? '');
const tabDataMap = ref<Record<string, any[]>>({});
const tabDeleteRowsMap = ref<Record<string, any[]>>({});
const remoteOptionsByColumn = ref<Record<string, Array<{ label: string; value: any }>>>({});
const dictionaryOptionsByColumn = ref<Record<string, Array<{ label: string; value: any }>>>({});

// 为每个 tab 初始化空数据
watch(
  () => props.tabs,
  (tabs) => {
    const map: Record<string, any[]> = {};
    const delMap: Record<string, any[]> = {};
    tabs.forEach((t) => {
      map[t.key] = tabDataMap.value[t.key] ?? [];
      delMap[t.key] = tabDeleteRowsMap.value[t.key] ?? [];
    });
    tabDataMap.value = map;
    tabDeleteRowsMap.value = delMap;
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

function columnKey(tabKey: string, field: string) {
  return `${tabKey}::${field}`;
}

/** 单元格存 value（编码/GUID），表格展示 label（汉字等） */
function resolveOptionLabel(
  cellValue: unknown,
  getOpts: () => Array<{ label?: string; value?: any }>,
): string {
  if (cellValue === null || cellValue === undefined) return '';
  const s = String(cellValue).trim();
  if (!s) return '';
  const opts = getOpts();
  const hit = opts.find((o) => String(o.value ?? '').trim().toLowerCase() === s.toLowerCase());
  if (hit?.label != null && String(hit.label).trim() !== '') return String(hit.label);
  return s;
}

/** SQL Server 等常用的「空日期」哨兵（整段无有效业务日期） */
function isSqlSentinelDateTime(s: string): boolean {
  const t = s.trim();
  return /^1900-01-01/i.test(t) || /^0001-01-01/i.test(t);
}

/**
 * 行内「时间」控件：接口/库里的 datetime 常写成 1900-01-01 10:38:00 只表示时刻，须抽出 HH:mm；
 * 仅哨兵日 + 00:00:00（或无时间）视为空。
 */
function normalizeTimeStringForTabCell(s: string): string {
  if (!s) return '';

  const sentinel = s.match(
    /^(?:1900-01-01|0001-01-01)(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?)?/i,
  );
  if (sentinel) {
    const hh = sentinel[1] ?? '00';
    const mm = sentinel[2] ?? '00';
    const ss = sentinel[3] ?? '00';
    if (hh === '00' && mm === '00' && ss === '00') return '';
    return `${hh}:${mm}`;
  }

  if (s.includes('T')) {
    const tail = (s.split('T')[1] ?? '').trim();
    const hm = tail.match(/^(\d{2}:\d{2})(?::\d{2})?/);
    if (hm) return hm[1];
  }

  const withDate = s.match(/^\d{4}-\d{2}-\d{2}[ T](\d{2}:\d{2})(?::\d{2})?(?:\.\d+)?/);
  if (withDate) return withDate[1];

  const hm = s.match(/^(\d{2}:\d{2})(?::\d{2})?(?:\.\d+)?$/);
  return hm ? hm[1] : s;
}

/**
 * 接口回填的明细行：ISO 日期时间 / 哨兵日期 → 适合行内 date/time 控件的字符串
 * - editType=date 或字段名以 Date 结尾的 input：YYYY-MM-DD，哨兵→空
 * - editType=time 或字段名以 Time 结尾的 input：HH:mm；哨兵日仅当时间为 00:00:00 时→空
 */
function normalizeValueForTabColumn(col: TabTableColumn, v: any): any {
  const et = col.editType ?? 'input';
  const treatAsDate = et === 'date' || (et === 'input' && /date$/i.test(col.field));
  const treatAsTime = et === 'time' || (et === 'input' && /time$/i.test(col.field));

  if (treatAsDate) {
    if (v === null || v === undefined) return '';
    const s = String(v).trim();
    if (!s) return '';
    if (isSqlSentinelDateTime(s)) return '';
    const m = s.match(/^(\d{4}-\d{2}-\d{2})/);
    return m ? m[1] : s;
  }
  if (treatAsTime) {
    if (v === null || v === undefined) return '';
    const s = String(v).trim();
    if (!s) return '';
    return normalizeTimeStringForTabCell(s);
  }
  return v;
}

function normalizeDetailRowsForTab(tab: TabTableConfig, rows: any[]): any[] {
  const cols = tab.columns ?? [];
  return rows.map((row) => {
    const out: Record<string, any> = { ...(row ?? {}) };
    for (const col of cols) {
      if (!Object.prototype.hasOwnProperty.call(out, col.field)) continue;
      out[col.field] = normalizeValueForTabColumn(col, out[col.field]);
    }
    return out;
  });
}

async function loadRemoteOptionsForTabs(tabs: TabTableConfig[]) {
  const nextMap = { ...remoteOptionsByColumn.value };
  for (const tab of tabs || []) {
    for (const col of tab.columns || []) {
      if (!['remote-select', 'autocomplete'].includes(col.editType ?? '')) continue;
      const tableName = String(col.remoteTableName ?? '').trim();
      const labelField = String(col.remoteLabelField ?? '').trim();
      const valueField = String(col.remoteValueField ?? '').trim();
      if (!tableName || !labelField || !valueField) continue;

      const ck = columnKey(tab.key, col.field);
      try {
        const req: any = {
          TableName: tableName,
          Page: 1,
          PageSize: Number(col.remotePageSize ?? 50) || 50,
          SortBy: labelField,
          SortOrder: 'asc',
        };
        const qf = String(col.remoteQueryFields ?? '').trim();
        if (qf) req.QueryField = qf;

        const searchFields = String(col.remoteSearchFields ?? '').trim();
        if (searchFields) {
          req.Where = {
            Logic: 'OR',
            Conditions: searchFields.split(',').map((f) => ({
              Field: String(f ?? '').trim(),
              Operator: 'contains',
              Value: '',
            })),
            Groups: [],
          };
        }

        const res = await requestClient.post<any>(backendApi('DynamicQueryBeta/queryforvben'), req);
        const items = res?.items ?? [];
        nextMap[ck] = (items as any[]).map((row) => ({
          label: row?.[labelField] ?? row?.[valueField] ?? '',
          value: row?.[valueField],
        }));
      } catch {
        nextMap[ck] = [];
      }
    }
  }
  remoteOptionsByColumn.value = nextMap;
}

async function loadDictionaryOptionsForTabs(tabs: TabTableConfig[]) {
  const nextMap = { ...dictionaryOptionsByColumn.value };
  for (const tab of tabs || []) {
    for (const col of tab.columns || []) {
      if (col.editType !== 'select' || col.dataSourceType !== 'dictionary') continue;
      const dictionaryId = String(col.dictionaryId ?? '').trim();
      const ck = columnKey(tab.key, col.field);
      if (!dictionaryId) {
        nextMap[ck] = [];
        continue;
      }
      try {
        const res = await requestClient.post<{ items?: any[]; records?: any[] }>(
          backendApi('DynamicQueryBeta/queryforvben'),
          {
            TableName: 'vben_t_base_dictionary_detail',
            Page: 1,
            PageSize: 2000,
            SortBy: 'sort',
            SortOrder: 'asc',
            SimpleWhere: { dictionary_id: dictionaryId },
          },
        );
        const raw = (res as any)?.data ?? res;
        const list = raw?.items ?? raw?.records ?? [];
        nextMap[ck] = (list as any[]).map((r: any) => ({
          label: r?.name ?? r?.label ?? '',
          value: String(r?.value ?? r?.name ?? ''),
        }));
      } catch {
        nextMap[ck] = [];
      }
    }
  }
  dictionaryOptionsByColumn.value = nextMap;
}

// 根据 columns 生成 gridOptions
function buildGridOptions(tab: TabTableConfig, data: any[]) {
  const pk = (tab.primaryKey || 'id').trim() || 'id';
  const baseColumns = [
    { type: 'checkbox', width: 50 },
    { type: 'seq', width: 50 },
  ];
  const dataColumns = (tab.columns || []).filter((col) => col.visible !== false).map((col) => {
    const editType = col.editType ?? 'input';
    let editRender: Record<string, any> = { name: 'input' };
    if (editType === 'input-number') {
      editRender = { name: 'input', attrs: { type: 'number' } };
    } else if (editType === 'select') {
      const ckSel = columnKey(tab.key, col.field);
      const opts =
        col.dataSourceType === 'dictionary'
          ? (dictionaryOptionsByColumn.value[ckSel] ?? [])
          : parseOptions(col.options ?? '');
      editRender = { name: 'select', options: opts };
    } else if (editType === 'date') {
      editRender = { name: 'input', attrs: { type: 'date' } };
    } else if (editType === 'time') {
      editRender = { name: 'input', attrs: { type: 'time' } };
    } else if (editType === 'switch') {
      editRender = { name: 'input', attrs: { type: 'checkbox' } };
    } else if (editType === 'remote-select' || editType === 'autocomplete') {
      const opts = remoteOptionsByColumn.value[columnKey(tab.key, col.field)] ?? [];
      editRender = { name: 'select', options: opts };
    } else {
      editRender = { name: 'input' };
    }
    const colDef: Record<string, any> = {
      field: col.field,
      title: col.title,
      width: 120,
      editRender,
    };
    const ckFmt = columnKey(tab.key, col.field);
    const fieldName = col.field;
    if (editType === 'select') {
      if (col.dataSourceType === 'dictionary') {
        colDef.formatter = (p: any) =>
          resolveOptionLabel(
            p?.cellValue ?? p?.row?.[fieldName],
            () => dictionaryOptionsByColumn.value[ckFmt] ?? [],
          );
      } else {
        colDef.formatter = (p: any) =>
          resolveOptionLabel(p?.cellValue ?? p?.row?.[fieldName], () => parseOptions(col.options ?? ''));
      }
    } else if (editType === 'remote-select' || editType === 'autocomplete') {
      colDef.formatter = (p: any) =>
        resolveOptionLabel(
          p?.cellValue ?? p?.row?.[fieldName],
          () => remoteOptionsByColumn.value[ckFmt] ?? [],
        );
    }
    const vt = col.validationType ?? (String(col.rules ?? '').includes('required') ? 'required' : 'none');
    if (vt === 'required') {
      colDef.editRule = [{ required: true, message: col.validationMessage || `${col.title}不能为空` }];
    }
    return colDef;
  });
  return {
    data,
    columns: [...baseColumns, ...dataColumns],
    rowConfig: { keyField: pk },
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

watch(
  () => props.tabs,
  async (tabs) => {
    await loadDictionaryOptionsForTabs(tabs ?? []);
    await loadRemoteOptionsForTabs(tabs ?? []);
    if (currentTab.value) {
      gridApi.setState({ gridOptions: { ...buildGridOptions(currentTab.value, currentData.value) } });
    }
  },
  { immediate: true, deep: true },
);

function addRow() {
  if (!currentTab.value) return;
  const tab = currentTab.value;
  const pk = (tab.primaryKey || 'id').trim() || 'id';
  const newRow: Record<string, any> = {};
  tab.columns.forEach((col) => {
    if (col.field === pk) return;
    if (col.editType === 'input-number') newRow[col.field] = 0;
    else if (col.editType === 'date') newRow[col.field] = '';
    else if (col.editType === 'time') newRow[col.field] = '';
    else if (col.editType === 'switch') newRow[col.field] = false;
    else newRow[col.field] = '';
  });
  // 主键勿留空：Vxe keyField 为空时会生成 row_xxx 写进主键列，SQL uniqueidentifier 转换失败
  newRow[pk] = pk === 'id' ? '' : crypto.randomUUID();
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
  const pk = (tab.primaryKey || 'id').trim();
  const deleted = tabDeleteRowsMap.value[tab.key] ?? [];

  // 记录删除主键（新建且无主键的行不加入 deleteRows）
  rows.forEach((r: any) => {
    const keyVal = r?.[pk];
    if (keyVal !== undefined && keyVal !== null && String(keyVal).trim() !== '') {
      if (!deleted.some((d: any) => String(d?.[pk]) === String(keyVal))) {
        deleted.push({ [pk]: keyVal });
      }
    }
  });
  tabDeleteRowsMap.value = { ...tabDeleteRowsMap.value, [tab.key]: deleted };

  const data = (tabDataMap.value[tab.key] ?? []).filter((r) => {
    if (pk && r?.[pk] !== undefined && r?.[pk] !== null) {
      return !rows.some((row: any) => String(row?.[pk]) === String(r?.[pk]));
    }
    return !rows.some((row: any) => row === r);
  });
  tabDataMap.value = { ...tabDataMap.value, [tab.key]: data };
  currentData.value = [...data];
  gridApi.setState({ gridOptions: { ...buildGridOptions(tab, data) } });
  gridApi.grid?.clearCheckboxRow?.();
  message.success('已删除');
}

/**
 * 将当前页签 Vxe 表格中「正在编辑」的单元格写回行对象，并同步到 tabDataMap。
 * 否则点保存时 getTabDataMap 仍是旧值（用户明明改了界面却入库默认/空值）。
 */
async function flushActiveGridToTabDataMap() {
  const grid = gridApi.grid as any;
  const key = activeKey.value;
  if (!grid || !key) return;
  try {
    if (typeof grid.clearEdit === 'function') {
      await grid.clearEdit();
    } else if (typeof grid.clearActived === 'function') {
      await grid.clearActived();
    }
  } catch {
    /* 无编辑态时部分版本会报错，忽略 */
  }
  let full: any[] = [];
  try {
    const pack = typeof grid.getTableData === 'function' ? grid.getTableData() : null;
    if (pack?.fullData && Array.isArray(pack.fullData)) {
      full = pack.fullData;
    } else if (typeof grid.getFullData === 'function') {
      const fd = grid.getFullData();
      if (fd?.fullData && Array.isArray(fd.fullData)) full = fd.fullData;
    }
  } catch {
    full = tabDataMap.value[key] ?? [];
  }
  const rows = full.map((r: any) => (r && typeof r === 'object' ? { ...r } : r));
  tabDataMap.value = { ...tabDataMap.value, [key]: rows };
  if (currentTab.value?.key === key) {
    currentData.value = [...rows];
  }
}

/** 保存前调用：先刷当前页签，再读全部分组数据 */
async function flushPendingGridEdits() {
  await flushActiveGridToTabDataMap();
}

/** 供父组件保存时读取：按页签 key 分组的行数据（浅拷贝行对象） */
function getTabDataMap(): Record<string, any[]> {
  const out: Record<string, any[]> = {};
  for (const k of Object.keys(tabDataMap.value)) {
    out[k] = (tabDataMap.value[k] ?? []).map((r) => ({ ...r }));
  }
  return out;
}

/** 供父组件保存时读取：按页签 key 分组的 deleteRows（用于 datasave-multi） */
function getTabDeleteRowsMap(): Record<string, any[]> {
  const out: Record<string, any[]> = {};
  for (const k of Object.keys(tabDeleteRowsMap.value)) {
    out[k] = (tabDeleteRowsMap.value[k] ?? []).map((r) => ({ ...r }));
  }
  return out;
}

async function setActiveTab(key: string) {
  if (!key) return;
  await flushActiveGridToTabDataMap();
  activeKey.value = key;
}

/** 编辑回填：替换某页签表格数据，并清空该页签的 deleteRows */
function setTabRows(tabKey: string, rows: any[]) {
  const tab = props.tabs.find((t) => t.key === tabKey);
  const raw = Array.isArray(rows) ? rows.map((r) => ({ ...(r ?? {}) })) : [];
  const list = tab ? normalizeDetailRowsForTab(tab, raw) : raw;
  tabDataMap.value = { ...tabDataMap.value, [tabKey]: list };
  tabDeleteRowsMap.value = { ...tabDeleteRowsMap.value, [tabKey]: [] };
  if (currentTab.value?.key === tabKey) {
    currentData.value = [...list];
    gridApi.setState({ gridOptions: { ...buildGridOptions(currentTab.value, list) } });
  }
}

/** 新增或切换主表前：清空所有页签行与删除记录 */
function clearAllTabRows() {
  const map: Record<string, any[]> = {};
  const delMap: Record<string, any[]> = {};
  for (const t of props.tabs ?? []) {
    map[t.key] = [];
    delMap[t.key] = [];
  }
  tabDataMap.value = map;
  tabDeleteRowsMap.value = delMap;
  if (currentTab.value) {
    const data = map[currentTab.value.key] ?? [];
    currentData.value = [...data];
    gridApi.setState({ gridOptions: { ...buildGridOptions(currentTab.value, data) } });
  }
}

function isEmptyValue(v: unknown) {
  return v === null || v === undefined || String(v).trim() === '';
}

function isValidDateValue(v: unknown) {
  if (isEmptyValue(v)) return true;
  const s = String(v).trim();
  const r = /^\d{4}-\d{2}-\d{2}$/;
  if (!r.test(s)) return false;
  const d = new Date(`${s}T00:00:00`);
  return !Number.isNaN(d.getTime());
}

function isValidTimeValue(v: unknown) {
  if (isEmptyValue(v)) return true;
  const s = String(v).trim();
  return /^([01]\d|2[0-3]):([0-5]\d)(:[0-5]\d)?$/.test(s);
}

function isValidNumberValue(v: unknown) {
  if (isEmptyValue(v)) return true;
  return /^-?\d+(\.\d+)?$/.test(String(v).trim());
}

function isValidEmailValue(v: unknown) {
  if (isEmptyValue(v)) return true;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(v).trim());
}

function isValidPhoneValue(v: unknown) {
  if (isEmptyValue(v)) return true;
  return /^1\d{10}$/.test(String(v).trim());
}

function checkValueByValidationType(col: TabTableColumn, v: unknown): string {
  const vt = col.validationType ?? (String(col.rules ?? '').includes('required') ? 'required' : 'none');
  const title = col.title || col.field;
  if (vt === 'none') return '';
  if (vt === 'required') {
    return isEmptyValue(v) ? (col.validationMessage || `${title}不能为空`) : '';
  }
  if (isEmptyValue(v)) return '';

  if (vt === 'date' && !isValidDateValue(v)) return col.validationMessage || `${title}格式不正确，应为 YYYY-MM-DD`;
  if (vt === 'time' && !isValidTimeValue(v)) return col.validationMessage || `${title}格式不正确，应为 HH:mm 或 HH:mm:ss`;
  if (vt === 'number' && !isValidNumberValue(v)) return col.validationMessage || `${title}必须是数字`;
  if (vt === 'email' && !isValidEmailValue(v)) return col.validationMessage || `${title}邮箱格式不正确`;
  if (vt === 'phone' && !isValidPhoneValue(v)) return col.validationMessage || `${title}手机号格式不正确`;
  if (vt === 'regex') {
    const pattern = String(col.validationPattern ?? '').trim();
    if (!pattern) return '正则校验未配置表达式';
    try {
      const reg = new RegExp(pattern);
      if (!reg.test(String(v))) return col.validationMessage || `${title}格式不符合规则`;
    } catch {
      return '正则表达式无效';
    }
  }
  return '';
}

function validateAllTabs(): { valid: true } | { valid: false; message: string; tabKey?: string } {
  for (const tab of props.tabs ?? []) {
    const rows = tabDataMap.value[tab.key] ?? [];
    const cols = (tab.columns ?? []).filter((c) => c.visible !== false);
    if (!cols.length) continue;

    for (let ri = 0; ri < rows.length; ri++) {
      const row = rows[ri] ?? {};
      for (const col of cols) {
        const v = row[col.field];
        const err = checkValueByValidationType(col, v);
        if (err) {
          return {
            valid: false,
            tabKey: tab.key,
            message: `页签「${tab.tab}」第 ${ri + 1} 行「${col.title || col.field}」${err}`,
          };
        }
      }
    }
  }
  return { valid: true };
}

async function onTabsChange(nextKey: string) {
  if (nextKey === activeKey.value) return;
  await flushActiveGridToTabDataMap();
  activeKey.value = nextKey;
}

defineExpose({
  getTabDataMap,
  getTabDeleteRowsMap,
  validateAllTabs,
  setActiveTab,
  setTabRows,
  clearAllTabRows,
  flushPendingGridEdits,
  flushActiveGridToTabDataMap,
});
</script>

<template>
  <div class="form-tabs-table-preview">
    <div v-if="showForm && formSchema.length" class="mb-4">
      <Form />
    </div>
    <div v-if="tabs.length" :class="showForm && formSchema.length ? 'mt-4' : ''">
      <Tabs :active-key="activeKey" type="card" @change="onTabsChange">
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
