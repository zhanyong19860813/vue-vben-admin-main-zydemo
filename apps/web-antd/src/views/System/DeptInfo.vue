<script lang="ts" setup>
import type { VxeGridProps } from '#/adapter/vxe-table';

import { useVbenVxeGrid } from '#/adapter/vxe-table';
import type { DefaultOptionType } from 'ant-design-vue/es/select';
import { Page } from '@vben/common-ui';
import { useUserStore } from '@vben/stores';
import {
  Button,
  Form,
  FormItem,
  Input,
  InputNumber,
  Modal,
  Radio,
  RadioGroup,
  Select,
  Tabs,
  TreeSelect,
  message,
} from 'ant-design-vue';
import { computed, nextTick, onMounted, reactive, ref, watch } from 'vue';
import { useRoute } from 'vue-router';

import { backendApi } from '#/api/constants';
import { baseRequestClient, requestClient } from '#/api/request';
import { useAuthStore } from '#/store';

interface RowType {
  id: string;
  name: string;
  parentId: null | string;
  longName?: string;
  managerName?: string;
  replacemanagerName?: string;
  sjCode?: string;
  status?: string;
  deptType?: number;
  sort?: number;
  description?: string;
  addTime?: string;
  addName?: string;
  modifyTime?: string;
  modifyName?: string;
}

function unwrapDepartmentRow(raw: unknown, depth = 0): Record<string, unknown> | null {
  if (!raw || typeof raw !== 'object') return null;
  const direct = raw as Record<string, unknown>;
  if ('id' in direct || 'Id' in direct || 'ID' in direct) return direct;
  if (depth >= 4) return direct;
  const nested =
    direct.row ??
    direct.record ??
    direct.data ??
    direct._row ??
    direct.source ??
    direct.raw;
  if (nested && typeof nested === 'object') {
    return unwrapDepartmentRow(nested, depth + 1) ?? (nested as Record<string, unknown>);
  }
  return direct;
}

/** 动态查询/表格行可能为 id 或 Id（PascalCase），树表勾选行需兼容 */
function pickDepartmentRowId(row: RowType | Record<string, unknown> | null | undefined): string | null {
  const r = unwrapDepartmentRow(row);
  if (!r) return null;
  const v = r.id ?? r.Id ?? r.ID;
  if (v === undefined || v === null) return null;
  const s = String(v).trim();
  return s.length > 0 ? s : null;
}

function pickDepartmentSjCode(row: RowType | Record<string, unknown> | null | undefined): string | null {
  const r = unwrapDepartmentRow(row);
  if (!r) return null;
  const v = r.sjCode ?? r.SJCode ?? r.sjcode;
  if (v === undefined || v === null) return null;
  const s = String(v).trim();
  return s.length > 0 ? s : null;
}

const DEPT_EDIT_DEBUG = true;
function deptEditDebug(step: string, payload?: unknown) {
  if (!DEPT_EDIT_DEBUG) return;
  try {
    console.groupCollapsed(`[DeptInfo][EditDebug] ${step}`);
    if (payload !== undefined) console.log(payload);
    console.groupEnd();
    (globalThis as any).__deptEditDebug = {
      step,
      payload,
      at: new Date().toISOString(),
    };
  } catch {
    /* ignore */
  }
}

/**
 * vxe 行主键读的是 `row['id']`（见 getFastRowIdByKey）；若接口只返回 `Id`，树与勾选行会缺 id。
 * 加载列表时统一写入小写 id / parentId，避免「当前行缺少部门 id」。
 */
function normalizeDepartmentGridRow(raw: unknown): RowType {
  if (!raw || typeof raw !== 'object') return raw as RowType;
  const o = raw as Record<string, unknown>;
  const idVal = o.id ?? o.Id ?? o.ID;
  const parentVal = o.parentId ?? o.ParentId ?? o.parent_id ?? o.Parent_Id;
  const next: Record<string, unknown> = { ...o };
  if (idVal !== undefined && idVal !== null && String(idVal).trim() !== '') {
    next.id = String(idVal).trim();
  }
  if (parentVal === undefined || parentVal === null || String(parentVal).trim() === '') {
    next.parentId = null;
  } else {
    next.parentId = String(parentVal).trim();
  }
  return next as RowType;
}

const ACTION = {
  add: 'add',
  expandAll: 'expandAll',
  collapseAll: 'collapseAll',
  refresh: 'refresh',
  edit: 'edit',
  enable: 'enable',
  disable: 'disable',
  /** 同步到钉钉（字典 DingTalk_DeptSync：enabled、corp_id=Client ID、corp_secret=Client Secret） */
  syncDingTalk: 'syncDingTalk',
  /** 按本地部门名称在钉钉侧查找并回写 dingtalk_id */
  matchDingTalkByName: 'matchDingTalkByName',
} as const;

const route = useRoute();
const userStore = useUserStore();
const authStore = useAuthStore();
const menuId = computed(() => {
  const q = route.meta?.query as Record<string, string> | undefined;
  const v = (q?.menuid ?? '').trim();
  return v || null;
});

const allowedActionKeys = ref<null | Set<string>>(null);
function showToolbarAction(actionKey: string): boolean {
  const set = allowedActionKeys.value;
  if (set === null) return true;
  return set.has(actionKey);
}

async function queryForVben(payload: Record<string, unknown>) {
  return requestClient.post(backendApi('DynamicQueryBeta/queryforvben'), payload as any);
}

async function loadToolbarPermissions() {
  const mid = menuId.value;
  if (!mid) {
    allowedActionKeys.value = null;
    return;
  }
  let userId = (userStore.userInfo as any)?.userId ?? (userStore.userInfo as any)?.id;
  if (!userId) {
    try {
      await authStore.fetchUserInfo();
    } catch {
      /* ignore */
    }
    const u = userStore.userInfo as any;
    userId = u?.userId ?? u?.id;
  }
  if (!userId) {
    allowedActionKeys.value = null;
    return;
  }
  try {
    const res = await queryForVben({
      TableName: 'vben_v_user_role_menu_actions',
      Page: 1,
      PageSize: 500,
      Where: {
        Logic: 'AND',
        Conditions: [
          { Field: 'userid', Operator: 'eq', Value: String(userId) },
          { Field: 'menu_id', Operator: 'eq', Value: String(mid) },
        ],
        Groups: [],
      },
    });
    const raw = res?.items ?? [];
    const keys = new Set<string>();
    for (const r of raw) {
      const k = r.action_key ?? r.actionKey;
      if (k) keys.add(String(k));
    }
    allowedActionKeys.value = keys.size > 0 ? keys : null;
  } catch {
    allowedActionKeys.value = null;
  }
}

const gridOptions: VxeGridProps<RowType> = {
  height: 480,
  columns: [
    { type: 'checkbox', width: 48, fixed: 'left' },
    { type: 'seq', width: 56, title: '#' },
    { field: 'name', minWidth: 220, title: '部门名称', treeNode: true, showOverflow: true },
    { field: 'longName', minWidth: 220, title: '全称', showOverflow: true },
    {
      field: 'managerName',
      minWidth: 120,
      title: '主管姓名',
      showOverflow: true,
      formatter: ({ row }: { row: RowType }) =>
        String(row.managerName ?? '').trim() || String(row.replacemanagerName ?? '').trim(),
    },
    { field: 'replacemanagerName', minWidth: 120, title: '代管理人', showOverflow: true },
    { field: 'sjCode', width: 110, title: '时捷编号', showOverflow: true },
    { field: 'status', width: 84, title: '状态', showOverflow: true },
    { field: 'deptType', width: 96, title: '部门类型', showOverflow: true },
    { field: 'sort', width: 96, title: '显示顺序', sortable: true },
    { field: 'description', minWidth: 160, title: '说明', showOverflow: true },
    { field: 'addTime', width: 164, title: '创建时间', sortable: true },
    { field: 'addName', width: 100, title: '创建人', showOverflow: true },
    { field: 'modifyTime', width: 164, title: '修改时间', sortable: true },
    { field: 'modifyName', width: 100, title: '修改人', showOverflow: true },
  ],
  pagerConfig: { enabled: false },
  /** 与 treeConfig.rowField 一致，避免树表行主键未对齐导致勾选行缺少 id */
  rowConfig: { keyField: 'id' },
  /** 树形勾选：父子互不联动，避免只选父部门时整棵子树被勾选 */
  checkboxConfig: { checkStrictly: true },
  treeConfig: { parentField: 'parentId', rowField: 'id', transform: true },
  proxyConfig: {
    ajax: {
      query: async ({ page, sort }) => {
        const res = await queryForVben({
          TableName: 'v_t_base_department',
          Page: page?.currentPage ?? 1,
          PageSize: 2000,
          SortBy: sort?.field || 'path',
          SortOrder: (sort?.order || 'asc').toString().toLowerCase(),
          QueryField:
            'id,parent_id as parentId,name,long_name as longName,managerName,replacemanagerName,SJCode as sjCode,status,dept_type as deptType,sort,description,add_time as addTime,add_name as addName,Modify_Time as modifyTime,Modify_Name as modifyName',
          Where: { Logic: 'AND', Conditions: [], Groups: [] },
        });
        setTimeout(() => {
          try {
            gridApi.grid?.setAllTreeExpand(true);
          } catch {
            /* ignore */
          }
        }, 0);
        const items = (res.items ?? []).map((r: unknown) => normalizeDepartmentGridRow(r));
        return { items, total: res.total };
      },
    },
  },
};

async function beginEditByRow(row?: RowType | null) {
  if (!pickDepartmentRowId(row ?? null)) return;
  try {
    gridApi.grid?.setCurrentRow?.(row);
    gridApi.grid?.setCheckboxRow?.(row, true);
  } catch {
    /* ignore */
  }
  await onEdit(row);
}

const gridEvents = {
  cellDblclick: ({ row }: { row: RowType }) => {
    void beginEditByRow(row);
  },
  rowDblclick: ({ row }: { row: RowType }) => {
    void beginEditByRow(row);
  },
};

const [Grid, gridApi] = useVbenVxeGrid({ gridEvents, gridOptions });
const gridWrapRef = ref<HTMLElement | null>(null);

function applyGridHeight() {
  const el = gridWrapRef.value;
  if (!el) return;
  const rect = el.getBoundingClientRect();
  const px = Math.max(360, Math.floor(rect.height));
  gridApi.setGridOptions({ height: px });
  nextTick(() => {
    try {
      gridApi.grid?.recalculate?.();
      gridApi.grid?.setAllTreeExpand?.(true);
    } catch {
      /* ignore */
    }
  });
}
function scheduleGridHeight() {
  requestAnimationFrame(() => applyGridHeight());
}

const mode = ref<'add' | 'edit'>('edit');
const editOpen = ref(false);
const saving = ref(false);
const parentTree = ref<DefaultOptionType[]>([]);

const editForm = reactive({
  id: '',
  name: '',
  long_name: '',
  parent_id: undefined as string | undefined,
  SJCode: '',
  SJPCode: '',
  manager: '',
  replacemanager: '',
  isbussiness_dept: 0,
  status: '0',
  dept_type: 0,
  is_virtual_department: 0,
  isapprove: 0,
  description: '',
  email: '',
  url: '',
  office_address: '',
  phone: '',
  post_code: '',
  fax: '',
  path: '',
  sort: 0,
});

function resetEditForm() {
  Object.assign(editForm, {
    id: '',
    name: '',
    long_name: '',
    parent_id: undefined,
    SJCode: '',
    SJPCode: '',
    manager: '',
    replacemanager: '',
    isbussiness_dept: 0,
    status: '0',
    dept_type: 0,
    is_virtual_department: 0,
    isapprove: 0,
    description: '',
    email: '',
    url: '',
    office_address: '',
    phone: '',
    post_code: '',
    fax: '',
    path: '',
    sort: 0,
  });
}

function newGuid() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function listToTree(rows: any[]) {
  const map = new Map<string, any>();
  const roots: any[] = [];
  for (const x of rows) {
    map.set(String(x.id), { title: String(x.name ?? ''), value: String(x.id), key: String(x.id), children: [] });
  }
  for (const x of rows) {
    const node = map.get(String(x.id));
    const pid = x.parent_id ? String(x.parent_id) : '';
    if (pid && map.has(pid)) map.get(pid).children.push(node);
    else roots.push(node);
  }
  return roots;
}

async function loadParentTree() {
  const res = await queryForVben({
    TableName: 'v_t_base_department',
    Page: 1,
    PageSize: 5000,
    SortBy: 'path',
    SortOrder: 'asc',
    QueryField: 'id,parent_id,name',
    Where: { Logic: 'AND', Conditions: [], Groups: [] },
  });
  parentTree.value = listToTree(res.items ?? []);
}

async function onParentChanged(parentId?: string) {
  if (mode.value !== 'add' || !parentId) return;
  const p = await queryForVben({
    TableName: 't_base_department',
    Page: 1,
    PageSize: 1,
    QueryField: 'id,path,SJCode',
    Where: { Logic: 'AND', Conditions: [{ Field: 'id', Operator: 'eq', Value: String(parentId) }], Groups: [] },
  });
  const parent = (p.items ?? [])[0];
  if (!parent) return;
  const c = await queryForVben({
    TableName: 't_base_department',
    Page: 1,
    PageSize: 5000,
    QueryField: 'sort',
    Where: { Logic: 'AND', Conditions: [{ Field: 'parent_id', Operator: 'eq', Value: String(parentId) }], Groups: [] },
  });
  const rows = c.items ?? [];
  const nextSort = rows.reduce((m: number, r: any) => Math.max(m, Number(r.sort ?? 0) || 0), 0) + 1;
  const pPath = String(parent.path ?? '').trim();
  const pCode = String(parent.SJCode ?? '').trim();
  editForm.sort = nextSort;
  editForm.path = `${pPath}-${String(nextSort).padStart(3, '0')}`;
  editForm.SJPCode = pCode;
  editForm.SJCode = `${pCode}${String(nextSort).padStart(2, '0')}`;
}

function getSingleSelected(): RowType | null {
  const grid = gridApi.grid;
  /** tree + transform 时非 full 勾选记录可能不是完整行，缺 id；传 true 取 fullData 行 */
  const rows = ((grid?.getCheckboxRecords?.(true) ?? []) as unknown[])
    .map((r) => normalizeDepartmentGridRow(unwrapDepartmentRow(r)))
    .filter(Boolean) as RowType[];
  const curr =
    (grid?.getCurrentRecord?.() as unknown) ??
    (grid?.getCurrentRow?.() as unknown) ??
    null;
  const currRow = normalizeDepartmentGridRow(unwrapDepartmentRow(curr)) as RowType;
  const currId = pickDepartmentRowId(currRow);
  let row: RowType | null = null;
  if (rows.length === 1) {
    row = rows[0];
  } else if (rows.length > 1 && currId) {
    row = rows.find((x) => pickDepartmentRowId(x) === currId) ?? null;
  } else if (currId) {
    row = currRow;
  }
  if (!row) return null;
  if (!pickDepartmentRowId(row) && grid?.getRowid) {
    const encoded = grid.getRowid(row);
    if (encoded) {
      try {
        const decoded = decodeURIComponent(encoded);
        if (decoded) row = { ...row, id: decoded } as RowType;
      } catch {
        /* ignore */
      }
    }
  }
  if (!pickDepartmentRowId(row) && currId) {
    deptEditDebug('getSingleSelected:fallback-current-row', {
      rowsLength: rows.length,
      currId,
      selectedPreview: row,
      currentPreview: currRow,
    });
    return currRow;
  }
  deptEditDebug('getSingleSelected:resolved', {
    rowsLength: rows.length,
    rowId: pickDepartmentRowId(row),
    rowSjCode: pickDepartmentSjCode(row),
    rowPreview: row,
  });
  return row;
}

async function resolveDepartmentId(row: unknown): Promise<string | null> {
  if (row instanceof Event) {
    deptEditDebug('resolveDepartmentId:received-event', {
      eventType: row.type,
    });
    return null;
  }
  const directId = pickDepartmentRowId(row);
  if (directId) {
    deptEditDebug('resolveDepartmentId:direct-id', {
      directId,
      rowSjCode: pickDepartmentSjCode(row),
      rowPreview: row,
    });
    return directId;
  }
  const sjCode = pickDepartmentSjCode(row);
  if (!sjCode) {
    deptEditDebug('resolveDepartmentId:no-id-no-sjcode', {
      rowPreview: row,
      unwrappedRow: unwrapDepartmentRow(row),
    });
    return null;
  }
  try {
    const res = await queryForVben({
      TableName: 't_base_department',
      Page: 1,
      PageSize: 2,
      QueryField: 'id',
      Where: {
        Logic: 'AND',
        Conditions: [{ Field: 'SJCode', Operator: 'eq', Value: sjCode }],
        Groups: [],
      },
    });
    const items = (res?.items ?? []) as Record<string, unknown>[];
    const one = items[0];
    const resolved = pickDepartmentRowId(one ?? null);
    deptEditDebug('resolveDepartmentId:query-by-sjcode', {
      sjCode,
      resultCount: items.length,
      firstRow: one ?? null,
      resolvedId: resolved,
    });
    return resolved;
  } catch (e: unknown) {
    deptEditDebug('resolveDepartmentId:query-error', {
      sjCode,
      error: e instanceof Error ? e.message : e,
    });
    return null;
  }
}

async function onAdd() {
  mode.value = 'add';
  resetEditForm();
  editForm.id = newGuid();
  await loadParentTree();
  editOpen.value = true;
}

async function onEdit(rowArg?: unknown) {
  const row = rowArg instanceof Event ? null : (rowArg ?? null);
  const picked = (row as any) ?? getSingleSelected();
  const usingRow = picked;
  if (!usingRow) return message.warning('请勾选一条部门记录');
  deptEditDebug('onEdit:input-row', {
    fromArg: Boolean(rowArg) && !(rowArg instanceof Event),
    fromEvent: rowArg instanceof Event,
    rowPreview: usingRow,
    rowId: pickDepartmentRowId(usingRow),
    rowSjCode: pickDepartmentSjCode(usingRow),
  });
  const rowId = await resolveDepartmentId(usingRow);
  if (!rowId) {
    const debugCode = `DEPT-${Date.now().toString(36).slice(-6).toUpperCase()}`;
    deptEditDebug('onEdit:missing-id', {
      debugCode,
      rowPreview: usingRow,
      unwrappedRow: unwrapDepartmentRow(usingRow),
      rowId: pickDepartmentRowId(usingRow),
      rowSjCode: pickDepartmentSjCode(usingRow),
    });
    return message.error(`无法编辑：当前行缺少部门 id，请刷新列表后重试。 [${debugCode}]`);
  }
  mode.value = 'edit';
  resetEditForm();
  await loadParentTree();
  const res = await queryForVben({
    TableName: 't_base_department',
    Page: 1,
    PageSize: 1,
    QueryField:
      'id,name,long_name,parent_id,SJCode,SJPCode,manager,replacemanager,isbussiness_dept,status,dept_type,is_virtual_department,isapprove,description,email,url,office_address,phone,post_code,fax,path,sort',
    Where: { Logic: 'AND', Conditions: [{ Field: 'id', Operator: 'eq', Value: rowId }], Groups: [] },
  });
  const d = (res.items ?? [])[0] ?? {};
  Object.assign(editForm, {
    id: String((d as any).id ?? (d as any).Id ?? rowId),
    name: String(d.name ?? ''),
    long_name: String(d.long_name ?? ''),
    parent_id: d.parent_id ? String(d.parent_id) : undefined,
    SJCode: String(d.SJCode ?? ''),
    SJPCode: String(d.SJPCode ?? ''),
    manager: String(d.manager ?? ''),
    replacemanager: String(d.replacemanager ?? ''),
    isbussiness_dept: Number(d.isbussiness_dept ?? 0) === 1 ? 1 : 0,
    status: String(d.status ?? '0') === '1' ? '1' : '0',
    dept_type: Number(d.dept_type ?? 0) || 0,
    is_virtual_department: Number(d.is_virtual_department ?? 0) === 1 ? 1 : 0,
    isapprove: Number(d.isapprove ?? 0) === 1 ? 1 : 0,
    description: String(d.description ?? ''),
    email: String(d.email ?? ''),
    url: String(d.url ?? ''),
    office_address: String(d.office_address ?? ''),
    phone: String(d.phone ?? ''),
    post_code: String(d.post_code ?? ''),
    fax: String(d.fax ?? ''),
    path: String(d.path ?? ''),
    sort: Number(d.sort ?? 0) || 0,
  });
  editOpen.value = true;
}

async function saveEdit() {
  if (!editForm.name.trim()) return message.warning('请输入部门简称');
  saving.value = true;
  try {
    const payload = {
      tables: [
        {
          tableName: 't_base_department',
          primaryKey: 'id',
          data: [
            {
              ...editForm,
              name: editForm.name.trim(),
              long_name: editForm.long_name.trim() || null,
              is_stop: editForm.status === '1' ? 1 : 0,
            },
          ],
        },
      ],
    };
    deptEditDebug('saveEdit:payload', payload);
    // 绕开 @vben/request 的错误包装：直接用 axios 实例拿到 400 的响应体
    const resp = await baseRequestClient.instance.request({
      url: backendApi('DataSave/datasave-multi'),
      method: 'POST',
      data: payload,
      validateStatus: () => true,
    });
    if (resp.status >= 400) {
      const data = resp.data as any;
      const msg =
        (typeof data === 'string' && data.trim()) ||
        (data && typeof data === 'object' && (data.message || data.error || data.detail || data.title)) ||
        `保存失败（HTTP ${resp.status}）`;
      deptEditDebug('saveEdit:http-error-raw', { status: resp.status, data });
      throw new Error(typeof msg === 'string' ? msg : String(msg));
    }
    message.success('保存成功');
    editOpen.value = false;
    await gridApi.reload();
  } catch (e: unknown) {
    const anyErr = e as any;
    const resp =
      anyErr?.response ??
      anyErr?.cause?.response ??
      anyErr?.error?.response ??
      anyErr?.raw?.response ??
      null;
    const respData =
      resp?.data ??
      anyErr?.responseData ??
      anyErr?.data ??
      anyErr?.cause?.data ??
      null;
    const xhrText: string | null =
      resp?.request?.responseText ??
      resp?.request?.response ??
      anyErr?.response?.request?.responseText ??
      null;
    let parsedXhr: any = null;
    if (!respData && xhrText && typeof xhrText === 'string') {
      const t = xhrText.trim();
      if (t) {
        try {
          parsedXhr = JSON.parse(t);
        } catch {
          parsedXhr = t;
        }
      }
    }
    const serverMsg =
      respData?.message ??
      respData?.error ??
      respData?.detail ??
      respData?.title ??
      parsedXhr?.message ??
      parsedXhr?.error ??
      parsedXhr?.detail ??
      parsedXhr?.title ??
      null;
    const msg =
      (typeof serverMsg === 'string' && serverMsg.trim()) ||
      (typeof respData === 'string' && respData.trim()) ||
      (typeof parsedXhr === 'string' && parsedXhr.trim()) ||
      (e instanceof Error ? e.message : '') ||
      '保存失败';
    deptEditDebug('saveEdit:error', {
      message: msg,
      responseData: respData ?? parsedXhr ?? null,
      status: resp?.status ?? anyErr?.status ?? null,
      rawError: anyErr,
    });
    message.error(msg);
  } finally {
    saving.value = false;
  }
}

async function setStop(isStop: boolean) {
  const row = getSingleSelected();
  if (!row) return message.warning('请勾选一条部门记录');
  const rid = await resolveDepartmentId(row);
  if (!rid) return message.error('当前行缺少部门 id，请刷新列表后重试。');
  await requestClient.post(backendApi('DataSave/datasave-multi'), {
    tables: [{ tableName: 't_base_department', primaryKey: 'id', data: [{ id: rid, is_stop: isStop ? 1 : 0, status: isStop ? '1' : '0' }] }],
  });
  message.success('操作成功');
  await gridApi.reload();
}

type DingTalkDeptSyncCfg = {
  configured?: boolean;
  enabled?: boolean;
  missingKeys?: string[];
};

/** 与「同步到钉钉」「按名对齐钉钉」共用：检查数据字典 DingTalk_DeptSync */
async function assertDingTalkDeptSyncReady(): Promise<boolean> {
  const cfg = (await requestClient.get(
    backendApi('DingTalkDeptSync/config-status'),
  )) as DingTalkDeptSyncCfg;
  if (!cfg?.configured) {
    message.warning(
      '未配置钉钉部门同步字典。请在「数据字典」中维护 DingTalk_DeptSync（enabled；corp_id=应用 Client ID；corp_secret=Client Secret）。若 t_base 有数据但页面不显示，执行 fix_数据字典_DingTalk_镜像到vben界面表.sql。',
    );
    return false;
  }
  if (cfg.missingKeys?.length) {
    message.warning(`数据字典缺少项：${cfg.missingKeys.join('、')}，请补全后再试。`);
    return false;
  }
  if (!cfg.enabled) {
    message.warning('钉钉部门同步未启用：请将字典明细 enabled 设为 1。');
    return false;
  }
  return true;
}

const syncingDingTalk = ref(false);

/** 即时调用钉钉部门 oapi，并回写 dingtalk_id（与老系统定时任务中部门同步逻辑一致） */
async function onSyncToDingTalk() {
  const rows = (gridApi.grid?.getCheckboxRecords?.(true) ?? []) as RowType[];
  if (!rows.length) return message.warning('请至少勾选一条部门记录');
  syncingDingTalk.value = true;
  try {
    if (!(await assertDingTalkDeptSyncReady())) return;
    let ok = 0;
    const failed: string[] = [];
    for (const row of rows) {
      const rid = await resolveDepartmentId(row);
      if (!rid) {
        failed.push(`${String((row as any)?.name ?? '未知部门')}: 缺少部门 id`);
        continue;
      }
      try {
        await requestClient.post(backendApi('DingTalkDeptSync/sync-department'), {
          departmentId: rid,
        });
        ok += 1;
      } catch (e: any) {
        const deptName = String((row as any)?.name ?? rid);
        const err =
          e?.message ||
          e?.response?.data?.message ||
          e?.response?.data?.error ||
          '同步失败';
        failed.push(`${deptName}: ${err}`);
      }
    }
    if (!failed.length) {
      message.success(`已完成部门同步，共 ${ok} 条。`);
    } else if (ok > 0) {
      message.warning(`部分成功：成功 ${ok} 条，失败 ${failed.length} 条。首条失败：${failed[0]}`);
    } else {
      message.error(`同步失败：${failed[0]}`);
    }
    await gridApi.reload();
  } finally {
    syncingDingTalk.value = false;
  }
}

const matchByNameOpen = ref(false);
const matchByNameDeptId = ref<string | null>(null);
const matchByNameMode = ref<'organization' | 'underParent'>('underParent');
const matchingByName = ref(false);

function openMatchByNameModal() {
  const row = getSingleSelected();
  if (!row) return message.warning('请勾选一条部门记录');
  void (async () => {
    const rid = await resolveDepartmentId(row);
    if (!rid) {
      message.error('当前行缺少部门 id，请刷新列表后重试。');
      return;
    }
    matchByNameDeptId.value = rid;
    matchByNameMode.value = 'underParent';
    matchByNameOpen.value = true;
  })();
}

/** 返回 reject 时 Modal 保持打开（与 Ant Design Vue 约定一致） */
async function submitMatchByName(): Promise<void> {
  const id = matchByNameDeptId.value;
  if (!id) {
    matchByNameOpen.value = false;
    return;
  }
  if (!(await assertDingTalkDeptSyncReady())) {
    return Promise.reject(new Error('skip'));
  }
  matchingByName.value = true;
  try {
    await requestClient.post(backendApi('DingTalkDeptSync/match-department-by-name'), {
      departmentId: id,
      mode: matchByNameMode.value === 'organization' ? 'organization' : 'underParent',
    });
    message.success('已按名称对齐并回写钉钉部门 ID。');
    matchByNameOpen.value = false;
    await gridApi.reload();
  } catch {
    /* 全局拦截器已提示 message */
    return Promise.reject(new Error('skip'));
  } finally {
    matchingByName.value = false;
  }
}

function refresh() {
  gridApi.reload();
}
function expandAll() {
  gridApi.grid?.setAllTreeExpand(true);
}
function collapseAll() {
  gridApi.grid?.setAllTreeExpand(false);
}

onMounted(() => {
  loadToolbarPermissions();
  scheduleGridHeight();
});
watch(
  gridWrapRef,
  (el, _p, onCleanup) => {
    if (!el) return;
    scheduleGridHeight();
    const ro = new ResizeObserver(() => scheduleGridHeight());
    ro.observe(el);
    onCleanup(() => ro.disconnect());
  },
  { flush: 'post' },
);
</script>

<template>
  <Page auto-content-height content-class="flex min-h-0 flex-col overflow-hidden">
    <div ref="gridWrapRef" class="dept-grid-wrap">
    <Grid table-title="数据列表" table-title-help="提示">
      <template #toolbar-tools>
        <Button v-if="showToolbarAction(ACTION.add)" class="mr-2" type="primary" @click="onAdd">
          新增
        </Button>
        <Button
          v-if="showToolbarAction(ACTION.expandAll)"
          class="mr-2"
          type="primary"
          @click="expandAll"
        >
          展开全部
        </Button>
        <Button
          v-if="showToolbarAction(ACTION.collapseAll)"
          class="mr-2"
          type="primary"
          @click="collapseAll"
        >
          折叠全部
        </Button>
        <Button
          v-if="showToolbarAction(ACTION.refresh)"
          class="mr-2"
          @click="refresh"
        >
          刷新
        </Button>
        <Button
          v-if="showToolbarAction(ACTION.edit)"
          class="mr-2"
          @click="() => onEdit()"
        >
          修改
        </Button>
        <Button
          v-if="showToolbarAction(ACTION.disable)"
          class="mr-2"
          danger
          @click="setStop(true)"
        >
          停用
        </Button>
        <Button
          v-if="showToolbarAction(ACTION.enable)"
          class="mr-2"
          @click="setStop(false)"
        >
          启用
        </Button>
        <Button
          v-if="showToolbarAction(ACTION.syncDingTalk)"
          class="mr-2"
          :loading="syncingDingTalk"
          @click="onSyncToDingTalk"
        >
          同步到钉钉
        </Button>
        <Button
          v-if="showToolbarAction(ACTION.matchDingTalkByName)"
          class="mr-2"
          :loading="matchingByName"
          @click="openMatchByNameModal"
        >
          按名对齐钉钉
        </Button>
      </template>
    </Grid>
    </div>

    <Modal
      v-model:open="editOpen"
      :title="mode === 'add' ? '新增部门' : '修改部门'"
      :confirm-loading="saving"
      :mask-closable="false"
      destroy-on-close
      @ok="saveEdit"
    >
      <Tabs>
        <Tabs.TabPane key="base" tab="部门基本信息">
          <Form
            class="dept-form-inline"
            layout="horizontal"
            :label-col="{ flex: '0 0 112px' }"
            :wrapper-col="{ flex: '1' }"
            :colon="false"
            label-align="right"
          >
            <FormItem label="部门简称" required><Input v-model:value="editForm.name" /></FormItem>
            <FormItem label="部门全称"><Input v-model:value="editForm.long_name" /></FormItem>
            <FormItem label="上级部门">
              <TreeSelect
                v-model:value="editForm.parent_id"
                :tree-data="parentTree"
                tree-default-expand-all
                show-search
                allow-clear
                @change="(v) => onParentChanged(v as string | undefined)"
              />
            </FormItem>
            <FormItem label="SJCode"><Input v-model:value="editForm.SJCode" /></FormItem>
            <FormItem label="主管"><Input v-model:value="editForm.manager" placeholder="工号，多个用逗号分隔" /></FormItem>
            <FormItem label="代管理人"><Input v-model:value="editForm.replacemanager" placeholder="工号，多个用逗号分隔" /></FormItem>
            <FormItem label="业务部门">
              <RadioGroup v-model:value="editForm.isbussiness_dept">
                <Radio :value="1">是</Radio><Radio :value="0">否</Radio>
              </RadioGroup>
            </FormItem>
            <FormItem label="状态">
              <RadioGroup v-model:value="editForm.status">
                <Radio value="0">运行中</Radio><Radio value="1">停用</Radio>
              </RadioGroup>
            </FormItem>
            <FormItem label="部门类型">
              <Select v-model:value="editForm.dept_type" :options="[{ label: '公司', value: 0 }, { label: '部门', value: 1 }]" />
            </FormItem>
            <FormItem label="虚拟部门">
              <RadioGroup v-model:value="editForm.is_virtual_department">
                <Radio :value="1">是</Radio><Radio :value="0">否</Radio>
              </RadioGroup>
            </FormItem>
            <FormItem label="共同管理">
              <RadioGroup v-model:value="editForm.isapprove">
                <Radio :value="1">是</Radio><Radio :value="0">否</Radio>
              </RadioGroup>
            </FormItem>
            <FormItem label="显示顺序"><InputNumber v-model:value="editForm.sort" class="w-full" :min="0" /></FormItem>
            <FormItem label="说明"><Input.TextArea v-model:value="editForm.description" :rows="4" /></FormItem>
          </Form>
        </Tabs.TabPane>
        <Tabs.TabPane key="contact" tab="联系信息">
          <Form
            class="dept-form-inline"
            layout="horizontal"
            :label-col="{ flex: '0 0 112px' }"
            :wrapper-col="{ flex: '1' }"
            :colon="false"
            label-align="right"
          >
            <FormItem label="部门邮箱"><Input v-model:value="editForm.email" /></FormItem>
            <FormItem label="部门网址"><Input v-model:value="editForm.url" /></FormItem>
            <FormItem label="办公地址"><Input v-model:value="editForm.office_address" /></FormItem>
            <FormItem label="电话"><Input v-model:value="editForm.phone" /></FormItem>
            <FormItem label="邮编"><Input v-model:value="editForm.post_code" /></FormItem>
            <FormItem label="传真号"><Input v-model:value="editForm.fax" /></FormItem>
          </Form>
        </Tabs.TabPane>
      </Tabs>
    </Modal>

    <Modal
      v-model:open="matchByNameOpen"
      title="按名称对齐钉钉"
      :confirm-loading="matchingByName"
      ok-text="开始对齐"
      cancel-text="取消"
      :mask-closable="false"
      destroy-on-close
      @ok="submitMatchByName"
    >
      <p class="mb-3 text-sm text-gray-500">
        在钉钉中按<strong>与本地完全一致的部门名称</strong>查找部门，将找到的钉钉部门 ID 写回本系统。若钉钉侧同名部门多于一个，将失败，需改名或手工填写
        dingtalk_id。
      </p>
      <div class="mb-2 text-sm font-medium">匹配范围</div>
      <RadioGroup v-model:value="matchByNameMode" class="flex flex-col gap-2">
        <Radio value="underParent">
          仅在上级钉钉部门下匹配（默认，需上级已维护正确的 dingtalk_id）
        </Radio>
        <Radio value="organization">全组织按名称匹配（根部门或上级未对齐时用；全企业同名多于一条时会报错）</Radio>
      </RadioGroup>
    </Modal>
  </Page>
</template>

<style scoped>
.dept-grid-wrap {
  display: flex;
  flex: 1 1 0%;
  min-height: 0;
  min-width: 0;
  flex-direction: column;
}
.dept-grid-wrap :deep(> *) {
  display: flex;
  flex: 1 1 0%;
  min-height: 0;
  flex-direction: column;
}

.dept-form-inline :deep(.ant-form-item) {
  margin-bottom: 5px;
}
</style>
