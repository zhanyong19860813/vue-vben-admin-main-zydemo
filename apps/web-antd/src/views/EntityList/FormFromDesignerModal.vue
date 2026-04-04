<script setup lang="ts">
/**
 * 表单设计器配置的表单 - 弹窗内容
 * 支持数据字典、控件联动、打开时脚本(onOpenScript)、保存前脚本(beforeSubmitScript)
 * 布局 layout.layoutType === 'formTabsTable' 时：上主表单 + 下页签内表格（表格数据在保存前脚本的 params.tabTables 中）
 */
import { h, ref, toRaw, watch, nextTick, computed } from 'vue';
import { Button, message, Tag } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import type { VbenFormSchema } from '#/adapter/form';
import type { FormLinkageConfig } from '../demos/form-designer/form-designer.types';
import { resolveDictionaryInSchema } from '../demos/form-designer/resolveDictionarySchema';
import FormTabsTablePreview from '../demos/form-designer/FormTabsTablePreview.vue';
import type { TabTableConfig } from '../demos/form-designer/FormTabsTablePreview.vue';

const props = withDefaults(
  defineProps<{
    formSchema: VbenFormSchema[];
    saveEntityName: string;
    primaryKey?: string;
    formTitle?: string;
    layout?: {
      cols?: number;
      labelWidth?: number;
      labelAlign?: string;
      layout?: string;
      /** formTabsTable = 上表单 + 下页签（页签内为表格） */
      layoutType?: string;
      /** 追加到表单栅格容器，如 gap、max-w 等 */
      wrapperClass?: string;
      /** 表单项底部间距 px（内联样式，不依赖 Tailwind 扫描 DB 里的 class） */
      formItemGapPx?: number;
    };
    /** 与 layoutType=formTabsTable 配套：页签与表格列配置 */
    tabs?: TabTableConfig[];
    /** 编辑回填：传入选中行数据 */
    initialValues?: Record<string, any>;
    /** 打开弹窗后执行的脚本，可对表单赋值。参数: params={ mode, initialValues, setTabRows, backendApi }, formApi, request */
    onOpenScript?: string;
    /** 保存前执行的脚本，可校验或修改数据。参数: params={ formValues, tabTables, tabConfigs(含 foreignKeyField/mainKeyField) }, formApi。返回 { valid: false, message } 阻止保存；返回 { formValues } 用新值提交 */
    beforeSubmitScript?: string;
    /** 是否显示「数据回填调试」折叠区（列表行→主表对照；formTabsTable 时含明细快照） */
    showFillDebug?: boolean;
  }>(),
  {
    primaryKey: 'id',
    formTitle: '新增',
    tabs: () => [],
    showFillDebug: false,
  }
);

const tabsPreviewRef = ref<InstanceType<typeof FormTabsTablePreview> | null>(null);

const isFormTabsTable = computed(
  () =>
    props.layout?.layoutType === 'formTabsTable' &&
    Array.isArray(props.tabs) &&
    props.tabs.length > 0,
);

const emit = defineEmits<{
  success: [];
  cancel: [];
}>();

const submitting = ref(false);

/** layout.formItemGapPx：兼容 JSON/接口成字符串；并显式绑到 <Form> 上，否则 useVbenForm 初始 state 可能进不了内层 Form 的 props */
function resolveFormItemGapPx(raw: unknown): number | undefined {
  if (raw === null || raw === undefined || raw === '') return undefined;
  const n = typeof raw === 'number' ? raw : Number(raw);
  if (!Number.isFinite(n) || n < 0 || n > 120) return undefined;
  return Math.round(n);
}

const layoutFormItemGapPx = computed(() =>
  resolveFormItemGapPx(props.layout?.formItemGapPx),
);

const wrapperClass = computed(() =>
  [
    props.layout?.cols === 1
      ? 'grid-cols-1'
      : props.layout?.cols === 3
        ? 'grid-cols-1 md:grid-cols-2 lg:grid-cols-3'
        : 'grid-cols-1 md:grid-cols-2',
    'gap-x-6',
    layoutFormItemGapPx.value !== undefined ? 'gap-y-0' : 'gap-y-2',
    props.layout?.wrapperClass,
  ]
    .filter(Boolean)
    .join(' '),
);

const [Form, formApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as VbenFormSchema[],
  layout: 'horizontal',
  commonConfig: {
    labelWidth: props.layout?.labelWidth ?? 100,
    labelAlign: (props.layout?.labelAlign as any) ?? 'right',
  } as any,
  handleValuesChange: (values, changedFields) => {
    runLinkageOnChange(values, changedFields);
  },
});

/**
 * 通用联动：根据 schema 中的 linkage 配置，当某字段变化时请求接口并填充映射字段
 */
function runLinkageOnChange(values: Record<string, any>, changedFields: string[]) {
  const schema = props.formSchema ?? [];
  for (const item of schema) {
    const linkage = (item as any).linkage as FormLinkageConfig | undefined;
    if (!linkage?.enabled || !linkage.responseMap || Object.keys(linkage.responseMap).length === 0)
      continue;
    if (!changedFields?.includes(item.fieldName as string)) continue;

    const paramKey = linkage.paramKey ?? item.fieldName;
    const paramValue = paramKey ? values[paramKey] : undefined;
    if (paramValue == null || String(paramValue).trim() === '') continue;

    let url: string;
    let method: 'GET' | 'POST' = linkage.method ?? 'GET';
    if (linkage.type === 'preset' && linkage.preset === 'employee') {
      url = `${backendApi('FormLookup/Employee')}?value=${encodeURIComponent(String(paramValue))}`;
      method = 'GET';
    } else if (linkage.type === 'api' && linkage.apiUrl) {
      const base = linkage.apiUrl.startsWith('http') ? linkage.apiUrl : backendApi(linkage.apiUrl);
      url = method === 'GET' ? `${base}${base.includes('?') ? '&' : '?'}value=${encodeURIComponent(String(paramValue))}` : base;
    } else {
      continue;
    }

    const thenSet = (data: Record<string, any> | null) => {
      if (!data || typeof data !== 'object') return;
      const toSet: Record<string, any> = {};
      for (const [apiKey, formFieldName] of Object.entries(linkage.responseMap!)) {
        const val = data[apiKey] ?? data[apiKey.toLowerCase()] ?? data[apiKey.toUpperCase()];
        if (formFieldName && val !== undefined) toSet[formFieldName] = val;
      }
      if (Object.keys(toSet).length) formApi.setValues(toSet);
    };

    if (method === 'GET') {
      requestClient.get<{ code?: number; data?: Record<string, any> }>(url).then((res) => {
        const data = res && typeof res === 'object' && res.data != null ? res.data : (Array.isArray(res) ? null : (res as any));
        thenSet(data && typeof data === 'object' ? data : null);
      }).catch(() => {});
    } else {
      requestClient.post<{ code?: number; data?: Record<string, any> }>(url, { value: paramValue }).then((res) => {
        const data = res && typeof res === 'object' && res.data != null ? res.data : (Array.isArray(res) ? null : (res as any));
        thenSet(data && typeof data === 'object' ? data : null);
      }).catch(() => {});
    }
  }
}

/** 供打开时脚本调用的 request 方法：request(url, { method?, data? }) */
function createRequestHelper() {
  return async function request(url: string, options?: { method?: string; data?: any }) {
    const method = (options?.method ?? 'GET').toUpperCase();
    if (method === 'GET') {
      return requestClient.get(url);
    }
    return requestClient.post(url, options?.data);
  };
}

/** 运行脚本前做轻量兼容：移除常见 TS `as xxx` 断言，避免 new Function 语法报错 */
function sanitizeScriptForRuntime(script: string): string {
  if (!script) return script;
  // 仅处理最常见的变量后置断言：foo as any / as string / as SomeType
  return script.replace(/\s+as\s+[A-Za-z_$][\w.$<>\[\]\s|&,:?]*/g, '');
}

/** 是否为合法 GUID（与 SQL Server uniqueidentifier 兼容，含 {GUID} 形式） */
function isValidGuidString(v: unknown): boolean {
  if (v === null || v === undefined) return false;
  let s = String(v).trim();
  if (s.startsWith('{') && s.endsWith('}')) s = s.slice(1, -1);
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(s);
}

function canonicalGuidString(v: unknown): string {
  let s = String(v ?? '').trim();
  if (s.startsWith('{') && s.endsWith('}')) s = s.slice(1, -1);
  return s;
}

/**
 * 明细主键规范化：空、0、Vxe 内部 row_*、非纯数字且非 GUID → 生成新 GUID。
 * 避免 DetailID=row_1706 等导致「将字符串转换为 uniqueidentifier 时失败」。
 * 纯数字主键（自增 int）保留原样。
 */
function normalizeDetailPrimaryKey(pkVal: unknown): string {
  const s = pkVal === null || pkVal === undefined ? '' : String(pkVal).trim();
  if (!s || s === '0') return crypto.randomUUID();
  if (/^row_/i.test(s)) return crypto.randomUUID();
  if (/^\d+$/.test(s)) return s;
  if (isValidGuidString(pkVal)) return canonicalGuidString(pkVal);
  return crypto.randomUUID();
}

/** 从列表行取主键值（兼容列名大小写不一致） */
function getPrimaryKeyValueFromRow(row: Record<string, any> | undefined, pk: string): string {
  if (!row || typeof row !== 'object') return '';
  const v = row[pk];
  if (v != null && String(v).trim() !== '') return String(v).trim();
  const lower = pk.toLowerCase();
  const origKey = Object.keys(row).find((k) => k.toLowerCase() === lower);
  if (origKey != null && row[origKey] != null && String(row[origKey]).trim() !== '') {
    return String(row[origKey]).trim();
  }
  return '';
}

/**
 * 编辑时按页签 tableName + foreignKeyField 拉取明细（列表行通常只有主表字段）
 */
async function syncTabTablesFromDetailApi() {
  if (!isFormTabsTable.value) return;
  let preview = tabsPreviewRef.value as
    | { setTabRows?: (k: string, r: any[]) => void; clearAllTabRows?: () => void }
    | null;
  for (let i = 0; i < 8 && !preview?.setTabRows; i++) {
    await nextTick();
    preview = tabsPreviewRef.value as any;
  }
  if (!preview?.setTabRows || !preview?.clearAllTabRows) return;

  const row = props.initialValues;
  const pkField = props.primaryKey || 'id';
  const pkVal = row && Object.keys(row).length ? getPrimaryKeyValueFromRow(row, pkField) : '';

  if (!pkVal) {
    preview.clearAllTabRows();
    return;
  }

  preview.clearAllTabRows();
  const tabs = props.tabs ?? [];
  for (const t of tabs) {
    const tn = String(t.tableName ?? '').trim();
    const fk = String((t as any).foreignKeyField ?? '').trim();
    if (!tn || !fk) continue;
    try {
      const res = await requestClient.post<{ items?: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), {
        TableName: tn,
        Page: 1,
        PageSize: 2000,
        SimpleWhere: { [fk]: pkVal },
      });
      const items = res?.items ?? [];
      preview.setTabRows(t.key, items);
    } catch (e) {
      console.error('[FormFromDesigner] 明细加载失败', t.tab, t.tableName, e);
      preview.setTabRows(t.key, []);
    }
  }
}

/** 执行打开时脚本：可对表单控件赋值，支持异步（如调接口后 setValues） */
async function runOnOpenScript() {
  const script = props.onOpenScript?.trim();
  if (!script) return;
  try {
    const params = {
      mode: props.initialValues && Object.keys(props.initialValues).length ? 'edit' : 'add',
      initialValues: props.initialValues ?? {},
      backendApi, // 脚本内可 request(backendApi('FormLookup/Employee') + '?value=xxx')
      /** 写入某页签明细行（可覆盖自动按外键加载的结果） */
      setTabRows: (tabKey: string, rows: any[]) =>
        (tabsPreviewRef.value as any)?.setTabRows?.(tabKey, rows),
    };
    const request = createRequestHelper();
    const runtimeScript = sanitizeScriptForRuntime(script);
    const fn = new Function('params', 'formApi', 'request', runtimeScript);
    const result = fn(params, formApi, request);
    if (result && typeof (result as Promise<unknown>).then === 'function') {
      await result;
    }
  } catch (e) {
    console.error('[onOpenScript]', e);
    message.error('打开时脚本执行失败: ' + (e as Error).message);
  }
}

/** 执行保存前脚本：可校验（返回 { valid: false, message }）或修改数据（返回 { formValues }） */
async function runBeforeSubmitScript(
  formValues: Record<string, any>,
  tabTables: Record<string, any[]>,
  tabConfigs?: Array<{
    key: string;
    tab: string;
    tableName?: string;
    primaryKey?: string;
    foreignKeyField?: string;
    mainKeyField?: string;
  }>,
): Promise<{ valid: true; formValues?: Record<string, any> } | { valid: false; message: string }> {
  const script = props.beforeSubmitScript?.trim();
  if (!script) return { valid: true };
  try {
    const params = {
      formValues: { ...formValues },
      tabTables: { ...tabTables },
      tabConfigs: (tabConfigs ?? []).map((t) => ({ ...t })),
    };
    const runtimeScript = sanitizeScriptForRuntime(script);
    const fn = new Function('params', 'formApi', runtimeScript);
    const result = fn(params, formApi);
    const resolved = result && typeof (result as Promise<unknown>).then === 'function' ? await result : result;
    if (resolved && resolved.valid === false) {
      return { valid: false, message: resolved.message ?? '校验不通过' };
    }
    if (resolved && resolved.formValues && typeof resolved.formValues === 'object') {
      return { valid: true, formValues: resolved.formValues };
    }
    return { valid: true };
  } catch (e) {
    console.error('[beforeSubmitScript]', e);
    message.error('保存前脚本执行失败: ' + (e as Error).message);
    return { valid: false, message: (e as Error).message };
  }
}

/**
 * 将行数据按表单 schema 的 fieldName 映射，兼容后端返回 PascalCase 等情况
 */
function mapRowToSchemaFields(
  row: Record<string, any>,
  schema: VbenFormSchema[],
): Record<string, any> {
  if (!row || !schema?.length) return row ?? {};
  const fieldNames = new Set(schema.map((s) => s.fieldName).filter(Boolean));
  const rowKeysLower = new Map<string, string>(
    Object.keys(row).map((k) => [k.toLowerCase(), k]),
  );
  const result: Record<string, any> = {};
  for (const fn of fieldNames) {
    if (fn in row) {
      result[fn] = row[fn];
    } else {
      const lower = fn.toLowerCase();
      const origKey = rowKeysLower.get(lower);
      if (origKey !== undefined) result[fn] = row[origKey];
    }
  }
  return result;
}

type FillMatchType = 'exact' | 'case_insensitive' | 'missing';

interface FillDiagRow {
  key: string;
  fieldName: string;
  label: string;
  matchType: FillMatchType;
  sourceKey: string;
  valuePreview: string;
}

function buildFillDiagnostics(
  row: Record<string, any> | undefined,
  schema: VbenFormSchema[],
): { tableRows: FillDiagRow[]; mapped: Record<string, any>; unusedKeys: string[] } {
  const tableRows: FillDiagRow[] = [];
  if (!schema?.length) {
    return { tableRows, mapped: {}, unusedKeys: row ? Object.keys(row) : [] };
  }
  if (!row || !Object.keys(row).length) {
    for (const s of schema) {
      const fn = (s.fieldName as string) || '';
      if (!fn) continue;
      tableRows.push({
        key: fn,
        fieldName: fn,
        label: String((s as any).label ?? ''),
        matchType: 'missing',
        sourceKey: '—',
        valuePreview: '（无列表行，新增模式）',
      });
    }
    return { tableRows, mapped: {}, unusedKeys: [] };
  }

  const rowKeysLower = new Map<string, string>(
    Object.keys(row).map((k) => [k.toLowerCase(), k]),
  );
  const usedRowKeys = new Set<string>();
  const mapped = mapRowToSchemaFields(row, schema);

  for (const s of schema) {
    const fn = (s.fieldName as string) || '';
    if (!fn) continue;
    let matchType: FillMatchType = 'missing';
    let sourceKey = '—';
    let raw: any;

    if (fn in row) {
      matchType = 'exact';
      sourceKey = fn;
      raw = row[fn];
      usedRowKeys.add(fn);
    } else {
      const orig = rowKeysLower.get(fn.toLowerCase());
      if (orig !== undefined) {
        matchType = 'case_insensitive';
        sourceKey = orig;
        raw = row[orig];
        usedRowKeys.add(orig);
      } else {
        raw = undefined;
      }
    }

    const valuePreview = formatDebugValue(raw);
    tableRows.push({
      key: fn,
      fieldName: fn,
      label: String((s as any).label ?? ''),
      matchType,
      sourceKey,
      valuePreview,
    });
  }

  const unusedKeys = Object.keys(row).filter((k) => !usedRowKeys.has(k));
  return { tableRows, mapped, unusedKeys };
}

function formatDebugValue(v: unknown): string {
  if (v === null || v === undefined) return String(v);
  if (typeof v === 'object') {
    try {
      const s = JSON.stringify(v);
      return s.length > 120 ? `${s.slice(0, 117)}…` : s;
    } catch {
      return String(v);
    }
  }
  const s = String(v);
  return s.length > 120 ? `${s.slice(0, 117)}…` : s;
}

function isEmptyValue(v: unknown) {
  return v === null || v === undefined || String(v).trim() === '';
}

function isValidDateValue(v: unknown) {
  if (isEmptyValue(v)) return true;
  if (v instanceof Date) return !Number.isNaN(v.getTime());
  const s = String(v).trim();
  const r = /^\d{4}-\d{2}-\d{2}$/;
  if (!r.test(s)) return false;
  const d = new Date(`${s}T00:00:00`);
  return !Number.isNaN(d.getTime());
}

function isValidTimeValue(v: unknown) {
  if (isEmptyValue(v)) return true;
  return /^([01]\d|2[0-3]):([0-5]\d)(:[0-5]\d)?$/.test(String(v).trim());
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

function validateFormBySchema(values: Record<string, any>, schema: VbenFormSchema[]): string {
  for (const s of schema ?? []) {
    const field = String((s as any).fieldName ?? '');
    if (!field) continue;
    const cp = (s as any).componentProps ?? {};
    const vt = String(cp.validationType ?? 'none');
    if (!vt || vt === 'none') continue;
    const v = values[field];
    const label = String((s as any).label ?? field);
    const msg = String(cp.validationMessage ?? '').trim();
    if (isEmptyValue(v)) continue;
    if (vt === 'date' && !isValidDateValue(v)) return msg || `${label}格式不正确，应为 YYYY-MM-DD`;
    if (vt === 'time' && !isValidTimeValue(v)) return msg || `${label}格式不正确，应为 HH:mm 或 HH:mm:ss`;
    if (vt === 'number' && !isValidNumberValue(v)) return msg || `${label}必须是数字`;
    if (vt === 'email' && !isValidEmailValue(v)) return msg || `${label}邮箱格式不正确`;
    if (vt === 'phone' && !isValidPhoneValue(v)) return msg || `${label}手机号格式不正确`;
    if (vt === 'regex') {
      const pattern = String(cp.validationPattern ?? '').trim();
      if (!pattern) return `${label}正则校验未配置表达式`;
      try {
        const reg = new RegExp(pattern);
        if (!reg.test(String(v))) return msg || `${label}格式不符合规则`;
      } catch {
        return `${label}正则表达式无效`;
      }
    }
  }
  return '';
}

function prettyJson(obj: unknown): string {
  try {
    return JSON.stringify(obj ?? {}, null, 2);
  } catch {
    return String(obj);
  }
}

async function copyText(label: string, text: string) {
  try {
    await navigator.clipboard.writeText(text);
    message.success(`已复制${label}`);
  } catch {
    message.error('复制失败，请手动选择文本复制');
  }
}

/** 打开弹窗、映射与 onOpen 脚本执行后的表单快照（用于对照界面是否被脚本改写） */
const formValuesAfterOpen = ref<Record<string, any>>({});
/** 点击保存时最终提交给 datasave-multi 的 payload（调试用） */
const submitPayloadDebug = ref<Record<string, any> | null>(null);

/** 明细页签当前内存快照（与「刷新当前表单值」一并更新；列表行不含明细，明细来自接口加载或手工增删） */
const fillDebugTabSnapshot = ref<{
  summary: Array<{
    key: string;
    tab: string;
    tableName?: string;
    primaryKey?: string;
    foreignKeyField?: string;
    rowCount: number;
    deletePendingCount: number;
  }>;
  tabTables: Record<string, any[]>;
  tabDeleteRows: Record<string, any[]>;
} | null>(null);

function refreshTabTablesDebugSnapshot() {
  if (!isFormTabsTable.value) {
    fillDebugTabSnapshot.value = null;
    return;
  }
  const p = tabsPreviewRef.value as {
    getTabDataMap?: () => Record<string, any[]>;
    getTabDeleteRowsMap?: () => Record<string, any[]>;
  } | null;
  const tabs = props.tabs ?? [];
  const tabTables = p?.getTabDataMap?.() ?? {};
  const tabDeleteRows = p?.getTabDeleteRowsMap?.() ?? {};
  const summary = tabs.map((t) => {
    const rows = tabTables[t.key] ?? [];
    const dels = tabDeleteRows[t.key] ?? [];
    return {
      key: t.key,
      tab: t.tab,
      tableName: t.tableName,
      primaryKey: t.primaryKey,
      foreignKeyField: (t as any).foreignKeyField,
      rowCount: rows.length,
      deletePendingCount: dels.length,
    };
  });
  fillDebugTabSnapshot.value = { summary, tabTables, tabDeleteRows };
}

// AutoComplete 远程查询：为每个 fieldName 维护一份 options 引用
// 这样我们可以在 onSearch 里 splice 内容，让 AntD 组件刷新列表
const autoCompleteOptionsByField = ref<Record<string, any[]>>({});
const autoCompleteRequestSeqByField = ref<Record<string, number>>({});

function toQueryFieldsText(v: unknown): string | undefined {
  if (v === null || v === undefined) return undefined;
  if (Array.isArray(v)) return v.join(',');
  const s = String(v).trim();
  return s || undefined;
}

/**
 * 为 componentProps.dataSourceType === 'query' 的 AutoComplete 注入：
 * - onSearch：用 POST /api/DynamicQueryBeta/queryforvben 拉取候选
 * - onSelect：把选中记录的“其它列”按 fieldName（大小写不敏感）回填到其它表单控件
 *
 * 配置约定（写在 schema item.componentProps 里）：
 * - tableName: string
 * - queryFields: string（列名逗号分隔，建议包含 label/value 以及你要回填的其它列）
 * - labelField: string（展示列，选中后 value 仍会存 valueField）
 * - valueField: string（写入表单的值列）
 * - searchField?: string（模糊匹配列，不填则默认 labelField）
 * - pageSize?: number（默认 10）
 * - responseMap?: Record<string, string> 或 responseMapText?: string（显式映射）
 *   - 含义：{ "查询结果列名": "表单 fieldName" }
 *   - responseMapText 每行：`查询结果列名,表单fieldName`（支持 `:` 或 `=>` 但建议用逗号）
 * - displayColumnsText?: string（下拉多列展示/表头配置，可选）
 *   - 每行：`字段名,表头标题`（例如 name,姓名；code,工号）
 * - dropdownMatchSelectWidth?: number | false（默认 560；AutoComplete 基于 Select，true 时下拉与输入框同宽会把多列压扁）
 */
function attachAutoCompleteRemoteQuery(schema: VbenFormSchema[]): VbenFormSchema[] {
  return (schema ?? []).map((item) => {
    if (item.component !== 'AutoComplete') return item;
    const cp: any = item.componentProps ?? {};
    if (cp?.dataSourceType !== 'query') return item;

    const tableName = String(cp?.tableName ?? '').trim();
    const queryFieldsText = toQueryFieldsText(cp?.queryFields ?? cp?.queryField);
    const labelField = String(cp?.labelField ?? '').trim();
    const valueField = String(cp?.valueField ?? '').trim();
    const searchFieldRaw = cp?.searchField ?? cp?.searchFields ?? labelField;
    const searchFields: string[] = Array.isArray(searchFieldRaw)
      ? searchFieldRaw.map((x) => String(x ?? '').trim()).filter(Boolean)
      : String(searchFieldRaw ?? '')
          .split(',')
          .map((x) => String(x ?? '').trim())
          .filter(Boolean);
    const pageSize = Number(cp?.pageSize ?? 10);

    const displayColumnsParsed = parseDisplayColumnsText(cp?.displayColumnsText ?? '');

    const responseMapObj: Record<string, string> | undefined =
      cp?.responseMap && typeof cp.responseMap === 'object'
        ? (cp.responseMap as Record<string, string>)
        : undefined;

    // responseMapText 是“多行映射文本”，不要走 toQueryFieldsText（它会把数组拼成逗号字符串）
    const responseMapTextRaw = cp?.responseMapText ?? cp?.fieldMapText;
    const responseMapText: string | undefined =
      responseMapTextRaw === null || responseMapTextRaw === undefined
        ? undefined
        : String(responseMapTextRaw).trim() || undefined;

    const responseMapParsed: Record<string, string> | undefined =
      responseMapText
        ? parseMultiLineMap(responseMapText)
        : undefined;

    const responseMap = responseMapObj && Object.keys(responseMapObj).length
      ? responseMapObj
      : responseMapParsed;

    if (!tableName || !labelField || !valueField || !searchFields.length) {
      // 缺配置时不注入行为，避免运行时异常
      return item;
    }

    const fieldName = item.fieldName;
    if (!autoCompleteOptionsByField.value[fieldName]) {
      autoCompleteOptionsByField.value[fieldName] = [];
    }
    const optionsArr = autoCompleteOptionsByField.value[fieldName];

    const nextCp: Record<string, any> = {
      ...cp,
      options: optionsArr,
      // 关闭本地 filter，直接用 onSearch 的远程结果
      filterOption: false,
      // 与输入框同宽时多列表头挤成一列，需固定最小宽度或 false
      dropdownMatchSelectWidth:
        cp?.dropdownMatchSelectWidth === false
          ? false
          : Number.isFinite(Number(cp?.dropdownMatchSelectWidth))
            ? Number(cp.dropdownMatchSelectWidth)
            : 560,
    };

    nextCp.onSearch = async (input: string) => {
      const keyword = String(input ?? '').trim();
      // 空输入：清空
      if (!keyword) {
        optionsArr.splice(0, optionsArr.length);
        return;
      }

      const seq = (autoCompleteRequestSeqByField.value[fieldName] ?? 0) + 1;
      autoCompleteRequestSeqByField.value[fieldName] = seq;

      try {
        const requestBody: any = {
          TableName: tableName,
          Page: 1,
          PageSize: Number.isFinite(pageSize) ? pageSize : 10,
          SortBy: searchFields[0] || labelField,
          SortOrder: 'asc',
          Where: {
            // 多列模糊：name contains xxx OR code contains xxx ...
            Logic: 'OR',
            Conditions: [
              ...searchFields.map((f) => ({
                Field: f,
                Operator: 'contains',
                Value: keyword,
              })),
            ],
            Groups: [],
          },
        };
        // 不填 queryFields 则后端默认 SELECT *
        if (queryFieldsText) requestBody.QueryField = queryFieldsText;

        const res = await requestClient.post<any>(backendApi('DynamicQueryBeta/queryforvben'), requestBody);

        // 丢弃过期请求结果
        if (autoCompleteRequestSeqByField.value[fieldName] !== seq) return;

        const items = res?.items ?? [];
        const nextOptions = (items as any[]).map((row) => {
          const raw = row ?? {};
          return {
            value: raw[valueField],
            label: raw[labelField],
            _raw: raw, // 用于 onSelect 回填其它列
          };
        });

        optionsArr.splice(0, optionsArr.length, ...nextOptions);
      } catch (e) {
        // 查询失败就清空候选
        console.error('[AutoComplete queryforvben] failed', e);
        optionsArr.splice(0, optionsArr.length);
      }
    };

    nextCp.onSelect = async (_value: any, option: any) => {
      const raw = option?._raw ?? option?.raw ?? option;
      if (!raw || typeof raw !== 'object') return;

      const schemaNow = (formApi.getState()?.schema ?? []) as VbenFormSchema[];

      const rawObj = raw as Record<string, any>;
      const rawKeysLower = new Map<string, string>(
        Object.keys(rawObj).map((k) => [k.toLowerCase(), k]),
      );

      // 显式映射优先；默认不做“同名字段自动回填”（避免 fid/FID 等误伤）
      const mapped: Record<string, any> = {};

      if (responseMap && Object.keys(responseMap).length) {
        for (const [fromKey, toField] of Object.entries(responseMap)) {
          if (!toField) continue;
          const direct = fromKey in rawObj ? rawObj[fromKey] : undefined;
          const lower = fromKey?.toLowerCase?.() ?? '';
          const origKey = rawKeysLower.get(lower);
          const val = direct !== undefined
            ? direct
            : (origKey ? rawObj[origKey] : undefined);
          if (val === undefined) continue;
          // 多列映射到同一表单字段时：后写 longdeptname 等若为空串，勿覆盖已有非空值（如 long_name）
          if (
            String(val).trim() === '' &&
            mapped[toField] != null &&
            String(mapped[toField]).trim() !== ''
          ) {
            continue;
          }
          mapped[toField] = val;
        }
      } else if (cp?.fallbackFillSameName === true) {
        // 仅当显式开启时，才按同名字段回填
        const fallback = mapRowToSchemaFields(rawObj, schemaNow);
        if (fallback && typeof fallback === 'object') {
          Object.assign(mapped, fallback);
        }
      }

      // 当前控件 fieldName 本身由 v-model 已经写入，无需在这里重复设置
      if (fieldName in mapped) delete mapped[fieldName];

      if (Object.keys(mapped).length > 0) {
        await formApi.setValues(mapped);
        await refreshFormValuesSnapshot();
      }
    };

    // 参考静态 demo：自定义下拉渲染多列（含表头）
    // displayColumnsText 不填时：默认把 queryFields 作为展示列，表头标题显示字段名
    nextCp.dropdownRender = () => {
      const cols =
        displayColumnsParsed.length > 0
          ? displayColumnsParsed
          : (queryFieldsText ?? '')
              .split(',')
              .map((x) => String(x ?? '').trim())
              .filter(Boolean)
              .map((f) => ({ field: f, title: f }));

      const headerRowStyle =
        'display:flex; gap:12px; align-items:center; justify-content:flex-start; padding:6px 4px; background:#fafafa; border-bottom:1px solid #f0f0f0; font-weight:600; font-size:12px; color:#666;';
      const defaultCell =
        'flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;';

      /** 三列（工号/姓名/部门）时用固定比例，避免与输入框同宽时叠在一起 */
      function colStyle(idx: number, total: number): string {
        if (total === 3) {
          if (idx === 0) {
            return 'width:100px;min-width:100px;max-width:120px;flex-shrink:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;';
          }
          if (idx === 1) {
            return 'width:120px;min-width:100px;flex:0 1 120px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;';
          }
          return 'flex:1;min-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;';
        }
        return defaultCell;
      }

      const nodes: any[] = [];
      nodes.push(
        h(
          'div',
          { style: headerRowStyle },
          cols.map((c, idx) =>
            h('span', { style: colStyle(idx, cols.length) }, String(c.title ?? c.field ?? '')),
          ),
        ),
      );

      if (Array.isArray(optionsArr) && optionsArr.length > 0) {
        for (const opt of optionsArr as any[]) {
          const raw = opt?._raw ?? opt?.raw ?? null;
          nodes.push(
            h(
              'div',
              {
                style:
                  'display:flex; gap:12px; align-items:center; justify-content:flex-start; padding:8px 4px; cursor:pointer; border-bottom:1px solid #f5f5f5; font-size:13px;',
                onClick: async () => {
                  const v = opt?.value;
                  if (v !== undefined) await formApi.setValues({ [fieldName]: v });
                  await nextCp.onSelect?.(v, opt);
                },
              },
              cols.map((c, idx) => {
                const val = getRawFieldValue(raw, c.field);
                return h('span', { style: colStyle(idx, cols.length) }, formatCellValue(val));
              }),
            ),
          );
        }
      } else {
        nodes.push(h('div', { style: 'color:#999; padding: 8px 0; font-size:12px;' }, '暂无数据'));
      }

      return h(
        'div',
        {
          style:
            'padding: 6px 8px; min-width: 520px; width: max-content; max-width: min(92vw, 720px); max-height: 320px; overflow:auto; background:#fff; border:1px solid #f0f0f0; border-radius:6px; box-shadow:0 4px 14px rgba(0,0,0,0.06);',
        },
        nodes,
      );
    };

    return {
      ...item,
      componentProps: nextCp,
    };
  });
}

/** 对运行时加载/接口返回的表单项做统一兜底：没配置宽度时补 `100%` */
function applyDefaultControlWidth(schema: VbenFormSchema[]): VbenFormSchema[] {
  return (schema ?? []).map((item: any) => {
    const cp = item?.componentProps ?? {};
    const style = typeof cp?.style === 'object' && cp?.style ? cp.style : {};

    // hidden 控件不强制宽度（避免影响隐藏字段逻辑/布局）
    const isHidden = cp?.type === 'hidden' || item?.component === 'Input' || item?.component === 'input';
    if (cp?.type === 'hidden') return item;

    if (style?.width) return item;
    return {
      ...item,
      componentProps: {
        ...cp,
        style: {
          ...style,
          width: '100%',
        },
      },
    };
  });
}

function parseMultiLineMap(text: string): Record<string, string> {
  const map: Record<string, string> = {};
  text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .forEach((line) => {
      // 允许 "a,b" / "a=>b" / "a:b"
      const commaIdx = line.indexOf(',');
      const arrowIdx = line.indexOf('=>');
      const colonIdx = line.indexOf(':');
      let from = '';
      let to = '';
      if (commaIdx >= 0) {
        from = line.slice(0, commaIdx).trim();
        to = line.slice(commaIdx + 1).trim();
      } else if (arrowIdx >= 0) {
        from = line.slice(0, arrowIdx).trim();
        to = line.slice(arrowIdx + 2).trim();
      } else if (colonIdx >= 0) {
        from = line.slice(0, colonIdx).trim();
        to = line.slice(colonIdx + 1).trim();
      } else {
        from = line;
        to = line;
      }
      if (from && to) map[from] = to;
    });
  return map;
}

function parseDisplayColumnsText(text: unknown): Array<{ field: string; title: string }> {
  const t = text === null || text === undefined ? '' : String(text);
  if (!t.trim()) return [];
  const lines = t
    .split('\n')
    .map((l) => String(l ?? '').trim())
    .filter(Boolean);
  const cols: Array<{ field: string; title: string }> = [];
  for (const line of lines) {
    // 支持 "field,title" / "field=>title" / "field:title"
    const commaIdx = line.indexOf(',');
    const arrowIdx = line.indexOf('=>');
    const colonIdx = line.indexOf(':');
    if (commaIdx >= 0) {
      const field = line.slice(0, commaIdx).trim();
      const title = line.slice(commaIdx + 1).trim();
      if (field) cols.push({ field, title: title || field });
      continue;
    }
    if (arrowIdx >= 0) {
      const field = line.slice(0, arrowIdx).trim();
      const title = line.slice(arrowIdx + 2).trim();
      if (field) cols.push({ field, title: title || field });
      continue;
    }
    if (colonIdx >= 0) {
      const field = line.slice(0, colonIdx).trim();
      const title = line.slice(colonIdx + 1).trim();
      if (field) cols.push({ field, title: title || field });
      continue;
    }
    cols.push({ field: line, title: line });
  }
  return cols;
}

function normalizeKeyForValue(key: string): string {
  return String(key ?? '').toLowerCase().trim().replace(/\s+/g, '');
}

function getRawFieldValue(raw: any, key: string): any {
  if (!raw || !key) return '';
  const target = normalizeKeyForValue(key);
  for (const k of Object.keys(raw)) {
    if (normalizeKeyForValue(k) === target) return raw[k];
  }

  // 兼容：有些视图可能用中文别名
  if (target === 'name') {
    for (const k of Object.keys(raw)) {
      const nk = normalizeKeyForValue(k);
      if (nk === normalizeKeyForValue('姓名') || nk === normalizeKeyForValue('name')) return raw[k];
    }
  }
  if (target === 'code') {
    for (const k of Object.keys(raw)) {
      const nk = normalizeKeyForValue(k);
      if (nk === normalizeKeyForValue('代码') || nk === normalizeKeyForValue('工号') || nk === normalizeKeyForValue('code')) return raw[k];
    }
  }

  return '';
}

function formatCellValue(v: any): string {
  if (v === null || v === undefined) return '';
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  const s = String(v).trim();
  if (!s) return '';
  if (s.includes('T')) return s.split('T')[0] ?? '';
  if (s.length >= 10 && /^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);
  return s;
}

async function refreshFormValuesSnapshot() {
  try {
    formValuesAfterOpen.value = (await formApi.getValues()) ?? {};
  } catch {
    formValuesAfterOpen.value = {};
  }
  await nextTick();
  if (isFormTabsTable.value && (tabsPreviewRef.value as any)?.flushPendingGridEdits) {
    await (tabsPreviewRef.value as any).flushPendingGridEdits();
  }
  refreshTabTablesDebugSnapshot();
}

const fillDebugReport = computed(() =>
  buildFillDiagnostics(props.initialValues, props.formSchema ?? []),
);

watch(
  () => props.formSchema,
  async (schema) => {
    const raw = schema ? [...schema] : [];
    const resolved = await resolveDictionaryInSchema(raw);
    const finalSchema = attachAutoCompleteRemoteQuery(resolved);
    const schemaWithDefaultWidth = applyDefaultControlWidth(finalSchema);
    formApi.setState({ schema: schemaWithDefaultWidth });
    await nextTick();
    const vals = props.initialValues;
    if (vals && Object.keys(vals).length) {
      const mapped = mapRowToSchemaFields(vals, schemaWithDefaultWidth);
      if (Object.keys(mapped).length) {
        await formApi.setValues(mapped);
      }
    }
    await nextTick();
    await syncTabTablesFromDetailApi();
    if (props.onOpenScript?.trim()) {
      await runOnOpenScript();
    }
    await refreshFormValuesSnapshot();
  },
  { immediate: true, deep: true }
);

watch(
  () => props.initialValues,
  async (vals) => {
    if (!vals || !Object.keys(vals).length) {
      if (isFormTabsTable.value) {
        await nextTick();
        (tabsPreviewRef.value as any)?.clearAllTabRows?.();
      }
      return;
    }
    const schema = (formApi.getState()?.schema ?? []) as VbenFormSchema[];
    const mapped = mapRowToSchemaFields(vals, schema);
    if (Object.keys(mapped).length) {
      await formApi.setValues(mapped);
    }
    await nextTick();
    await syncTabTablesFromDetailApi();
    await refreshFormValuesSnapshot();
  },
  { immediate: false, deep: true }
);

async function handleSubmit() {
  try {
    await formApi.validate();
    let values = toRaw((await formApi.getValues()) ?? {}) as Record<string, any>;
    const formRuleError = validateFormBySchema(values, props.formSchema ?? []);
    if (formRuleError) {
      message.warning(formRuleError);
      return;
    }

    // 明细：先把 Vxe 正在编辑的单元格写回行，再校验与组装（否则保存的是旧数据）
    if (isFormTabsTable.value && (tabsPreviewRef.value as any)?.flushPendingGridEdits) {
      await (tabsPreviewRef.value as any).flushPendingGridEdits();
    }

    // 明细表闭环校验：保存前先校验所有页签行（required）
    if (isFormTabsTable.value && tabsPreviewRef.value && (tabsPreviewRef.value as any).validateAllTabs) {
      const tabValidation = (tabsPreviewRef.value as any).validateAllTabs();
      if (!tabValidation?.valid) {
        if (tabValidation?.tabKey && (tabsPreviewRef.value as any).setActiveTab) {
          await (tabsPreviewRef.value as any).setActiveTab(tabValidation.tabKey);
        }
        message.warning(tabValidation?.message || '明细表校验不通过');
        return;
      }
    }

    const tabTables =
      isFormTabsTable.value && tabsPreviewRef.value?.getTabDataMap
        ? tabsPreviewRef.value.getTabDataMap()
        : {};
    const tabDeleteRowsMap =
      isFormTabsTable.value && (tabsPreviewRef.value as any)?.getTabDeleteRowsMap
        ? (tabsPreviewRef.value as any).getTabDeleteRowsMap()
        : {};
    const tabConfigs =
      (props.tabs ?? []).map((t) => ({
        key: t.key,
        tab: t.tab,
        tableName: (t as any).tableName,
        primaryKey: (t as any).primaryKey ?? 'id',
        foreignKeyField: (t as any).foreignKeyField,
        mainKeyField: (t as any).mainKeyField,
      }));
    const scriptResult = await runBeforeSubmitScript(values, tabTables, tabConfigs);
    if (!scriptResult.valid) {
      message.error(scriptResult.message);
      return;
    }
    if (scriptResult.formValues) values = scriptResult.formValues;
    const BLOCKLIST = new Set(['valid', 'results', 'errors', 'values', 'source']);
    const excludeFields = new Set(
      (props.formSchema || [])
        .filter((s: any) => s.excludeFromSubmit)
        .map((s) => s.fieldName),
    );
    const cleanValues: Record<string, any> = {};
    for (const [k, v] of Object.entries(values)) {
      if (!BLOCKLIST.has(k) && !excludeFields.has(k)) {
        cleanValues[k] = v === undefined ? null : v;
      }
    }
    // 新增时若缺少主键，自动生成 GUID
    const pk = props.primaryKey || 'id';
    if (!cleanValues[pk] || String(cleanValues[pk]).trim() === '') {
      cleanValues[pk] = crypto.randomUUID();
    }
    if (!props.saveEntityName?.trim()) {
      message.warning('未配置保存实体 (saveEntityName)，请联系管理员在列表配置中设置');
      return;
    }
    if (Object.keys(cleanValues).filter((k) => k !== pk).length === 0) {
      message.warning('表单数据为空，请填写表单项后再保存');
      return;
    }
    // 调试输出（上线前可移除）
    console.debug('[FormFromDesigner] 保存参数:', {
      saveEntityName: props.saveEntityName,
      primaryKey: pk,
      data: cleanValues,
      tabTables: isFormTabsTable.value ? tabTables : undefined,
      tabDeleteRowsMap: isFormTabsTable.value ? tabDeleteRowsMap : undefined,
    });

    const tables: Array<{
      tableName: string;
      primaryKey: string;
      data: Record<string, any>[];
      deleteRows: Record<string, any>[];
    }> = [
      {
        tableName: props.saveEntityName,
        primaryKey: pk,
        data: [cleanValues],
        deleteRows: [],
      },
    ];

    // 明细表：按 tabs 配置（tableName + primaryKey）组装多表保存
    for (const t of tabConfigs) {
      const tableName = String(t.tableName ?? '').trim();
      if (!tableName) continue;
      const tabPk = String((t as any).primaryKey ?? 'id').trim() || 'id';
      const rowsRaw = (tabTables?.[t.key] ?? []) as Record<string, any>[];
      const deleteRowsRaw = (tabDeleteRowsMap?.[t.key] ?? []) as Record<string, any>[];

      const rows = rowsRaw.map((r) => {
        const out: Record<string, any> = {};
        for (const [k, v] of Object.entries(r ?? {})) {
          if (BLOCKLIST.has(k) || k.startsWith('_X')) continue;
          out[k] = v === undefined ? null : v;
        }
        // 只使用 tab 配置的主键；主键为空/0 时自动补 UUID
        if (tabPk !== 'id' && Object.prototype.hasOwnProperty.call(out, 'id')) {
          delete out.id;
        }
        out[tabPk] = normalizeDetailPrimaryKey(out[tabPk]);
        return out;
      });

      const fkField = String((t as any).foreignKeyField ?? '').trim();
      const mainKeyForFk = String((t as any).mainKeyField ?? '').trim() || pk;
      const mainFkVal = cleanValues[mainKeyForFk];
      if (
        fkField &&
        mainFkVal != null &&
        String(mainFkVal).trim() !== ''
      ) {
        for (const row of rows) {
          row[fkField] = mainFkVal;
        }
      }

      tables.push({
        tableName,
        primaryKey: tabPk,
        data: rows,
        deleteRows: deleteRowsRaw,
      });
    }

    submitPayloadDebug.value = { tables };

    submitting.value = true;
    await requestClient.post<any>(backendApi('DataSave/datasave-multi'), {
      tables,
    });
    message.success(
      props.showFillDebug
        ? '保存成功。弹窗不自动关闭，可复制调试区内容；点「关闭」或标题栏 × 结束。'
        : '保存成功',
    );
    emit('success');
  } catch (e: any) {
    if (e?.errorFields) return; // 校验失败
    message.error(e?.message || e?.data?.message || '保存失败');
  } finally {
    submitting.value = false;
  }
}

function handleCancel() {
  emit('cancel');
}
</script>

<template>
  <div
    class="form-from-designer-modal rounded-xl border border-neutral-200/90 bg-gradient-to-b from-white to-neutral-50/80 p-5 shadow-sm dark:border-neutral-700 dark:from-neutral-900 dark:to-neutral-950/80"
  >
    <Form
      :wrapper-class="wrapperClass"
      :form-item-gap-px="layoutFormItemGapPx"
    />
    <FormTabsTablePreview
      v-if="isFormTabsTable"
      ref="tabsPreviewRef"
      :show-form="false"
      :form-schema="[]"
      :tabs="tabs"
      :wrapper-class="wrapperClass"
      :layout="layout?.layout"
      :label-width="layout?.labelWidth"
      class="mt-4"
    />
    <details
      v-if="showFillDebug"
      class="fill-debug-panel mt-4 rounded border border-amber-200/90 bg-amber-50/50 dark:border-amber-900/45 dark:bg-amber-950/25"
    >
      <summary
        class="cursor-pointer select-none px-3 py-2 text-sm font-medium text-amber-950 dark:text-amber-100"
      >
        数据回填调试（列表行 → 主表；明细见下方）
      </summary>
      <div
        class="space-y-3 border-t border-amber-200/80 p-3 text-xs dark:border-amber-900/40"
      >
        <p class="text-neutral-600 dark:text-neutral-400">
          主表区：对照「列表原始行」与主表单项 fieldName。「未匹配」表示行里没有同名字段；「列表多出字段」多为列名与 fieldName 不一致。列表行一般
          <span class="font-medium">不含明细</span>
          ，明细在下方快照中展示（自动按外键加载或手工增删后点刷新）。
        </p>
        <div class="flex flex-wrap gap-2">
          <Button size="small" @click="refreshFormValuesSnapshot">
            刷新主表值与明细快照
          </Button>
          <Button
            size="small"
            @click="copyText('列表原始行', prettyJson(initialValues))"
          >
            复制列表原始行 JSON
          </Button>
          <Button
            size="small"
            @click="copyText('映射后对象', prettyJson(fillDebugReport.mapped))"
          >
            复制映射后 JSON
          </Button>
          <Button
            size="small"
            @click="copyText('当前表单值', prettyJson(formValuesAfterOpen))"
          >
            复制当前表单 JSON
          </Button>
          <Button
            v-if="fillDebugTabSnapshot"
            size="small"
            @click="copyText('明细页签行数据', prettyJson(fillDebugTabSnapshot.tabTables))"
          >
            复制明细行 JSON
          </Button>
          <Button
            size="small"
            @click="copyText('提交 payload', prettyJson(submitPayloadDebug))"
          >
            复制提交 payload JSON
          </Button>
        </div>
        <div
          class="max-h-48 overflow-auto rounded border border-neutral-200 bg-white dark:border-neutral-700 dark:bg-neutral-900"
        >
          <table class="w-full border-collapse text-left">
            <thead
              class="sticky top-0 bg-neutral-100 text-neutral-700 dark:bg-neutral-800 dark:text-neutral-200"
            >
              <tr>
                <th
                  class="border-b border-neutral-200 px-2 py-1 font-medium dark:border-neutral-600"
                >
                  fieldName
                </th>
                <th
                  class="border-b border-neutral-200 px-2 py-1 font-medium dark:border-neutral-600"
                >
                  标签
                </th>
                <th
                  class="border-b border-neutral-200 px-2 py-1 font-medium dark:border-neutral-600"
                >
                  匹配
                </th>
                <th
                  class="border-b border-neutral-200 px-2 py-1 font-medium dark:border-neutral-600"
                >
                  列表行键
                </th>
                <th
                  class="border-b border-neutral-200 px-2 py-1 font-medium dark:border-neutral-600"
                >
                  取值预览
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in fillDebugReport.tableRows"
                :key="row.key"
                class="border-b border-neutral-100 dark:border-neutral-800"
              >
                <td class="px-2 py-1 font-mono text-[11px]">
                  {{ row.fieldName }}
                </td>
                <td class="px-2 py-1">{{ row.label }}</td>
                <td class="px-2 py-1">
                  <Tag v-if="row.matchType === 'exact'" color="success" class="!m-0">
                    一致
                  </Tag>
                  <Tag
                    v-else-if="row.matchType === 'case_insensitive'"
                    color="processing"
                    class="!m-0"
                  >
                    大小写
                  </Tag>
                  <Tag v-else color="error" class="!m-0">未匹配</Tag>
                </td>
                <td class="px-2 py-1 font-mono text-[11px]">
                  {{ row.sourceKey }}
                </td>
                <td
                  class="break-all px-2 py-1 text-neutral-700 dark:text-neutral-300"
                >
                  {{ row.valuePreview }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div
          v-if="fillDebugReport.unusedKeys.length"
          class="rounded bg-orange-100/80 px-2 py-2 text-orange-950 dark:bg-orange-950/40 dark:text-orange-100"
        >
          <strong>列表里有、但未映射到任何表单项的字段：</strong>
          <span class="font-mono">{{ fillDebugReport.unusedKeys.join(', ') }}</span>
        </div>

        <div
          v-if="fillDebugTabSnapshot"
          class="rounded border border-amber-300/60 bg-amber-100/40 p-2 dark:border-amber-800/50 dark:bg-amber-950/30"
        >
          <div class="mb-2 font-medium text-amber-950 dark:text-amber-100">
            明细页签快照（按页签 key → 当前表格行；非列表原始行）
          </div>
          <div class="mb-2 max-h-32 overflow-auto rounded border border-amber-200/80 bg-white dark:border-amber-900/40 dark:bg-neutral-900">
            <table class="w-full border-collapse text-left">
              <thead class="sticky top-0 bg-amber-100/90 text-amber-950 dark:bg-amber-950/80 dark:text-amber-50">
                <tr>
                  <th class="border-b px-2 py-1 font-medium">页签 key</th>
                  <th class="border-b px-2 py-1 font-medium">名称</th>
                  <th class="border-b px-2 py-1 font-medium">tableName</th>
                  <th class="border-b px-2 py-1 font-medium">primaryKey</th>
                  <th class="border-b px-2 py-1 font-medium">foreignKeyField</th>
                  <th class="border-b px-2 py-1 font-medium">行数</th>
                  <th class="border-b px-2 py-1 font-medium">待删</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="s in fillDebugTabSnapshot.summary"
                  :key="s.key"
                  class="border-b border-amber-100 dark:border-amber-900/50"
                >
                  <td class="px-2 py-1 font-mono text-[11px]">{{ s.key }}</td>
                  <td class="px-2 py-1">{{ s.tab }}</td>
                  <td class="px-2 py-1 font-mono text-[11px]">{{ s.tableName || '—' }}</td>
                  <td class="px-2 py-1 font-mono text-[11px]">{{ s.primaryKey || '—' }}</td>
                  <td class="px-2 py-1 font-mono text-[11px]">{{ s.foreignKeyField || '—' }}</td>
                  <td class="px-2 py-1">{{ s.rowCount }}</td>
                  <td class="px-2 py-1">{{ s.deletePendingCount }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="grid gap-2 md:grid-cols-2">
            <div>
              <div class="mb-1 font-medium text-neutral-700 dark:text-neutral-300">
                明细行数据 tabTables
              </div>
              <pre
                class="max-h-40 overflow-auto rounded border border-neutral-200 bg-neutral-50 p-2 font-mono text-[11px] leading-relaxed dark:border-neutral-700 dark:bg-neutral-950"
              >{{ prettyJson(fillDebugTabSnapshot.tabTables) }}</pre>
            </div>
            <div>
              <div class="mb-1 font-medium text-neutral-700 dark:text-neutral-300">
                待删除主键 deleteRows（保存时提交）
              </div>
              <pre
                class="max-h-40 overflow-auto rounded border border-neutral-200 bg-neutral-50 p-2 font-mono text-[11px] leading-relaxed dark:border-neutral-700 dark:bg-neutral-950"
              >{{ prettyJson(fillDebugTabSnapshot.tabDeleteRows) }}</pre>
            </div>
          </div>
        </div>

        <div class="grid gap-2 md:grid-cols-2">
          <div>
            <div class="mb-1 font-medium text-neutral-700 dark:text-neutral-300">
              列表原始行
            </div>
            <pre
              class="max-h-36 overflow-auto rounded border border-neutral-200 bg-neutral-50 p-2 font-mono text-[11px] leading-relaxed dark:border-neutral-700 dark:bg-neutral-950"
            >{{ prettyJson(initialValues) }}</pre>
          </div>
          <div>
            <div class="mb-1 font-medium text-neutral-700 dark:text-neutral-300">
              映射后 → setValues
            </div>
            <pre
              class="max-h-36 overflow-auto rounded border border-neutral-200 bg-neutral-50 p-2 font-mono text-[11px] leading-relaxed dark:border-neutral-700 dark:bg-neutral-950"
            >{{ prettyJson(fillDebugReport.mapped) }}</pre>
          </div>
          <div class="md:col-span-2">
            <div class="mb-1 font-medium text-neutral-700 dark:text-neutral-300">
              当前表单值（含打开时脚本写入；可点「刷新主表值与明细快照」）
            </div>
            <pre
              class="max-h-36 overflow-auto rounded border border-neutral-200 bg-neutral-50 p-2 font-mono text-[11px] leading-relaxed dark:border-neutral-700 dark:bg-neutral-950"
            >{{ prettyJson(formValuesAfterOpen) }}</pre>
          </div>
          <div class="md:col-span-2">
            <div class="mb-1 font-medium text-neutral-700 dark:text-neutral-300">
              保存时提交 payload（点击保存后更新）
            </div>
            <pre
              class="max-h-48 overflow-auto rounded border border-neutral-200 bg-neutral-50 p-2 font-mono text-[11px] leading-relaxed dark:border-neutral-700 dark:bg-neutral-950"
            >{{ prettyJson(submitPayloadDebug) }}</pre>
          </div>
        </div>
      </div>
    </details>
    <div
      class="mt-6 flex justify-end gap-3 border-t border-neutral-200/80 pt-5 dark:border-neutral-700"
    >
      <Button size="middle" class="min-w-[88px]" @click="handleCancel">
        关闭
      </Button>
      <Button
        type="primary"
        size="middle"
        class="min-w-[88px]"
        :loading="submitting"
        @click="handleSubmit"
      >
        保存
      </Button>
    </div>
  </div>
</template>
