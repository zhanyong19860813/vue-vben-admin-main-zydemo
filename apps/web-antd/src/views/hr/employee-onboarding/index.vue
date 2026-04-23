<script lang="ts" setup>
import type { DataNode } from 'ant-design-vue/es/tree';
import type { VxeGridProps } from '#/adapter/vxe-table';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { Page } from '@vben/common-ui';
import type { VbenFormProps } from '#/adapter/form';
import {
  Button,
  Input,
  Layout,
  message,
  Modal,
  Tree,
} from 'ant-design-vue';
import dayjs from 'dayjs';
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useAccessStore, useUserStore } from '@vben/stores';

import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { useAuthStore } from '#/store';

import EmployeeOnboardingModal from './EmployeeOnboardingModal.vue';
import LegacyHrmIframeModal from './LegacyHrmIframeModal.vue';
import { legacyHrmUrl } from './legacyHrm';
import { HR_EMPLOYEE_ONBOARDING_LEAF_MENU_ID, HR_ONB_ACTION } from './menuMeta';

const { Content, Sider } = Layout;

/** 与 StoneApi Condition / WhereNode 一致 */
interface WhereCondition {
  Field: string;
  Operator: string;
  Value: string;
}

interface WhereNode {
  Logic: string;
  Conditions: WhereCondition[];
  Groups?: WhereNode[];
}

interface DeptRow {
  id: string;
  name: string;
  parent_id: string | null;
  path: string | null;
}

interface EmpRow {
  id: string;
  code?: string;
  name?: string;
  EMP_ID?: string;
  gendername?: string;
  longdeptname?: string;
  dutyName?: string;
  frist_join_date?: string;
  hiredt?: string;
  regularworker_time?: string;
  path?: string;
  status?: number;
}

interface QueryResult {
  items: EmpRow[];
  total: number;
}

const QUERY_URL = backendApi('DynamicQueryBeta/queryforvben');
const EXPORT_URL = backendApi('DynamicQueryBeta/ExportExcel');
const DINGTALK_CFG_URL = backendApi('DingTalkDeptSync/config-status');
const ONB_SYNC_DINGTALK_URL = backendApi('HrEmployeeOnboarding/sync-to-dingtalk');

const selectedDeptPath = ref<string>('');
const deptRows = ref<DeptRow[]>([]);
const treeSearch = ref('');
const expandedKeys = ref<string[]>([]);
const selectedTreeKeys = ref<string[]>([]);
const loadingDept = ref(false);

const route = useRoute();
const accessStore = useAccessStore();
const userStore = useUserStore();
const authStore = useAuthStore();

/** null：不按按钮表过滤（未配置 menuid 或无权限数据时展示全部） */
const allowedActionKeys = ref<null | Set<string>>(null);

const menuId = computed(() => {
  const q = route.meta?.query as Record<string, string> | undefined;
  return (q?.menuid ?? HR_EMPLOYEE_ONBOARDING_LEAF_MENU_ID).trim();
});

function showToolbarAction(actionKey: string): boolean {
  const set = allowedActionKeys.value;
  if (set === null) return true;
  return set.has(actionKey);
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
    const res = await requestClient.post<{ items: any[] }>(QUERY_URL, {
      TableName: 'vben_v_user_role_menu_actions',
      Page: 1,
      PageSize: 500,
      Where: {
        Logic: 'AND',
        Conditions: [
          { Field: 'userid', Operator: 'eq', Value: String(userId) },
          { Field: 'menu_id', Operator: 'eq', Value: mid },
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
    /* 已配置 menuid 但库中尚无授权行时，不收紧为 0 个按钮 */
    allowedActionKeys.value = keys.size > 0 ? keys : null;
  } catch {
    allowedActionKeys.value = null;
  }
}

function buildEmployeeWhere(formValues: Record<string, unknown>): WhereNode {
  const conditions: WhereCondition[] = [
    { Field: 'status', Operator: 'eq', Value: '0' },
  ];

  const empId = String(formValues.EMP_ID ?? '').trim();
  if (empId) {
    conditions.push({ Field: 'EMP_ID', Operator: 'eq', Value: empId });
  }
  const name = String(formValues.name ?? '').trim();
  if (name) {
    conditions.push({ Field: 'name', Operator: 'contains', Value: name });
  }
  const jd = formValues.frist_join_date;
  if (jd) {
    const s = dayjs(jd as any).isValid()
      ? dayjs(jd as any).format('YYYY-MM-DD')
      : String(jd).trim();
    if (s) {
      conditions.push({ Field: 'frist_join_date', Operator: 'eq', Value: s });
    }
  }

  const dp = selectedDeptPath.value.trim();
  if (dp) {
    conditions.push({ Field: 'path', Operator: 'contains', Value: dp });
  }

  return { Logic: 'AND', Conditions: conditions, Groups: [] };
}

const exportQueryField =
  'code as 工号,name as 姓名,EMP_ID as 员工编号,gendername as 性别,longdeptname as 部门,dutyName as 职务,frist_join_date as 入职日期,hiredt as 到职日,regularworker_time as 转正日期,comp_name as 公司';

const formOptions: VbenFormProps = {
  collapsed: false,
  showCollapseButton: true,
  submitOnChange: false,
  submitOnEnter: true,
  schema: [
    {
      component: 'Input',
      fieldName: 'EMP_ID',
      label: '工号',
      componentProps: { allowClear: true, placeholder: '员工编号' },
    },
    {
      component: 'Input',
      fieldName: 'name',
      label: '姓名',
      componentProps: { allowClear: true },
    },
    {
      component: 'DatePicker',
      fieldName: 'frist_join_date',
      label: '入职日期',
      componentProps: { valueFormat: 'YYYY-MM-DD', class: 'w-full' },
    },
  ],
};

const gridOptions: VxeGridProps<EmpRow> = {
  /* 初始高度；挂载后由 ResizeObserver 按容器实测高度覆盖 */
  height: 480,
  columns: [
    { type: 'checkbox', width: 48, fixed: 'left' },
    { type: 'seq', width: 52, title: '#' },
    { field: 'code', title: '工号', width: 88, sortable: true, showOverflow: true },
    { field: 'EMP_ID', title: '员工编号', width: 100, sortable: true, showOverflow: true },
    { field: 'name', title: '姓名', width: 96, sortable: true, showOverflow: true },
    { field: 'gendername', title: '性别', width: 56, showOverflow: true },
    {
      field: 'longdeptname',
      title: '部门',
      minWidth: 160,
      sortable: true,
      showOverflow: true,
    },
    { field: 'dutyName', title: '职务', width: 110, showOverflow: true },
    { field: 'frist_join_date', title: '入职日期', width: 110, sortable: true },
    { field: 'hiredt', title: '到职日', width: 110, sortable: true },
    { field: 'regularworker_time', title: '转正日期', width: 110, sortable: true },
    { field: 'comp_name', title: '公司', minWidth: 120, showOverflow: true },
  ],
  pagerConfig: { enabled: true, pageSize: 20, pageSizes: [20, 50, 100] },
  sortConfig: {
    remote: true,
    defaultSort: { field: 'sort', order: 'asc' },
  },
  toolbarConfig: { custom: true, zoom: true },
  proxyConfig: {
    ajax: {
      query: async ({ page, sort }, formValues) => {
        const where = buildEmployeeWhere(formValues || {});
        const res = await requestClient.post<QueryResult>(QUERY_URL, {
          TableName: 'v_t_base_employee',
          Page: page.currentPage,
          PageSize: page.pageSize,
          SortBy: sort?.field || 'sort',
          SortOrder: (sort?.order || 'asc').toLowerCase(),
          Where: where,
        });
        return res;
      },
    },
  },
};

const [Grid, gridApi] = useVbenVxeGrid<EmpRow>({ gridOptions, formOptions });

const gridWrapRef = ref<HTMLElement | null>(null);

const employeeOnboardingOpen = ref(false);
/** 有值时打开入职弹窗为编辑模式（与列表勾选行的 id 一致） */
const editEmployeeId = ref<string | null>(null);

/** 老系统页面：全屏 iframe 大弹窗（对标 mini.open + win.max） */
const legacyIframeOpen = ref(false);
const legacyIframeSrc = ref('');
const legacyIframeTitle = ref('老系统');
const syncingDingTalk = ref(false);

function openLegacyInBigModal(path: string, title: string): boolean {
  const url = legacyHrmUrl(path);
  if (!url) return false;
  legacyIframeTitle.value = title;
  legacyIframeSrc.value = url;
  legacyIframeOpen.value = true;
  return true;
}


function applyEmployeeOnboardingGridHeight() {
  const el = gridWrapRef.value;
  if (!el) return;
  const rect = el.getBoundingClientRect();
  const h = Math.floor(rect.height);
  const px = Math.max(280, h);
  gridApi.setGridOptions({ height: px });
  nextTick(() => {
    try {
      gridApi.grid?.recalculate?.();
    } catch {
      /* ignore */
    }
  });
}

function scheduleGridHeight() {
  requestAnimationFrame(() => {
    applyEmployeeOnboardingGridHeight();
  });
}

function flatToTree(rows: DeptRow[]): DataNode[] {
  const map = new Map<string, DataNode>();
  for (const r of rows) {
    map.set(r.id, {
      key: r.id,
      title: r.name,
      children: [],
    });
  }
  const roots: DataNode[] = [];
  for (const r of rows) {
    const node = map.get(r.id)!;
    const pid = r.parent_id;
    if (pid && map.has(pid)) {
      const p = map.get(pid)!;
      if (!p.children) p.children = [];
      p.children.push(node);
    } else {
      roots.push(node);
    }
  }
  return roots;
}

const treeData = computed(() => flatToTree(deptRows.value));

const filteredTreeData = computed(() => {
  const q = treeSearch.value.trim().toLowerCase();
  if (!q) return treeData.value;
  const keep = new Set<string>();
  for (const r of deptRows.value) {
    if (String(r.name || '').toLowerCase().includes(q)) {
      keep.add(r.id);
      let pid = r.parent_id;
      while (pid) {
        keep.add(pid);
        const parent = deptRows.value.find((x) => x.id === pid);
        pid = parent?.parent_id ?? null;
      }
    }
  }
  function filterNodes(nodes: DataNode[]): DataNode[] {
    const out: DataNode[] = [];
    for (const n of nodes) {
      const k = String(n.key);
      const children = n.children ? filterNodes(n.children) : [];
      if (keep.has(k) || children.length) {
        out.push({ ...n, children: children.length ? children : undefined });
      }
    }
    return out;
  }
  return filterNodes(treeData.value);
});

async function loadDepartments() {
  loadingDept.value = true;
  try {
    const res = await requestClient.post<QueryResult>(QUERY_URL, {
      TableName: 'v_t_base_department',
      Page: 1,
      PageSize: 5000,
      SortBy: 'path',
      SortOrder: 'asc',
      Where: { Logic: 'AND', Conditions: [], Groups: [] },
    });
    const items = (res as any)?.items ?? [];
    deptRows.value = items.map((x: any) => ({
      id: String(x.id),
      name: String(x.name ?? ''),
      parent_id: x.parent_id ? String(x.parent_id) : null,
      path: x.path != null ? String(x.path) : null,
    }));
    expandedKeys.value = deptRows.value.slice(0, 8).map((r) => r.id);
  } catch (e: any) {
    message.error(e?.message || '加载部门树失败');
  } finally {
    loadingDept.value = false;
  }
}

function onTreeSelect(keys: (string | number)[]) {
  const id = keys.length ? String(keys[0]) : '';
  if (!id) {
    selectedDeptPath.value = '';
  } else {
    const row = deptRows.value.find((r) => r.id === id);
    selectedDeptPath.value = (row?.path ?? '').trim();
  }
  gridApi.query();
}

function clearDeptFilter() {
  selectedTreeKeys.value = [];
  selectedDeptPath.value = '';
  gridApi.query();
}

function getSelectedRows(): EmpRow[] {
  const g = gridApi.grid;
  if (!g) return [];
  return (g.getCheckboxRecords?.() ?? []) as EmpRow[];
}

function getSingleSelected(): EmpRow | null {
  const rows = getSelectedRows();
  if (rows.length !== 1) return null;
  return rows[0] ?? null;
}

function onEmployeeEntry() {
  editEmployeeId.value = null;
  employeeOnboardingOpen.value = true;
}

function onEdit() {
  const row = getSingleSelected();
  if (!row?.id) {
    message.warning('请选中一条记录');
    return;
  }
  editEmployeeId.value = row.id;
  employeeOnboardingOpen.value = true;
}

type DingTalkDeptSyncCfg = {
  configured?: boolean;
  enabled?: boolean;
  missingKeys?: string[];
};

async function assertDingTalkReady(): Promise<boolean> {
  const cfg = (await requestClient.get(DINGTALK_CFG_URL)) as DingTalkDeptSyncCfg;
  if (!cfg?.configured) {
    message.warning(
      '未配置钉钉同步字典。请在「数据字典」中维护 DingTalk_DeptSync（enabled；corp_id=Client ID；corp_secret=Client Secret）。',
    );
    return false;
  }
  if (cfg.missingKeys?.length) {
    message.warning(`数据字典缺少项：${cfg.missingKeys.join('、')}，请补全后再试。`);
    return false;
  }
  if (!cfg.enabled) {
    message.warning('钉钉同步未启用：请将字典明细 enabled 设为 1。');
    return false;
  }
  return true;
}

async function onSyncToDingTalk() {
  const rows = getSelectedRows().filter((x) => Boolean(x?.id));
  if (!rows.length) {
    message.warning('请至少选中一条记录');
    return;
  }
  syncingDingTalk.value = true;
  try {
    if (!(await assertDingTalkReady())) return;
    let ok = 0;
    const failed: string[] = [];
    for (const r of rows) {
      try {
        await requestClient.post(ONB_SYNC_DINGTALK_URL, { employeeId: r.id });
        ok += 1;
      } catch (e: any) {
        const emp = String(r.code ?? r.EMP_ID ?? r.name ?? r.id);
        const err =
          e?.message ||
          e?.response?.data?.message ||
          e?.response?.data?.error ||
          '同步失败';
        failed.push(`${emp}: ${err}`);
      }
    }
    if (!failed.length) {
      message.success(`已完成同步，共 ${ok} 人。`);
      return;
    }
    if (ok > 0) {
      message.warning(`部分成功：成功 ${ok} 人，失败 ${failed.length} 人。首条失败：${failed[0]}`);
      return;
    }
    message.error(`同步失败：${failed[0]}`);
  } finally {
    syncingDingTalk.value = false;
  }
}

function onSetNormalDate() {
  const row = getSingleSelected();
  const q = row?.id
    ? `?id=${encodeURIComponent(row.id)}`
    : '';
  if (!openLegacyInBigModal(`/BaseEmployee/SetNormalDate${q}`, '调整入职/转正日期')) {
    message.warning('未配置 VITE_LEGACY_HRM_ORIGIN');
  }
}

function onPrintArchive() {
  const row = getSingleSelected();
  if (!row?.id) {
    message.warning('请选中一条记录');
    return;
  }
  if (
    !openLegacyInBigModal(
      `/ReportList/ReportEmpolyeeInfo.aspx?id=${encodeURIComponent(row.id)}`,
      '员工档案信息打印',
    )
  ) {
    message.warning('未配置 VITE_LEGACY_HRM_ORIGIN');
  }
}

function onPrintWorkCard() {
  const rows = getSelectedRows();
  if (!rows.length) {
    message.warning('请选中至少一条记录');
    return;
  }
  Modal.info({
    title: '工牌打印',
    content:
      '老系统通过弹窗向内嵌页传递选中行数据；新窗口仅打开方案页，可能无法带入人员。请优先在老系统「员工入职登记」中操作工牌打印，或后续对接独立打印接口。',
    onOk: () => {
      openLegacyInBigModal(
        `/BaseEmployee/PrintWorkCard?length=${rows.length}`,
        '工牌打印方案选择',
      );
    },
  });
}

async function onExportExcel() {
  try {
    const formApi = gridApi.formApi as unknown as {
      getValues?: () => Promise<Record<string, unknown>>;
    };
    const formValues = (await formApi?.getValues?.()) ?? {};
    const sort = gridApi.grid?.getSortColumns?.()?.[0];
    const where = buildEmployeeWhere(formValues);
    const token = accessStore.accessToken;
    const res = await fetch(EXPORT_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({
        TableName: 'v_t_base_employee',
        Where: where,
        SortBy: sort?.field || 'sort',
        SortOrder: (sort?.order || 'asc').toString().toLowerCase(),
        QueryField: exportQueryField,
      }),
    });
    if (!res.ok) {
      const t = await res.text();
      throw new Error(t || res.statusText);
    }
    const buf = await res.arrayBuffer();
    const blob = new Blob([buf], {
      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `员工入职登记_${dayjs().format('YYYYMMDD_HHmm')}.xlsx`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
    message.success('导出成功');
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    message.error(`导出失败：${msg || '未知错误'}`);
  }
}

onMounted(() => {
  loadDepartments();
  loadToolbarPermissions();
});

watch(
  gridWrapRef,
  (el, _prev, onCleanup) => {
    if (!el) return;
    scheduleGridHeight();
    const ro = new ResizeObserver(() => scheduleGridHeight());
    ro.observe(el);
    onCleanup(() => ro.disconnect());
  },
  { flush: 'post' },
);

watch(menuId, () => {
  loadToolbarPermissions();
});

watch(treeSearch, (q) => {
  if (!q.trim()) return;
  expandedKeys.value = deptRows.value.map((r) => r.id);
});

watch(legacyIframeOpen, (open, prev) => {
  if (prev === true && open === false) {
    gridApi.reload();
  }
});

watch(employeeOnboardingOpen, (open) => {
  if (!open) editEmployeeId.value = null;
});
</script>

<template>
  <Page
    auto-content-height
    content-class="flex min-h-0 flex-col overflow-hidden"
  >
    <div class="flex min-h-0 flex-1 flex-col">
    <Layout class="hr-onboard-layout min-h-0 flex-1 rounded border border-border bg-card">
      <Sider
        :width="268"
        class="hr-onboard-sider !flex-shrink-0 border-r border-border bg-muted/30"
        theme="light"
      >
        <div class="p-2">
          <div class="mb-2 text-sm font-medium text-foreground">部门</div>
          <Input.Search
            v-model:value="treeSearch"
            allow-clear
            class="mb-2"
            placeholder="筛选部门名称"
          />
          <Button block class="mb-2" size="small" type="link" @click="clearDeptFilter">
            清除部门筛选
          </Button>
          <div
            v-if="loadingDept"
            class="py-6 text-center text-muted-foreground text-sm"
          >
            加载部门…
          </div>
          <Tree
            v-else
            v-model:expanded-keys="expandedKeys"
            v-model:selected-keys="selectedTreeKeys"
            :field-names="{ title: 'title', key: 'key', children: 'children' }"
            :show-line="true"
            :tree-data="filteredTreeData"
            block-node
            @select="onTreeSelect"
          />
        </div>
      </Sider>
      <Content class="hr-onboard-content min-h-0 min-w-0 flex-1 p-2">
        <div ref="gridWrapRef" class="hr-grid-wrap">
        <Grid>
          <template #toolbar-tools>
            <Button
              v-if="showToolbarAction(HR_ONB_ACTION.entry)"
              class="mr-2"
              type="primary"
              @click="onEmployeeEntry"
            >
              员工入职
            </Button>
            <Button
              v-if="showToolbarAction(HR_ONB_ACTION.edit)"
              class="mr-2"
              @click="onEdit"
            >
              修改
            </Button>
            <Button
              v-if="showToolbarAction(HR_ONB_ACTION.syncDingTalk)"
              class="mr-2"
              :loading="syncingDingTalk"
              @click="onSyncToDingTalk"
            >
              同步钉钉
            </Button>
            <Button
              v-if="showToolbarAction(HR_ONB_ACTION.setDate)"
              class="mr-2"
              @click="onSetNormalDate"
            >
              调整入职/转正日期
            </Button>
            <Button
              v-if="showToolbarAction(HR_ONB_ACTION.export)"
              class="mr-2"
              @click="onExportExcel"
            >
              导出
            </Button>
            <Button
              v-if="showToolbarAction(HR_ONB_ACTION.printCard)"
              class="mr-2"
              @click="onPrintWorkCard"
            >
              工牌打印
            </Button>
            <Button
              v-if="showToolbarAction(HR_ONB_ACTION.printArchive)"
              class="mr-2"
              @click="onPrintArchive"
            >
              员工档案信息打印
            </Button>
          </template>
        </Grid>
        </div>
      </Content>
    </Layout>
    </div>

    <EmployeeOnboardingModal
      v-model:open="employeeOnboardingOpen"
      :edit-employee-id="editEmployeeId"
      @saved="gridApi.reload()"
    />

    <LegacyHrmIframeModal
      v-model:open="legacyIframeOpen"
      :src="legacyIframeSrc"
      :title="legacyIframeTitle"
    />
  </Page>
</template>

<style scoped>
/* 与左侧部门树并排占满 Page 内容区剩余高度 */
.hr-onboard-layout {
  display: flex;
  flex-direction: row;
  min-height: 0;
}

.hr-onboard-sider {
  align-self: stretch;
}

.hr-onboard-sider :deep(.ant-layout-sider-children) {
  height: 100%;
  max-height: none;
  overflow: auto;
}

.hr-onboard-content {
  display: flex;
  flex-direction: column;
  min-width: 0;
  min-height: 0;
}

/* 包裹 VxeGrid，由 flex 分配高度；具体像素高由脚本 ResizeObserver 写入 */
.hr-grid-wrap {
  display: flex;
  flex: 1 1 0%;
  flex-direction: column;
  min-height: 0;
  min-width: 0;
}

.hr-grid-wrap :deep(> *) {
  display: flex;
  flex: 1 1 0%;
  flex-direction: column;
  min-height: 0;
}

.hr-onboard-content :deep(.vxe-grid) {
  padding-top: 0;
}
</style>
