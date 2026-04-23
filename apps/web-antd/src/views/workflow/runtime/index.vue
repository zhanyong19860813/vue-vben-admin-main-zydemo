<script setup lang="ts">
import type { Component as VueConcreteComponent } from 'vue';
import { computed, h, nextTick, onMounted, ref, shallowRef, watch } from 'vue';
import { useRoute } from 'vue-router';

import { Page } from '@vben/common-ui';
import { useAccessStore, useUserStore } from '@vben/stores';
import type { VbenFormSchema } from '#/adapter/form';
import { useVbenForm } from '#/adapter/form';
import { getWorkflowFormSchemaList } from '#/api/workflow';
import {
  applyProcessTitleBySchemaLabel,
  buildWorkflowBuiltinValuesFromUser,
  looksLikeEmployeeOrLoginId,
  restoreBuiltinValuesAfterJsonMerge,
  supplementBuiltinValuesByFieldLabel,
} from '#/views/demos/form-designer/workflowFormRuntime';
import FormTabsTablePreview from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import type { TabTableConfig } from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import type { WfNodeFormFieldRule } from '#/views/demos/workflow-designer/workflow-definition.schema';
import {
  applyFieldRulesToSchemaPlain,
  coerceLatestMainForm,
  coerceLatestTabsData,
  getStartNodeBinding,
  inferBizTypeFromGraphNode,
  isLikelyStartNode,
  jsonSafeClone,
  normalizeFieldRule,
  normalizeSchemaForPreview,
  parseStoredFormSchemaJson,
  resolveNodeFormBindingWithStartFallback,
} from '#/views/workflow/wfFormPreviewUtils';
import { createExtWorkflowFormComponent } from '#/views/workflowExtForm/registry';
import ProcessPreviewShell from '#/views/workflow/process-preview/ProcessPreviewShell.vue';
import {
  collectEmployeeIdsForDisplay,
  fetchEmployeeDisplayLabelsByIds,
  formatOperatorLabel,
  resolveActorFromLatestAndPending,
} from '#/views/workflow/workflowOperatorDisplay';
import RuntimeGraphReadonly from './RuntimeGraphReadonly.vue';

import {
  Button,
  Card,
  Input,
  Modal,
  Space,
  Table,
  Tabs,
  Tag,
  Timeline,
  message,
} from 'ant-design-vue';

import {
  type WfEngineRuntimeTodoItem,
  wfEngineRuntimeCompleteTask,
  wfEngineGetProcess,
  wfEngineRuntimeInstanceDetail,
  wfEngineRuntimeInstanceTimeline,
  wfEngineRuntimeStart,
  wfEngineRuntimeTodo,
  setWorkflowRuntimeMockAssigneeUserId,
} from '#/api/workflowEngine';
import { useAuthStore } from '#/store';

const route = useRoute();
const userStore = useUserStore();
const accessStore = useAccessStore();
const authStore = useAuthStore();
const isMobilePreviewMode = computed(() => String(route.query.mode || '') === 'mobile');

function decodeJwtPayload(token: null | string): Record<string, unknown> | null {
  if (!token || typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const pad = b64.length % 4 === 0 ? '' : '='.repeat(4 - (b64.length % 4));
    const json = atob(b64 + pad);
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
}

const DEBUG_PANEL_OPEN_KEY = 'wf-runtime-debug-panel-open';
function readSavedDebugPanelOpen() {
  try {
    const v = typeof localStorage === 'undefined' ? '' : localStorage.getItem(DEBUG_PANEL_OPEN_KEY);
    if (v === '0') return false;
    if (v === '1') return true;
  } catch {
    // ignore
  }
  // 默认展开：便于联调定位
  return true;
}
const showDebugPanel = ref(readSavedDebugPanelOpen());

const processCode = ref('');
const processDefId = ref('');
const runtimeDraftKey = ref('');
const runtimeDraftDefinitionJson = ref('');
const businessKey = ref('');
const title = ref('');
const starterDeptId = ref('');
const mockStarterUserId = ref('');
const mockStarterName = ref('');
const mockStarterDeptName = ref('');
const mockStarterPositionName = ref('');

function isLikelyGuidStr(s: string): boolean {
  const t = s.trim();
  if (!t) return false;
  const unbrace = t.startsWith('{') && t.endsWith('}') ? t.slice(1, -1) : t;
  return /^[\da-f]{8}-[\da-f]{4}-[1-5][\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i.test(unbrace);
}

/** 合并 userStore + JWT，供流程内置字段带出姓名/工号/部门/岗位 */
function mergeUserInfoForWorkflow(): Record<string, any> {
  const u: Record<string, any> = { ...(userStore.userInfo as any) };
  /** 后端常把登录号放在 name，避免占住「姓名」且补全工号 */
  const rawName = String(u.name || '').trim();
  if (rawName && looksLikeEmployeeOrLoginId(rawName) && !String(u.realName || '').trim()) {
    if (!String(u.employeeCode || '').trim()) u.employeeCode = rawName;
    if (!String(u.employeeNo || '').trim()) u.employeeNo = rawName;
    delete u.name;
  }
  const jwt = decodeJwtPayload(accessStore.accessToken);
  if (jwt) {
    const j = jwt as Record<string, unknown>;
    const str = (k: string) => {
      const v = j[k];
      return v !== undefined && v !== null ? String(v).trim() : '';
    };
    /** JWT「姓名」：name 常与登录号相同，只采用不像工号的 name/given_name */
    const jwtHumanName = str('name') || str('given_name');
    if (jwtHumanName && !looksLikeEmployeeOrLoginId(jwtHumanName)) {
      if (!String(u.realName || '').trim()) u.realName = jwtHumanName;
      if (!String(u.name || '').trim()) u.name = jwtHumanName;
    }
    /** 登录账号 → 工号（OIDC unique_name / preferred_username） */
    const loginAccount = str('unique_name') || str('preferred_username');
    if (loginAccount && !isLikelyGuidStr(loginAccount)) {
      if (!String(u.employeeCode || '').trim()) u.employeeCode = loginAccount;
      if (!String(u.employeeNo || '').trim()) u.employeeNo = loginAccount;
      if (!String(u.username || '').trim()) u.username = loginAccount;
    }
    if (!String(u.username || '').trim()) {
      const un = str('preferred_username');
      if (un) u.username = un;
    }
    const uid = str('UserId') || str('userId') || str('sub');
    if (uid && !String(u.userId || '').trim()) u.userId = uid;
    const emp = str('employee_id') || str('EmployeeId') || str('emp_code');
    if (emp && !isLikelyGuidStr(emp)) {
      if (!String(u.employeeCode || '').trim()) u.employeeCode = emp;
      if (!String(u.employeeNo || '').trim()) u.employeeNo = emp;
    }
    if (!String(u.deptName || '').trim()) {
      const dn =
        str('deptName') ||
        str('departmentName') ||
        str('department_name') ||
        str('DeptName') ||
        str('department') ||
        str('dept') ||
        str('org_name') ||
        str('orgName') ||
        str('organizationName');
      if (dn) {
        u.deptName = dn;
        u.departmentName = dn;
      }
    }
    if (!String(u.positionName || '').trim()) {
      const pn =
        str('positionName') ||
        str('dutyName') ||
        str('postName') ||
        str('title') ||
        str('post') ||
        str('jobTitle') ||
        str('JobTitle');
      if (pn) {
        u.positionName = pn;
        u.dutyName = pn;
        u.postName = pn;
      }
    }
  }
  if (mockStarterName.value) {
    u.realName = mockStarterName.value;
    u.name = mockStarterName.value;
  }
  if (mockStarterUserId.value) {
    u.employeeCode = mockStarterUserId.value;
    u.employeeNo = mockStarterUserId.value;
    u.userCode = mockStarterUserId.value;
    u.username = mockStarterUserId.value;
  }
  if (mockStarterDeptName.value) {
    u.deptName = mockStarterDeptName.value;
    u.departmentName = mockStarterDeptName.value;
  }
  if (mockStarterPositionName.value) {
    u.positionName = mockStarterPositionName.value;
    u.dutyName = mockStarterPositionName.value;
    u.postName = mockStarterPositionName.value;
  }
  return u;
}

/**
 * `/workflow/runtime-embed` 等为 core 子路由，路由守卫对 core 直接放行，不会走 fetchUserInfo；
 * 新开全屏页往往仅有 localStorage 中的 token，userInfo 仍为空，内置姓名/工号/部门/岗位无法带出。
 */
async function ensureUserInfoForWorkflowRuntime() {
  if (!accessStore.accessToken) return;
  const u = userStore.userInfo as Record<string, any> | null | undefined;
  const hasUsable =
    u &&
    (String(u.realName || u.name || '').trim() ||
      String(u.username || '').trim() ||
      String(u.employeeCode || u.employeeNo || '').trim());
  if (hasUsable) return;
  try {
    await authStore.fetchUserInfo();
  } catch {
    // 忽略：mergeUserInfoForWorkflow 仍可能从 JWT 补一部分
  }
}

/** 测试：模拟「办理人」工号，请求头 X-Workflow-Mock-User-Id（与模拟发起人不同：后者只影响发起） */
function readSavedMockAssigneeId() {
  try {
    return typeof sessionStorage === 'undefined'
      ? ''
      : sessionStorage.getItem('wf-runtime-mock-assignee-id') || '';
  } catch {
    return '';
  }
}
const mockAssigneeUserId = ref(readSavedMockAssigneeId());
const mockAssigneeName = ref('');
const mainFormJson = ref(
  JSON.stringify(
    {
      amount: 1200,
      dept: '研发部',
      applicant: '张三',
      reason: '设备采购',
    },
    null,
    2,
  ),
);
/** 发起时已提交的主表/明细缓存：用于提交后重渲染时保持页面不变 */
const submittedStartMainForm = ref<null | Record<string, any>>(null);
const submittedStartTabsData = ref<null | Record<string, any[]>>(null);

const startLoading = ref(false);
const saveDraftLoading = ref(false);
const lastStartResp = ref<Record<string, unknown> | null>(null);
const startSubmittedInstanceNo = ref('');
const startSubmittedHeaderFlowNo = ref('');

const todoLoading = ref(false);
const todoActionLoading = ref('');
const todoRows = ref<WfEngineRuntimeTodoItem[]>([]);
const todoPage = ref(1);
const todoPageSize = ref(20);
const todoTotal = ref(0);

const actionModalOpen = ref(false);
const actionType = ref<'agree' | 'reject'>('agree');
const actionRow = ref<WfEngineRuntimeTodoItem | null>(null);
const actionComment = ref('');
const actionRejectToNodeId = ref('');

const detailLoading = ref(false);
const timelineLoading = ref(false);
const inspectInstanceId = ref('');
const instanceDetail = ref<Record<string, any> | null>(null);
const timelineRows = ref<Array<Record<string, any>>>([]);
const operatorDisplayMap = ref<Record<string, string>>({});

async function refreshOperatorDisplayCache() {
  const ids = collectEmployeeIdsForDisplay(
    timelineRows.value || [],
    (instanceDetail.value?.tasks as Array<Record<string, any>>) || [],
  );
  if (!ids.length) {
    operatorDisplayMap.value = {};
    return;
  }
  const m = await fetchEmployeeDisplayLabelsByIds(ids);
  operatorDisplayMap.value = m;
}
const debugEvents = ref<Array<Record<string, any>>>([]);
const runtimePerfLogs = ref<
  Array<{ at: string; error?: string; ms: number; name: string; ok: boolean }>
>([]);
const SHOW_RUNTIME_PERF_LOG = false;

function pushRuntimePerfLog(name: string, ms: number, ok: boolean, error?: string) {
  runtimePerfLogs.value.unshift({
    name,
    ms: Number.isFinite(ms) ? Math.round(ms) : -1,
    ok,
    error: error ? String(error) : undefined,
    at: new Date().toLocaleTimeString(),
  });
  if (runtimePerfLogs.value.length > 40) {
    runtimePerfLogs.value = runtimePerfLogs.value.slice(0, 40);
  }
}

async function profiled<T>(name: string, fn: () => Promise<T>): Promise<T> {
  const t0 = performance.now();
  try {
    const v = await fn();
    pushRuntimePerfLog(name, performance.now() - t0, true);
    return v;
  } catch (err) {
    pushRuntimePerfLog(name, performance.now() - t0, false, (err as Error)?.message || String(err));
    throw err;
  }
}
const startBindingLoading = ref(false);
const startBindingHint = ref('当前流程暂未读取到发起节点绑定表单，使用 JSON 方式发起。');
const startBoundFormCode = ref('');
const startBoundFormName = ref('');
const startBoundFormMode = ref<'designer' | 'ext' | 'json'>('json');
const startExtRuntimeRoot = shallowRef<VueConcreteComponent | null>(null);
const startFormSchema = ref<VbenFormSchema[]>([]);
/** 设计器「上表+页签表格」布局（与 NodeFormBindingModal / 流程预览一致） */
const startLayoutIsTabs = ref(false);
const startTabsConfig = ref<TabTableConfig[]>([]);
const startTabsInitialMainValues = ref<Record<string, any>>({});
const startTabsFieldRulesMap = ref<Record<string, WfNodeFormFieldRule>>({});
const startTabsTablePreviewRef = ref<InstanceType<typeof FormTabsTablePreview> | null>(null);
/** 当前流程定义 JSON，用于渲染与「流程预览」一致的步骤条 */
const runtimeDefinitionJson = ref('');
/** 从接口加载的流程名称/编码（主界面展示，不暴露技术参数） */
const loadedProcessName = ref('');
const loadedProcessCode = ref('');
const startMetaWorkflowNo = ref('');
const startMetaDept = ref('');
const startMetaPosition = ref('');
const startMetaEmployeeNo = ref('');
const startMetaWorkflowNoPrefix = ref('WF');

function buildStartFixedMetaValues(workflowNoPrefix?: string) {
  const seedUser = mergeUserInfoForWorkflow();
  const builtins = buildWorkflowBuiltinValuesFromUser(
    [
      { fieldName: '__flowNo', componentProps: { workflowBuiltin: 'flowNo' } },
      { fieldName: '__employeeNo', componentProps: { workflowBuiltin: 'employeeNo' } },
      { fieldName: '__dept', componentProps: { workflowBuiltin: 'dept' } },
      { fieldName: '__position', componentProps: { workflowBuiltin: 'position' } },
    ] as unknown as VbenFormSchema[],
    {
      userInfo: seedUser,
      workflowNoPrefix: workflowNoPrefix || startMetaWorkflowNoPrefix.value,
      processTitle: loadedProcessName.value,
    },
  );
  return {
    flowNo: String(builtins.__flowNo || '').trim(),
    employeeNo: String(builtins.__employeeNo || '').trim(),
    dept: String(builtins.__dept || '').trim(),
    position: String(builtins.__position || '').trim(),
  };
}

function refreshStartFixedMeta(options?: { keepWorkflowNo?: boolean; workflowNoPrefix?: string }) {
  const fixed = buildStartFixedMetaValues(options?.workflowNoPrefix);
  if (!options?.keepWorkflowNo || !startMetaWorkflowNo.value.trim()) {
    startMetaWorkflowNo.value = fixed.flowNo;
  }
  startMetaDept.value = fixed.dept;
  startMetaPosition.value = fixed.position;
  startMetaEmployeeNo.value = fixed.employeeNo;
}

const [StartBoundForm, startBoundFormApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as VbenFormSchema[],
  wrapperClass: 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
  layout: 'horizontal',
  formItemGapPx: 2 as any,
  commonConfig: { labelWidth: 110 } as any,
});
function buildStartFormUiState(schema: VbenFormSchema[] = [] as VbenFormSchema[]) {
  return {
    schema,
    layout: isMobilePreviewMode.value ? 'vertical' : 'horizontal',
    wrapperClass: isMobilePreviewMode.value
      ? 'wf-mobile-form-single grid-cols-1 gap-y-2'
      : 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
    commonConfig: isMobilePreviewMode.value ? ({ labelWidth: 88 } as any) : ({ labelWidth: 110 } as any),
  } as const;
}

/** 当前待办节点绑定的办理表单（设计器 / 硬编码 / 无绑定时仅快照） */
const taskBoundFormLoading = ref(false);
/** 并发多次 loadTaskBoundForm 时计数，避免先完成的请求错误地关掉仍在进行的 loading */
let taskFormLoadInFlight = 0;
let taskFormLoadLatestSeq = 0;
let taskFormLoadSafetyTimer: ReturnType<typeof setTimeout> | null = null;
const taskBoundFormMode = ref<'none' | 'designer' | 'ext' | 'snapshot'>('none');
const taskBoundFormReuseError = ref('');
const taskFormSchema = ref<VbenFormSchema[]>([]);
const taskExtRuntimeRoot = shallowRef<VueConcreteComponent | null>(null);
const taskBindingHint = ref('');
const taskLayoutIsTabs = ref(false);
const taskTabsConfig = ref<TabTableConfig[]>([]);
const taskTabsInitialMainValues = ref<Record<string, any>>({});
const taskTabsFieldRulesMap = ref<Record<string, WfNodeFormFieldRule>>({});
const taskTabsTablePreviewRef = ref<InstanceType<typeof FormTabsTablePreview> | null>(null);
const taskPendingTabsData = ref<Record<string, any[]>>({});
const [TaskBoundForm, taskBoundFormApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as VbenFormSchema[],
  wrapperClass: 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
  layout: 'horizontal',
  formItemGapPx: 2 as any,
  commonConfig: { labelWidth: 110 } as any,
});
function buildTaskFormUiState(schema: VbenFormSchema[] = [] as VbenFormSchema[]) {
  return {
    schema,
    layout: isMobilePreviewMode.value ? 'vertical' : 'horizontal',
    wrapperClass: isMobilePreviewMode.value
      ? 'wf-mobile-form-single grid-cols-1 gap-y-2'
      : 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
    commonConfig: isMobilePreviewMode.value ? ({ labelWidth: 88 } as any) : ({ labelWidth: 110 } as any),
  } as const;
}
const REQUIRED_MISSING_CLASS = 'wf-required-missing';
const startMissingRequiredKeys = ref<string[]>([]);
const taskMissingRequiredKeys = ref<string[]>([]);

function applyRequiredMissingStyleToSchema(
  schema: VbenFormSchema[],
  requiredKeys: string[],
  missingKeys: string[],
): VbenFormSchema[] {
  const required = new Set((requiredKeys || []).map((k) => String(k || '').trim()).filter(Boolean));
  const missing = new Set((missingKeys || []).map((k) => String(k || '').trim()).filter(Boolean));
  return (schema || []).map((item) => {
    const fieldKey = String(item?.fieldName || '').trim();
    const oldCls = String(item?.formItemClass || '')
      .split(/\s+/)
      .filter(Boolean)
      .filter((x) => x !== 'wf-required-mark')
      .filter((x) => x !== REQUIRED_MISSING_CLASS);
    if (fieldKey && required.has(fieldKey)) oldCls.push('wf-required-mark');
    if (fieldKey && missing.has(fieldKey)) oldCls.push(REQUIRED_MISSING_CLASS);
    const oldLabelCls = String((item as any)?.labelClass || '')
      .split(/\s+/)
      .filter(Boolean)
      .filter((x) => x !== 'wf-required-label')
      .filter((x) => x !== 'wf-required-missing-label');
    if (fieldKey && required.has(fieldKey)) oldLabelCls.push('wf-required-label');
    if (fieldKey && missing.has(fieldKey)) oldLabelCls.push('wf-required-missing-label');
    const hasRequired = fieldKey && required.has(fieldKey);
    const originalSuffix = (item as any)?.suffix;
    const requiredSuffix = hasRequired
      ? () =>
          h(
            'span',
            {
              class: 'wf-required-inline-star',
              title: '必填',
            },
            '*',
          )
      : originalSuffix;
    return {
      ...item,
      formItemClass: oldCls.join(' '),
      labelClass: oldLabelCls.join(' '),
      suffix: requiredSuffix,
    } as VbenFormSchema;
  });
}

async function applyStartRequiredVisual(missingKeys: string[]) {
  startMissingRequiredKeys.value = [...missingKeys];
  if (startBoundFormMode.value !== 'designer' || !startFormSchema.value.length) return;
  const requiredKeys = collectRequiredFieldKeysFromRules(startTabsFieldRulesMap.value).mainKeys;
  startFormSchema.value = applyRequiredMissingStyleToSchema(
    startFormSchema.value as VbenFormSchema[],
    requiredKeys,
    missingKeys,
  );
  if (!startLayoutIsTabs.value) {
    await startBoundFormApi.setState(buildStartFormUiState(startFormSchema.value as VbenFormSchema[]));
  }
}

async function applyTaskRequiredVisual(missingKeys: string[]) {
  taskMissingRequiredKeys.value = [...missingKeys];
  if (taskBoundFormMode.value !== 'designer' || !taskFormSchema.value.length) return;
  const requiredKeys = collectRequiredFieldKeysFromRules(taskTabsFieldRulesMap.value).mainKeys;
  taskFormSchema.value = applyRequiredMissingStyleToSchema(
    taskFormSchema.value as VbenFormSchema[],
    requiredKeys,
    missingKeys,
  );
  if (!taskLayoutIsTabs.value) {
    await taskBoundFormApi.setState(buildTaskFormUiState(taskFormSchema.value as VbenFormSchema[]));
  }
}

function withTimeout<T>(p: Promise<T> | T, ms: number, label: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const tid = setTimeout(
      () => reject(new Error(`${label} 超时（${Math.round(ms / 1000)}s）`)),
      ms,
    );
    Promise.resolve(p).then(
      (v) => {
        clearTimeout(tid);
        resolve(v);
      },
      (e) => {
        clearTimeout(tid);
        reject(e);
      },
    );
  });
}

function toPrettyJson(value: unknown) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

let workflowFormSchemaIndexCache: Map<string, Record<string, any>> | null = null;
let workflowFormSchemaIndexLoading: Promise<Map<string, Record<string, any>>> | null = null;

async function getWorkflowFormSchemaByCode(formCode: string) {
  const code = String(formCode || '').trim();
  if (!code) return null;
  if (workflowFormSchemaIndexCache?.has(code)) {
    return workflowFormSchemaIndexCache.get(code) || null;
  }
  if (!workflowFormSchemaIndexLoading) {
    workflowFormSchemaIndexLoading = (async () => {
      const listRaw = (await getWorkflowFormSchemaList()) as any;
      const formRows = (Array.isArray(listRaw)
        ? listRaw
        : listRaw?.items || listRaw?.records || []) as Array<Record<string, any>>;
      const map = new Map<string, Record<string, any>>();
      for (const row of formRows) {
        const c = String(row?.code || '').trim();
        if (!c) continue;
        map.set(c, row);
      }
      workflowFormSchemaIndexCache = map;
      return map;
    })().finally(() => {
      workflowFormSchemaIndexLoading = null;
    });
  }
  const idx = await workflowFormSchemaIndexLoading;
  return idx.get(code) || null;
}

function extractErrorSummary(payload: Record<string, any>) {
  const first =
    [payload.message, payload.error, payload.detail, payload.title].find(
      (x) => typeof x === 'string' && String(x).trim(),
    ) || '';
  return String(first || '请求失败');
}

function pushDebugEvent(action: string, err: unknown) {
  const e = err as any;
  const response = e?.response;
  const payload = (response?.data ?? null) as Record<string, any> | null;
  const summary = extractErrorSummary(payload || {});
  const rawMessage = String(e?.message || e?.msg || e || '').trim();
  const finalSummary = summary === '请求失败' && rawMessage ? rawMessage : summary;
  const validationErrors = payload?.errors ?? null;
  debugEvents.value.unshift({
    at: new Date().toLocaleString(),
    action,
    summary: finalSummary,
    status: response?.status,
    method: String(e?.config?.method || '').toUpperCase(),
    url: e?.config?.url || '',
    traceId: payload?.traceId || '',
    payload,
    validationErrors,
    rawMessage,
    rawError: e,
  });
  if (debugEvents.value.length > 20) {
    debugEvents.value = debugEvents.value.slice(0, 20);
  }
}

async function resetBoundFormState(hint: string) {
  startBindingHint.value = hint;
  startBoundFormCode.value = '';
  startBoundFormName.value = '';
  startBoundFormMode.value = 'json';
  startExtRuntimeRoot.value = null;
  startFormSchema.value = [];
  startLayoutIsTabs.value = false;
  startTabsConfig.value = [];
  startTabsInitialMainValues.value = {};
  startTabsFieldRulesMap.value = {};
  startMetaWorkflowNoPrefix.value = 'WF';
  refreshStartFixedMeta({ keepWorkflowNo: false, workflowNoPrefix: startMetaWorkflowNoPrefix.value });
  await startBoundFormApi.setState(buildStartFormUiState([] as VbenFormSchema[]));
  await startBoundFormApi.setValues({});
}

function parseWorkflowGraphNodes(defJson: string): Array<{ id: string; title: string }> {
  if (!defJson.trim()) return [];
  try {
    const parsed = JSON.parse(defJson) as { graphData?: { nodes?: any[] } };
    const nodes = parsed?.graphData?.nodes ?? [];
    const out: Array<{ id: string; title: string }> = [];
    for (const n of nodes) {
      const id = String(n?.id ?? '').trim();
      if (!id) continue;
      const biz = inferBizTypeFromGraphNode(n);
      if (biz === 'edge' || biz === 'line') continue;
      const tv = String(n?.text?.value ?? n?.text ?? '').trim();
      out.push({ id, title: tv || id });
    }
    return out;
  } catch {
    return [];
  }
}

function applyRuntimeDraftByKey(key: string) {
  const k = String(key || '').trim();
  if (!k) return;
  try {
    const raw = localStorage.getItem(k);
    if (!raw) return;
    const parsed = JSON.parse(raw) as {
      definition?: Record<string, unknown> | string;
      processCode?: string;
      processName?: string;
    };
    const defObj = parsed?.definition;
    const definitionJson =
      typeof defObj === 'string'
        ? defObj.trim()
        : defObj && typeof defObj === 'object'
          ? JSON.stringify(defObj)
          : '';
    if (!definitionJson) return;
    runtimeDraftDefinitionJson.value = definitionJson;
    // 草稿定义优先用于运行台渲染（流程图/节点表单绑定）
    runtimeDefinitionJson.value = definitionJson;
    if (!processCode.value.trim() && parsed?.processCode) {
      processCode.value = String(parsed.processCode || '').trim();
    }
    if (parsed?.processName) {
      loadedProcessName.value = String(parsed.processName || '').trim();
    }
  } catch {
    runtimeDraftDefinitionJson.value = '';
  }
}

async function loadStartBoundForm() {
  startBindingLoading.value = true;
  try {
    const draftDefinitionJson = runtimeDraftDefinitionJson.value.trim();
    let definitionJson = draftDefinitionJson;
    if (!definitionJson) {
      const defId = processDefId.value.trim();
      if (!defId) {
        runtimeDefinitionJson.value = '';
        loadedProcessName.value = '';
        loadedProcessCode.value = '';
        await resetBoundFormState('未传 processDefId，无法读取发起节点绑定表单，使用 JSON 方式发起。');
        return;
      }
      const proc = await wfEngineGetProcess(defId);
      loadedProcessName.value = String((proc as { processDef?: { processName?: string; processCode?: string } })?.processDef?.processName ?? '').trim();
      loadedProcessCode.value = String((proc as { processDef?: { processName?: string; processCode?: string } })?.processDef?.processCode ?? '').trim();
      definitionJson = String(proc?.version?.definitionJson || '').trim();
    } else {
      loadedProcessCode.value = processCode.value.trim();
    }
    runtimeDefinitionJson.value = definitionJson;
    if (!definitionJson) {
      await resetBoundFormState('当前流程版本无定义内容，使用 JSON 方式发起。');
      return;
    }
    const binding = getStartNodeBinding(definitionJson);
    if (!binding) {
      await resetBoundFormState('发起节点未绑定表单，使用 JSON 方式发起。');
      return;
    }
    startBoundFormCode.value = binding.formCode;
    startBoundFormName.value = binding.formName;
    if (binding.formSource === 'ext' && binding.extFormKey) {
      const comp = createExtWorkflowFormComponent(binding.extFormKey);
      if (!comp) {
        await resetBoundFormState(`硬编码表单加载失败：${binding.extFormKey}`);
        return;
      }
      startBoundFormMode.value = 'ext';
      startExtRuntimeRoot.value = comp as any;
      startBindingHint.value = `已加载发起节点硬编码表单：${binding.formName || binding.extFormKey}`;
      await startBoundFormApi.setState(buildStartFormUiState([] as VbenFormSchema[]));
      await startBoundFormApi.setValues({});
      return;
    }
    const formCode = String(binding.formCode || '').trim();
    if (!formCode) {
      await resetBoundFormState('发起节点表单编码为空，使用 JSON 方式发起。');
      return;
    }
    const rec = await getWorkflowFormSchemaByCode(formCode);
    const schemaJson = String(rec?.schemaJson || '').trim();
    if (!schemaJson) {
      await resetBoundFormState(`未找到表单设计器定义：${formCode}`);
      return;
    }
    const parsed = parseStoredFormSchemaJson(schemaJson);
    if (!parsed) {
      await resetBoundFormState(`表单 schema 解析失败：${formCode}`);
      return;
    }
    const normalized = normalizeSchemaForPreview(parsed.srcSchema);
    const decorated = applyFieldRulesToSchemaPlain(normalized, binding.fieldRules || {});
    const startRequiredMainKeys = collectRequiredFieldKeysFromRules(
      (binding.fieldRules || {}) as Record<string, WfNodeFormFieldRule>,
    ).mainKeys;
    startFormSchema.value = applyRequiredMissingStyleToSchema(
      decorated as VbenFormSchema[],
      startRequiredMainKeys,
      [],
    ) as VbenFormSchema[];
    startBoundFormMode.value = 'designer';
    startExtRuntimeRoot.value = null;

    const layoutTabs = !!(parsed.layoutIsTabs && parsed.tabs?.length);
    startLayoutIsTabs.value = layoutTabs;
    startTabsConfig.value = layoutTabs ? (jsonSafeClone(parsed.tabs) as TabTableConfig[]) : [];
    startTabsFieldRulesMap.value = ((binding.fieldRules || {}) as Record<
      string,
      WfNodeFormFieldRule
    >);

    await ensureUserInfoForWorkflowRuntime();
    const seedUser = mergeUserInfoForWorkflow();
    startMetaWorkflowNoPrefix.value =
      String(parsed.workflowNoPrefix || binding.workflowNoPrefix || '').trim() || 'WF';
    const builtins = buildWorkflowBuiltinValuesFromUser(startFormSchema.value as VbenFormSchema[], {
      userInfo: seedUser,
      workflowNoPrefix: startMetaWorkflowNoPrefix.value,
      processTitle: loadedProcessName.value,
    });
    let jsonValues: Record<string, any> = {};
    if (submittedStartMainForm.value && typeof submittedStartMainForm.value === 'object') {
      jsonValues = jsonSafeClone(submittedStartMainForm.value) as Record<string, any>;
    } else {
      try {
        jsonValues = mainFormJson.value.trim()
          ? (JSON.parse(mainFormJson.value) as Record<string, any>)
          : {};
      } catch {
        jsonValues = {};
      }
    }
    const buildOpts = {
      userInfo: seedUser,
      workflowNoPrefix: startMetaWorkflowNoPrefix.value,
      processTitle: loadedProcessName.value,
    };
    const mergedMain = supplementBuiltinValuesByFieldLabel(
      startFormSchema.value as VbenFormSchema[],
      applyProcessTitleBySchemaLabel(
        startFormSchema.value as VbenFormSchema[],
        restoreBuiltinValuesAfterJsonMerge(builtins, { ...builtins, ...jsonValues }, startFormSchema.value as VbenFormSchema[]),
        loadedProcessName.value,
      ),
      seedUser,
      buildOpts,
    );
    startTabsInitialMainValues.value = mergedMain;
    refreshStartFixedMeta({ keepWorkflowNo: false, workflowNoPrefix: startMetaWorkflowNoPrefix.value });
    const mergedMainFlowNo = Object.entries(mergedMain).find(([k, v]) => {
      if (!/flow|no|number|编号/i.test(k)) return false;
      const s = String(v ?? '').trim();
      return /^[A-Za-z]{1,6}\d{6,}$/.test(s);
    })?.[1];
    if (String(mergedMainFlowNo ?? '').trim()) {
      startMetaWorkflowNo.value = String(mergedMainFlowNo ?? '').trim();
    }

    if (layoutTabs) {
      await startBoundFormApi.setState(buildStartFormUiState([] as VbenFormSchema[]));
      await startBoundFormApi.setValues({});
      if (submittedStartTabsData.value && Object.keys(submittedStartTabsData.value).length) {
        await nextTick();
        startTabsTablePreviewRef.value?.loadTabsDataFromObject?.(submittedStartTabsData.value);
      }
      startBindingHint.value = `已按发起节点「上表+页签表格」渲染：${binding.formName || formCode}`;
    } else {
      await startBoundFormApi.setState(buildStartFormUiState(startFormSchema.value as VbenFormSchema[]));
      await nextTick();
      await startBoundFormApi.setValues(mergedMain);
      startBindingHint.value = `已按发起节点绑定表单渲染：${binding.formName || formCode}`;
    }
  } catch (err) {
    await resetBoundFormState(`读取发起节点绑定失败：${(err as Error).message}`);
    pushDebugEvent('读取发起节点绑定', err);
  } finally {
    startBindingLoading.value = false;
  }
}

async function resetTaskBoundFormState(hint: string) {
  taskBindingHint.value = hint;
  taskBoundFormReuseError.value = '';
  taskBoundFormMode.value = 'none';
  taskFormSchema.value = [];
  taskExtRuntimeRoot.value = null;
  taskLayoutIsTabs.value = false;
  taskTabsConfig.value = [];
  taskTabsInitialMainValues.value = {};
  taskTabsFieldRulesMap.value = {};
  taskPendingTabsData.value = {};
  await taskBoundFormApi.setState(buildTaskFormUiState([] as VbenFormSchema[]));
  await taskBoundFormApi.setValues({});
}

function extractFlowNoFromObject(obj: Record<string, any> | null | undefined): string {
  if (!obj || typeof obj !== 'object') return '';
  const entries = Object.entries(obj);
  const strict = entries.find(([k, v]) => {
    if (!/(流程编号|流程\/单号|流程单号|单号|flowNo)/i.test(k)) return false;
    return String(v ?? '').trim() !== '';
  });
  if (strict) return String(strict[1] ?? '').trim();
  const loose = entries.find(([k, v]) => {
    if (!/flow|no|number|编号/i.test(k)) return false;
    return String(v ?? '').trim() !== '';
  });
  return String(loose?.[1] ?? '').trim();
}

const mobileStartHeaderRows = computed(() => [
  { key: 'flowNo', label: '流程编号', value: startMetaDisplayFlowNo.value || '—' },
  { key: 'processName', label: '流程名称', value: loadedProcessName.value || primaryFlowCardTitle.value || '—' },
  { key: 'starter', label: '发起人', value: startMetaStarter.value || '—' },
  { key: 'startTime', label: '发起时间', value: startMetaTime.value || '—' },
  { key: 'employeeNo', label: '工号', value: startMetaDisplayEmployeeNo.value || '—' },
  { key: 'dept', label: '部门', value: startMetaDisplayDept.value || '—' },
  { key: 'position', label: '岗位', value: startMetaDisplayPosition.value || '—' },
  { key: 'status', label: '当前状态', value: '发起中', isStatus: true },
  { key: 'node', label: '当前节点', value: startMetaNodeName.value || '—' },
]);

function parseLatestMainForm(): Record<string, any> {
  return coerceLatestMainForm(instanceDetail.value?.latestData);
}

function parseLatestTabsData(): Record<string, any[]> {
  return coerceLatestTabsData(instanceDetail.value?.latestData);
}

async function ensureRuntimeDefinitionJson() {
  if (runtimeDefinitionJson.value.trim()) return;
  const draft = runtimeDraftDefinitionJson.value.trim();
  if (draft) {
    runtimeDefinitionJson.value = draft;
    return;
  }
  let pid = processDefId.value.trim();
  if (!pid && instanceDetail.value?.instance) {
    const inst = instanceDetail.value.instance as Record<string, unknown>;
    const raw =
      inst.process_def_id ??
      inst.processDefId ??
      (inst as Record<string, unknown>).ProcessDefId;
    pid = String(raw ?? '').trim();
  }
  if (!pid) return;
  try {
    const proc = await withTimeout(wfEngineGetProcess(pid), 25_000, '加载流程定义');
    const dj = String((proc as { version?: { definitionJson?: string } })?.version?.definitionJson ?? '').trim();
    if (dj) runtimeDefinitionJson.value = dj;
    const pn = String(
      (proc as { processDef?: { processName?: string } })?.processDef?.processName ?? '',
    ).trim();
    const pc = String(
      (proc as { processDef?: { processCode?: string } })?.processDef?.processCode ?? '',
    ).trim();
    if (pn && !loadedProcessName.value) loadedProcessName.value = pn;
    if (pc && !loadedProcessCode.value) loadedProcessCode.value = pc;
  } catch (err) {
    pushDebugEvent('加载流程定义(实例)', err);
  }
}

function taskFormHasExclusiveUi() {
  return taskBoundFormMode.value === 'designer' || taskBoundFormMode.value === 'ext';
}

async function loadTaskBoundForm() {
  const instId = inspectInstanceId.value.trim();
  if (!instId) {
    await resetTaskBoundFormState('');
    return;
  }
  const todo = currentPrimaryTodo.value as WfEngineRuntimeTodoItem | undefined;
  const readonlyNodeId = String(resolvedCurrentNodeId.value || '').trim();
  const nodeId = String(todo?.nodeId || readonlyNodeId || '').trim();
  const nodeName =
    String(todo?.nodeName || '').trim() ||
    runtimeNodeList.value.find((x) => x.id === nodeId)?.title ||
    nodeId;
  const isReadonlyPreview = !todo && !!nodeId;
  const isStartNodeReadonlyPreview =
    isReadonlyPreview &&
    !!runtimeStartNodeId.value.trim() &&
    nodeId === runtimeStartNodeId.value.trim();
  if (!nodeId) {
    taskBoundFormMode.value = 'none';
    await resetTaskBoundFormState('暂无待办，仅查看流程信息。');
    return;
  }
  /**
   * 提交后常见场景：当前仍停留在「发起申请」节点，且仅用于只读预览；
   * 直接复用已加载的发起表单结构，避免再次拉取设计器列表导致超时后降级为快照。
   */
  if (isStartNodeReadonlyPreview && startBoundFormMode.value === 'designer' && startFormSchema.value.length) {
    taskBoundFormLoading.value = true;
    taskBoundFormReuseError.value = '';
    try {
      taskBoundFormMode.value = 'designer';
      taskExtRuntimeRoot.value = null;
      const taskRequiredMainKeysFromStart = collectRequiredFieldKeysFromRules(
        jsonSafeClone(startTabsFieldRulesMap.value) as Record<string, WfNodeFormFieldRule>,
      ).mainKeys;
      taskFormSchema.value = applyRequiredMissingStyleToSchema(
        jsonSafeClone(startFormSchema.value) as VbenFormSchema[],
        taskRequiredMainKeysFromStart,
        [],
      ) as VbenFormSchema[];
      taskLayoutIsTabs.value = !!(startLayoutIsTabs.value && startTabsConfig.value.length);
      taskTabsConfig.value = taskLayoutIsTabs.value
        ? (jsonSafeClone(startTabsConfig.value) as TabTableConfig[])
        : [];
      taskTabsFieldRulesMap.value = jsonSafeClone(startTabsFieldRulesMap.value) as Record<
        string,
        WfNodeFormFieldRule
      >;
      const latestMain = parseLatestMainForm();
      const previewMain =
        submittedStartMainForm.value && Object.keys(submittedStartMainForm.value).length
          ? (jsonSafeClone(submittedStartMainForm.value) as Record<string, any>)
          : latestMain;
      taskTabsInitialMainValues.value = latestMain;
      taskTabsInitialMainValues.value = previewMain;
      taskPendingTabsData.value = taskLayoutIsTabs.value
        ? submittedStartTabsData.value && Object.keys(submittedStartTabsData.value).length
          ? (jsonSafeClone(submittedStartTabsData.value) as Record<string, any[]>)
          : parseLatestTabsData()
        : {};
      if (taskLayoutIsTabs.value) {
        taskBoundFormApi.setState(buildTaskFormUiState([] as VbenFormSchema[]));
        taskBoundFormApi.setValues({});
        await nextTick();
        if (Object.keys(taskPendingTabsData.value).length) {
          taskTabsTablePreviewRef.value?.loadTabsDataFromObject?.(taskPendingTabsData.value);
        }
      } else {
        taskBoundFormApi.setState(buildTaskFormUiState(taskFormSchema.value as VbenFormSchema[]));
        await nextTick();
        taskBoundFormApi.setValues(previewMain);
      }
      taskBindingHint.value = '只读预览｜当前节点为发起节点，沿用发起表单展示已提交数据。';
      return;
    } catch (err) {
      taskBoundFormMode.value = 'snapshot';
      taskBoundFormReuseError.value = String((err as Error)?.message || '未知错误');
      taskBindingHint.value = '复用发起表单失败，已降级为快照展示。';
      pushDebugEvent('复用发起节点表单', err);
      return;
    } finally {
      taskBoundFormLoading.value = false;
    }
  }
  taskFormLoadLatestSeq += 1;
  taskBoundFormReuseError.value = '';
  const curLoadSeq = taskFormLoadLatestSeq;
  taskFormLoadInFlight++;
  taskBoundFormLoading.value = true;
  if (taskFormLoadSafetyTimer) clearTimeout(taskFormLoadSafetyTimer);
  taskFormLoadSafetyTimer = setTimeout(() => {
    // 兜底：任何未知挂起都不能让界面一直停在 loading
    if (curLoadSeq === taskFormLoadLatestSeq && taskBoundFormLoading.value) {
      taskBoundFormMode.value = 'snapshot';
      taskBindingHint.value = '加载节点表单超时，已降级为主表快照展示。';
      taskBoundFormLoading.value = false;
      taskFormLoadInFlight = 0;
    }
  }, 65_000);
  try {
    taskExtRuntimeRoot.value = null;
    taskFormSchema.value = [];
    taskLayoutIsTabs.value = false;
    taskTabsConfig.value = [];
    taskTabsFieldRulesMap.value = {};
    taskPendingTabsData.value = {};
    await ensureRuntimeDefinitionJson();
    const defJson = runtimeDefinitionJson.value.trim();
    if (!defJson) {
      taskBoundFormMode.value = 'snapshot';
      await taskBoundFormApi.setState(buildTaskFormUiState([] as VbenFormSchema[]));
      taskBindingHint.value = '未加载到流程定义，已展示主表快照。';
      return;
    }
    const { binding, usedStartFallback, nodeFoundInGraph } = resolveNodeFormBindingWithStartFallback(
      defJson,
      nodeId,
    );
    if (!binding) {
      taskBoundFormMode.value = 'snapshot';
      await taskBoundFormApi.setState(buildTaskFormUiState([] as VbenFormSchema[]));
      const knownIds = runtimeNodeList.value.map((n) => String(n.id || '').trim()).filter(Boolean);
      const inDefinition = knownIds.includes(String(nodeId || '').trim());
      if (!nodeFoundInGraph) {
        taskBindingHint.value = `节点「${nodeName || nodeId}」未绑定表单，已展示主表快照。（nodeId=${nodeId || '—'}；定义中${inDefinition ? '存在该节点' : '找不到该节点'}）`;
      } else {
        taskBindingHint.value = `节点「${nodeName || nodeId}」与发起节点均未绑定表单，已展示主表快照。（nodeId=${nodeId || '—'}）`;
      }
      return;
    }
    if (binding.formSource === 'ext' && binding.extFormKey) {
      const comp = createExtWorkflowFormComponent(binding.extFormKey);
      if (!comp) {
        taskBoundFormMode.value = 'snapshot';
        taskBindingHint.value = `硬编码表单加载失败：${binding.extFormKey}`;
        return;
      }
      taskBoundFormMode.value = 'ext';
      taskExtRuntimeRoot.value = comp as any;
      taskFormSchema.value = [];
      await taskBoundFormApi.setState(buildTaskFormUiState([] as VbenFormSchema[]));
      await taskBoundFormApi.setValues({});
      taskBindingHint.value = `${isReadonlyPreview ? '只读预览｜' : ''}当前节点硬编码表单：${binding.formName || binding.extFormKey}`;
      return;
    }
    const formCode = String(binding.formCode || '').trim();
    if (!formCode) {
      taskBoundFormMode.value = 'snapshot';
      taskBindingHint.value = '节点绑定表单编码为空，已展示主表快照。';
      return;
    }
    /**
     * 提速：若审批节点与发起节点复用同一设计器表单，直接复用已加载的发起 schema，
     * 避免再次请求表单定义列表（该请求在部分环境会非常慢）。
     */
    if (
      startBoundFormMode.value === 'designer' &&
      startFormSchema.value.length > 0 &&
      String(startBoundFormCode.value || '').trim() === formCode
    ) {
      const reused = applyFieldRulesToSchemaPlain(
        jsonSafeClone(startFormSchema.value) as VbenFormSchema[],
        binding.fieldRules || {},
      );
      const taskRequiredMainKeys = collectRequiredFieldKeysFromRules(
        (binding.fieldRules || {}) as Record<string, WfNodeFormFieldRule>,
      ).mainKeys;
      taskFormSchema.value = applyRequiredMissingStyleToSchema(
        reused as VbenFormSchema[],
        taskRequiredMainKeys,
        [],
      ) as VbenFormSchema[];
      taskBoundFormMode.value = 'designer';
      taskExtRuntimeRoot.value = null;
      const layoutTabs = !!(startLayoutIsTabs.value && startTabsConfig.value.length);
      taskLayoutIsTabs.value = layoutTabs;
      taskTabsConfig.value = layoutTabs ? (jsonSafeClone(startTabsConfig.value) as TabTableConfig[]) : [];
      taskTabsFieldRulesMap.value = ((binding.fieldRules || {}) as Record<
        string,
        WfNodeFormFieldRule
      >);
      taskPendingTabsData.value = layoutTabs ? parseLatestTabsData() : {};
      const latest = parseLatestMainForm();
      taskTabsInitialMainValues.value = latest;
      if (layoutTabs) {
        taskBoundFormApi.setState(buildTaskFormUiState([] as VbenFormSchema[]));
        taskBoundFormApi.setValues({});
      } else {
        taskBoundFormApi.setState(buildTaskFormUiState(taskFormSchema.value as VbenFormSchema[]));
        await nextTick();
        taskBoundFormApi.setValues(latest);
      }
      taskBindingHint.value = `${isReadonlyPreview ? '只读预览｜' : ''}当前节点复用发起表单（快速加载）：${
        binding.formName || formCode
      }`;
      return;
    }
    const rec = await withTimeout(
      getWorkflowFormSchemaByCode(formCode),
      45_000,
      '加载表单设计器定义',
    );
    const schemaJson = String(rec?.schemaJson || '').trim();
    if (!schemaJson) {
      taskBoundFormMode.value = 'snapshot';
      taskBindingHint.value = `未找到表单设计器定义：${formCode}`;
      return;
    }
    const parsed = parseStoredFormSchemaJson(schemaJson);
    if (!parsed) {
      taskBoundFormMode.value = 'snapshot';
      taskBindingHint.value = `表单 schema 解析失败：${formCode}`;
      return;
    }
    const normalized = normalizeSchemaForPreview(parsed.srcSchema);
    const decorated = applyFieldRulesToSchemaPlain(normalized, binding.fieldRules || {});
    const taskRequiredMainKeys = collectRequiredFieldKeysFromRules(
      (binding.fieldRules || {}) as Record<string, WfNodeFormFieldRule>,
    ).mainKeys;
    taskFormSchema.value = applyRequiredMissingStyleToSchema(
      decorated as VbenFormSchema[],
      taskRequiredMainKeys,
      [],
    ) as VbenFormSchema[];
    taskBoundFormMode.value = 'designer';

    const layoutTabs = !!(parsed.layoutIsTabs && parsed.tabs?.length);
    taskLayoutIsTabs.value = layoutTabs;
    taskTabsConfig.value = layoutTabs ? (jsonSafeClone(parsed.tabs) as TabTableConfig[]) : [];
    taskTabsFieldRulesMap.value = ((binding.fieldRules || {}) as Record<
      string,
      WfNodeFormFieldRule
    >);
    taskPendingTabsData.value = layoutTabs ? parseLatestTabsData() : {};

    const seedUser = {
      ...(userStore.userInfo || {}),
      realName: mockAssigneeName.value || (userStore.userInfo as any)?.realName,
      name: mockAssigneeName.value || (userStore.userInfo as any)?.name,
      employeeCode: mockAssigneeUserId.value || (userStore.userInfo as any)?.employeeCode,
      employeeNo: mockAssigneeUserId.value || (userStore.userInfo as any)?.employeeNo,
      userCode: mockAssigneeUserId.value || (userStore.userInfo as any)?.userCode,
      username: mockAssigneeUserId.value || (userStore.userInfo as any)?.username,
    } as Record<string, any>;
    const builtins = buildWorkflowBuiltinValuesFromUser(taskFormSchema.value as VbenFormSchema[], {
      userInfo: seedUser,
      workflowNoPrefix: parsed.workflowNoPrefix || binding.workflowNoPrefix,
    });
    const latest = parseLatestMainForm();
    const mergedMain = { ...builtins, ...latest };
    taskTabsInitialMainValues.value = mergedMain;

    if (layoutTabs) {
      /**
       * 上表+页签场景由 FormTabsTablePreview 自身渲染与回填；
       * 不再等待 taskBoundFormApi，避免在某些表单下被无关渲染链路阻塞。
       */
      taskBoundFormApi.setState(buildTaskFormUiState([] as VbenFormSchema[]));
      taskBoundFormApi.setValues({});
    } else {
      await withTimeout(
        (async () => {
          await taskBoundFormApi.setState(buildTaskFormUiState(taskFormSchema.value as VbenFormSchema[]));
          await nextTick();
          await taskBoundFormApi.setValues(mergedMain);
        })(),
        45_000,
        '渲染办理表单',
      );
    }
    taskBindingHint.value = `${isReadonlyPreview ? '只读预览｜' : ''}${
      usedStartFallback ? '本节点未单独绑定表单，已沿用发起节点表单｜' : ''
    }${
      layoutTabs
        ? `当前节点「上表+页签表格」：${binding.formName || formCode}`
        : `当前节点绑定表单：${binding.formName || formCode}`
    }`;
  } catch (err) {
    taskBoundFormMode.value = 'snapshot';
    taskBindingHint.value = `加载节点表单失败：${(err as Error).message}`;
    pushDebugEvent('加载节点办理表单', err);
  } finally {
    taskFormLoadInFlight = Math.max(0, taskFormLoadInFlight - 1);
    if (taskFormLoadInFlight === 0) {
      if (taskFormLoadSafetyTimer) {
        clearTimeout(taskFormLoadSafetyTimer);
        taskFormLoadSafetyTimer = null;
      }
      taskBoundFormLoading.value = false;
      // loading 面板收起后，页签组件才会挂载，此时再回填明细数据
      if (taskLayoutIsTabs.value && taskTabsConfig.value.length && Object.keys(taskPendingTabsData.value).length) {
        await nextTick();
        taskTabsTablePreviewRef.value?.loadTabsDataFromObject?.(taskPendingTabsData.value);
      }
    }
  }
}

const businessDataColumns = [
  { title: '字段', dataIndex: 'field', key: 'field', width: 220 },
  { title: '值', dataIndex: 'value', key: 'value' },
];

const latestDataPretty = computed(() => {
  const x = instanceDetail.value?.latestData;
  if (!x) return '';
  try {
    return JSON.stringify(x, null, 2);
  } catch {
    return String(x);
  }
});

const businessDataRows = computed(() => {
  const raw = instanceDetail.value?.latestData?.main_form_json;
  if (!raw) return [] as Array<{ field: string; value: string }>;
  try {
    const o = JSON.parse(String(raw)) as Record<string, unknown>;
    return Object.entries(o).map(([field, value]) => ({
      field,
      value: typeof value === 'object' ? JSON.stringify(value) : String(value ?? ''),
    }));
  } catch {
    return [];
  }
});

const resolvedCurrentNodeId = computed(() => {
  const tasks = (instanceDetail.value?.tasks as Array<Record<string, any>> | undefined) || [];
  function taskStatusNum(x: any) {
    const raw = x?.status ?? x?.status_num ?? x?.statusNum ?? x?.task_status ?? x?.taskStatus;
    const n = Number(raw);
    return Number.isFinite(n) ? n : -1;
  }
  function taskNodeId(x: any) {
    return String(
      x?.node_id ??
        x?.nodeId ??
        x?.node_id_str ??
        x?.node_code ??
        x?.nodeCode ??
        x?.current_node_id ??
        '',
    ).trim();
  }
  const pending = tasks.find((x) => taskStatusNum(x) === 0);
  if (pending) {
    const nid = taskNodeId(pending);
    if (nid) return nid;
  }
  const latestNodeId = String(
    (instanceDetail.value as any)?.latestData?.node_id ?? (instanceDetail.value as any)?.latestData?.nodeId ?? '',
  ).trim();
  if (latestNodeId) return latestNodeId;
  // 兜底：取最近一条任务的 nodeId（有些接口不返回 pending=0，但会带 tasks 列表）
  const latest = tasks
    .map((x) => ({
      raw: x,
      nodeId: taskNodeId(x),
      at: toTimeMs((x as any)?.received_at ?? (x as any)?.receivedAt ?? (x as any)?.completed_at ?? (x as any)?.completedAt),
    }))
    .filter((x) => !!x.nodeId)
    .sort((a, b) => (Number.isFinite(b.at) ? b.at : 0) - (Number.isFinite(a.at) ? a.at : 0))[0];
  if (latest?.nodeId) return latest.nodeId;
  const raw = instanceDetail.value?.instance?.current_node_ids;
  if (raw) {
    const first = String(raw).split(',')[0].trim();
    if (first) return first;
  }
  const firstTodoNode = String(todoRows.value[0]?.nodeId ?? '').trim();
  return firstTodoNode;
});

const runtimeActiveStepIndex = computed(() => {
  const nodes = parseWorkflowGraphNodes(runtimeDefinitionJson.value);
  if (!nodes.length) return 0;
  if (!inspectInstanceId.value.trim()) return 0;
  const curId = resolvedCurrentNodeId.value;
  if (!curId) return 0;
  const idx = nodes.findIndex((n) => n.id === curId);
  return idx >= 0 ? idx : 0;
});

const runtimeNodeList = computed(() => parseWorkflowGraphNodes(runtimeDefinitionJson.value));

/** 画布「发起/开始」节点 id；用于区分「再次提交」日志（approve 而非 submit） */
const runtimeStartNodeId = computed(() => {
  try {
    const parsed = JSON.parse(runtimeDefinitionJson.value || '{}') as Record<string, any>;
    const nodes = (parsed?.graphData?.nodes ?? []) as any[];
    const arr = Array.isArray(nodes) ? nodes : [];
    const start = arr.find((n) => isLikelyStartNode(n)) ?? arr[0];
    return start ? String(start.id || '').trim() : '';
  } catch {
    return '';
  }
});

const runtimeNodeNameMap = computed(() => {
  const map: Record<string, string> = {};
  const nodes = parseWorkflowGraphNodes(runtimeDefinitionJson.value);
  for (const n of nodes) {
    const id = String(n.id || '').trim();
    const title = String(n.title || '').trim();
    if (id) map[id] = title || id;
  }
  return map;
});

type WfRuntimeReturnEdge = {
  id: string;
  sourceNodeId: string;
  targetNodeId: string;
  priority: number;
  name?: string;
};

function parseReturnEdgesFromDefinition(
  definitionJson: string,
  sourceNodeId: string,
): WfRuntimeReturnEdge[] {
  const sid = String(sourceNodeId || '').trim();
  if (!sid || !definitionJson.trim()) return [];
  try {
    const parsed = JSON.parse(definitionJson) as { graphData?: { edges?: any[] } };
    const edges = parsed?.graphData?.edges ?? [];
    if (!Array.isArray(edges)) return [];
    return edges
      .map((e) => {
        const p = (e?.properties || {}) as Record<string, any>;
        const source = String(e?.sourceNodeId || '').trim();
        const target = String(e?.targetNodeId || '').trim();
        const edgeName = String(p.edgeName || e?.text?.value || e?.text || '').trim();
        const isReturn = !!p.isReturn || /退回|驳回/.test(edgeName);
        if (!isReturn || source !== sid || !target) return null;
        return {
          id: String(e?.id || `${source}->${target}`),
          sourceNodeId: source,
          targetNodeId: target,
          priority: Number(p.priority ?? 0),
          name: edgeName || undefined,
        } as WfRuntimeReturnEdge;
      })
      .filter(Boolean)
      .sort((a, b) => (a as WfRuntimeReturnEdge).priority - (b as WfRuntimeReturnEdge).priority) as WfRuntimeReturnEdge[];
  } catch {
    return [];
  }
}

const currentNodeReturnEdges = computed(() =>
  parseReturnEdgesFromDefinition(runtimeDefinitionJson.value, resolvedCurrentNodeId.value),
);

const canRejectCurrentNode = computed(() => currentNodeReturnEdges.value.length > 0);

const defaultRejectTargetNodeId = computed(
  () => currentNodeReturnEdges.value[0]?.targetNodeId || '',
);

const instanceMetaStatus = computed(() => {
  const st = Number((instanceDetail.value as any)?.instance?.status ?? -1);
  if (st === 2) return { text: '已完成', color: 'success' as const };
  if (st === 3) return { text: '已驳回', color: 'error' as const };
  if (st === 4) return { text: '已撤回', color: 'default' as const };
  return { text: '运行中', color: 'processing' as const };
});

const currentPrimaryTodo = computed(() => {
  const cur = String(resolvedCurrentNodeId.value || '').trim();
  if (cur) {
    const hit = todoRows.value.find((x) => String(x?.nodeId || '').trim() === cur);
    return hit as WfEngineRuntimeTodoItem | undefined;
  }
  return todoRows.value[0] as WfEngineRuntimeTodoItem | undefined;
});

const pageDescription = computed(() => {
  if (inspectInstanceId.value.trim()) return '查看流程信息与进度，办理待办任务。';
  return loadedProcessName.value
    ? `「${loadedProcessName.value}」`
    : '填写申请内容并提交。';
});

const primaryFlowCardTitle = computed(() => {
  if (inspectInstanceId.value.trim()) {
    const n = (instanceDetail.value?.process as { process_name?: string } | undefined)?.process_name;
    return String(n || '').trim() || '流程信息';
  }
  return loadedProcessName.value || '发起申请';
});

const startMetaStarter = computed(() => {
  const u = mergeUserInfoForWorkflow();
  return String(
    u.realName || u.name || u.username || u.employeeCode || u.employeeNo || u.userId || '',
  ).trim();
});
const startMetaDisplayFlowNo = computed(
  () =>
    businessKey.value.trim() ||
    startMetaWorkflowNo.value.trim() ||
    startSubmittedInstanceNo.value.trim() ||
    '—',
);
const startMetaDisplayDept = computed(() => startMetaDept.value.trim() || '—');
const startMetaDisplayPosition = computed(() => startMetaPosition.value.trim() || '—');
const startMetaDisplayEmployeeNo = computed(() => startMetaEmployeeNo.value.trim() || '—');

const startMetaTime = computed(() => new Date().toLocaleString());

const startMetaNodeName = computed(
  () => runtimeNodeNameMap.value[resolvedCurrentNodeId.value] || '发起申请',
);

function pickStringByKeys(
  source: null | Record<string, any> | undefined,
  keys: string[],
): string {
  if (!source) return '';
  for (const k of keys) {
    const v = source[k];
    if (v !== undefined && v !== null && String(v).trim()) {
      return String(v).trim();
    }
  }
  return '';
}

const instanceMainFormObject = computed<Record<string, any>>(() => parseLatestMainForm());

const instanceMetaDisplayFlowNo = computed(
  () =>
    String((instanceDetail.value?.instance as any)?.business_key || '').trim() ||
    String((instanceDetail.value?.instance as any)?.businessKey || '').trim() ||
    businessKey.value.trim() ||
    startSubmittedHeaderFlowNo.value.trim() ||
    extractFlowNoFromObject(submittedStartMainForm.value) ||
    extractFlowNoFromObject(instanceMainFormObject.value) ||
    startSubmittedInstanceNo.value.trim() ||
    String((instanceDetail.value?.instance as any)?.instance_no || '').trim() ||
    '—',
);

const instanceMetaDisplayStarter = computed(() => {
  const inst = (instanceDetail.value?.instance || {}) as Record<string, any>;
  const form = instanceMainFormObject.value || {};
  const fromInstance = pickStringByKeys(inst, [
    'starter_name',
    'starterName',
    'starter_real_name',
    'starterRealName',
  ]);
  const fromForm = pickStringByKeys(form, ['name', 'realName', '姓名', 'applicant', '申请人']);
  const fromCode = pickStringByKeys(inst, ['starter_emp_id', 'starterEmpId', 'starter_user_id']);
  const prefer = fromInstance || fromForm;
  if (prefer) return prefer;
  if (fromCode && !isLikelyGuidStr(fromCode)) return fromCode;
  return '—';
});

const instanceMetaDisplayEmployeeNo = computed(() => {
  const inst = (instanceDetail.value?.instance || {}) as Record<string, any>;
  const form = instanceMainFormObject.value || {};
  const v =
    pickStringByKeys(form, [
      'EMP_ID',
      'employeeNo',
      'employeeCode',
      'empNo',
      'workNo',
      '工号',
    ]) ||
    pickStringByKeys(inst, ['starter_emp_id', 'starterEmpId', 'starter_user_id']);
  if (!v || isLikelyGuidStr(v)) return '—';
  return v;
});

const instanceMetaDisplayDept = computed(() => {
  const form = instanceMainFormObject.value || {};
  return (
    pickStringByKeys(form, [
      'long_name',
      'deptName',
      'departmentName',
      'department',
      'dept',
      '部门',
    ]) || '—'
  );
});

const instanceMetaDisplayPosition = computed(() => {
  const form = instanceMainFormObject.value || {};
  return (
    pickStringByKeys(form, [
      'positionName',
      'dutyName',
      'postName',
      'position',
      'post',
      '岗位',
      '职位',
    ]) || '—'
  );
});

const realLoginSummary = computed(() => {
  const u = userStore.userInfo as Record<string, unknown> | null;
  if (u && (u.userId || u.id || u.realName || u.name || u.username)) {
    const name = String(u.realName ?? u.name ?? '').trim();
    const un = String(u.username ?? '').trim();
    const id = String(u.userId ?? u.id ?? '').trim();
    return [name || '—', un ? `@${un}` : '', id ? `userId ${id}` : ''].filter(Boolean).join(' · ');
  }
  const p = decodeJwtPayload(accessStore.accessToken);
  if (!p) return '（未登录）';
  const uid = String(p.UserId ?? p.userId ?? p.employee_id ?? p.sub ?? '').trim();
  const name = String(
    (p as Record<string, unknown>).name ??
      (p as Record<string, unknown>).unique_name ??
      '',
  ).trim();
  if (uid || name) return `JWT · ${[name, uid].filter(Boolean).join(' · ')}`;
  return '（JWT 中无 UserId，接口仍可能带 token）';
});

function tryParseJsonObject(raw: unknown): Record<string, any> | null {
  if (!raw) return null;
  if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
    return raw as Record<string, any>;
  }
  try {
    const parsed = JSON.parse(String(raw));
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? (parsed as Record<string, any>)
      : null;
  } catch {
    return null;
  }
}

function pickTimelineActionText(row: Record<string, any>): string {
  const action = String(row.action_type || '').trim().toLowerCase();
  const result = String(row.action_result || '').trim().toLowerCase();
  if (action === 'submit' || result === 'submitted') return '提交了申请';
  if (action === 'approve' || action === 'agree' || result === 'agree') return '审批通过';
  if (action === 'reject' || result === 'reject') return '已驳回';
  if (action === 'withdraw') return '撤回了申请';
  if (action === 'transfer') return '转交了任务';
  if (action === 'cc') return '抄送了相关人员';
  if (action === 'read' || action === 'view' || action === 'open') return '查看了流程';
  return row.action_type ? String(row.action_type) : '处理了流程';
}

function hasViewTrace(row: Record<string, any>): boolean | null {
  const action = String(row.action_type || '').trim().toLowerCase();
  if (action === 'read' || action === 'view' || action === 'open') return true;
  const payload = tryParseJsonObject(row.payload_json);
  if (!payload) return null;
  if (typeof payload.hasViewed === 'boolean') return payload.hasViewed;
  if (typeof payload.viewed === 'boolean') return payload.viewed;
  if (payload.viewAt || payload.viewedAt) return true;
  return null;
}

function summarizeSubmission(row: Record<string, any>): string {
  const payload = tryParseJsonObject(row.payload_json);
  if (!payload) return '';
  const mainForm =
    (typeof payload.mainForm === 'object' && payload.mainForm) ||
    (typeof payload.main_form === 'object' && payload.main_form) ||
    null;
  const tabsData =
    (typeof payload.tabsData === 'object' && payload.tabsData) ||
    (typeof payload.tabs_data === 'object' && payload.tabs_data) ||
    null;
  const mainCount = mainForm ? Object.keys(mainForm).length : 0;
  let detailRows = 0;
  if (tabsData && typeof tabsData === 'object') {
    for (const v of Object.values(tabsData)) {
      if (Array.isArray(v)) detailRows += v.length;
    }
  }
  if (!mainCount && !detailRows) return '';
  return `提交信息：主表 ${mainCount} 项，明细 ${detailRows} 行`;
}

function toTimeMs(v: unknown): number {
  if (!v) return Number.NaN;
  const t = new Date(String(v)).getTime();
  return Number.isFinite(t) ? t : Number.NaN;
}

const currentRoundStartMs = computed(() => {
  const rows = (timelineRows.value || []) as Array<Record<string, any>>;
  const startNid = runtimeStartNodeId.value.trim();
  for (let i = rows.length - 1; i >= 0; i--) {
    const r = rows[i] || {};
    const action = String(r.action_type || '').trim().toLowerCase();
    const result = String(r.action_result || '').trim().toLowerCase();
    const nodeId = String(r.node_id || '').trim();
    if (action === 'submit' || result === 'submitted') {
      return toTimeMs(r.action_at);
    }
    /**
     * 驳回后回到发起节点再办理：CompleteTask(action=agree) 记为 approve，不会记 submit。
     * 必须把「发起节点上的同意」视为新一轮起点，否则当前轮时间轴会混入上一轮，流程图会误标退回边。
     */
    if (
      startNid &&
      nodeId === startNid &&
      (action === 'approve' || action === 'agree' || result === 'agree')
    ) {
      return toTimeMs(r.action_at);
    }
  }
  return Number.NaN;
});

const timelineRowsCurrentRound = computed(() => {
  const start = currentRoundStartMs.value;
  const rows = (timelineRows.value || []) as Array<Record<string, any>>;
  if (!Number.isFinite(start)) return rows;
  return rows.filter((r) => {
    const t = toTimeMs(r.action_at);
    return Number.isFinite(t) && t >= start;
  });
});

const timelineViewRows = computed(() => {
  const dm = operatorDisplayMap.value;
  return (timelineRows.value || []).map((row) => {
    const actorRaw = formatOperatorLabel(dm, row.operator_name, row.operator_user_id);
    const actor = actorRaw === '—' ? '系统' : actorRaw;
    const node = String(row.node_id || row.node_name || '当前节点');
    const when = row.action_at ? new Date(row.action_at).toLocaleString() : '—';
    const actionText = pickTimelineActionText(row);
    const viewTrace = hasViewTrace(row);
    const submitSummary = summarizeSubmission(row);
    const nodeName = runtimeNodeNameMap.value[node] || String(row.node_name || '').trim() || node;
    const statusText =
      actionText === '提交了申请'
        ? '已提交'
        : actionText === '审批通过'
          ? '已通过'
          : actionText === '已驳回'
            ? '已驳回'
            : actionText;
    return {
      raw: row,
      actor,
      node,
      nodeName,
      when,
      actionText,
      statusText,
      comment: String(row.comment || '').trim(),
      viewTraceText: viewTrace === null ? '未记录是否查看' : viewTrace ? '已查看' : '未查看',
      submitSummary,
    };
  });
});

const timelineNodeCards = computed(() => {
  const dm = operatorDisplayMap.value;
  const nodes = runtimeNodeList.value;
  const allRows = (timelineRows.value || []) as Array<Record<string, any>>;
  const rows = timelineRowsCurrentRound.value as Array<Record<string, any>>;
  const roundStart = currentRoundStartMs.value;
  const tasks = ((instanceDetail.value?.tasks as Array<Record<string, any>>) || []).map((t) => ({
    ...t,
    nodeId: String(t.node_id ?? t.nodeId ?? '').trim(),
    statusNum: Number(t.status ?? -1),
  })).filter((t) => {
    if (t.statusNum === 0) return true;
    if (!Number.isFinite(roundStart)) return true;
    const received = toTimeMs((t as any).received_at ?? (t as any).receivedAt);
    const completed = toTimeMs((t as any).completed_at ?? (t as any).completedAt);
    return (Number.isFinite(received) && received >= roundStart) || (Number.isFinite(completed) && completed >= roundStart);
  });
  const byNode = new Map<string, Array<Record<string, any>>>();
  const byNodeAll = new Map<string, Array<Record<string, any>>>();
  const tasksByNode = new Map<string, Array<Record<string, any>>>();
  for (const row of allRows) {
    const nodeId = String(row.node_id || row.node_name || '').trim();
    if (!nodeId) continue;
    const list = byNodeAll.get(nodeId) || [];
    list.push(row);
    byNodeAll.set(nodeId, list);
  }
  for (const row of rows) {
    const nodeId = String(row.node_id || row.node_name || '').trim();
    if (!nodeId) continue;
    const list = byNode.get(nodeId) || [];
    list.push(row);
    byNode.set(nodeId, list);
  }
  for (const t of tasks) {
    if (!t.nodeId) continue;
    const list = tasksByNode.get(t.nodeId) || [];
    list.push(t);
    tasksByNode.set(t.nodeId, list);
  }

  const statusFromRow = (row: Record<string, any> | undefined) => {
    if (!row) return '待处理';
    const text = pickTimelineActionText(row);
    if (text === '提交了申请') return '已提交';
    if (text === '审批通过') return '已通过';
    if (text === '已驳回') return '已驳回';
    if (text === '撤回了申请') return '已撤回';
    return text || '已处理';
  };

  return nodes.map((n) => {
    const nodeRowsAll = byNodeAll.get(n.id) || [];
    const nodeRows = byNode.get(n.id) || [];
    const nodeTasks = tasksByNode.get(n.id) || [];
    const latest = nodeRows.length ? nodeRows[nodeRows.length - 1] : undefined;
    const viewed = nodeRows.some((r) => hasViewTrace(r) === true);
    const latestDecision =
      [...nodeRows]
        .reverse()
        .find((r) => ['submit', 'approve', 'agree', 'reject', 'withdraw'].includes(String(r.action_type || '').toLowerCase())) ||
      latest;

    const pendingTask = nodeTasks.find((t) => t.statusNum === 0);
    const passedTask = nodeTasks.find((t) => t.statusNum === 2);
    const rejectedTask = nodeTasks.find((t) => t.statusNum === 3);
    const canceledTask = nodeTasks.find((t) => t.statusNum === 4);
    const reached = nodeRows.length > 0 || nodeTasks.length > 0;

    let statusText = '待处理';
    if (rejectedTask) {
      statusText = '已驳回';
    } else if (pendingTask) {
      statusText = viewed ? '已查看' : '进行中';
    } else if (passedTask) {
      const fromLog = statusFromRow(latestDecision);
      statusText = fromLog === '待处理' || fromLog === '已处理' ? '已完成' : fromLog;
    } else if (canceledTask) {
      statusText = '已取消';
    } else if (reached) {
      const fromLog = statusFromRow(latestDecision);
      statusText = fromLog === '待处理' ? '已完成' : fromLog;
    }

    const whenRaw =
      latest?.action_at ?? pendingTask?.received_at ?? pendingTask?.receivedAt ?? passedTask?.completed_at ?? passedTask?.completedAt;
    const when = whenRaw ? new Date(whenRaw).toLocaleString() : '—';
    const actor = resolveActorFromLatestAndPending(dm, latest as any, pendingTask as any);
    const comment = String(latestDecision?.comment || '').trim();
    const rejectRowsAll = nodeRowsAll.filter((r) => {
      const a = String(r.action_type || '').trim().toLowerCase();
      const res = String(r.action_result || '').trim().toLowerCase();
      return a === 'reject' || res === 'reject';
    });
    const latestReject = rejectRowsAll.length ? rejectRowsAll[rejectRowsAll.length - 1] : undefined;
    const latestRejectWhen = latestReject?.action_at
      ? new Date(latestReject.action_at).toLocaleString()
      : '';
    const latestRejectActorRaw = formatOperatorLabel(
      dm,
      latestReject?.operator_name,
      latestReject?.operator_user_id,
    );
    const latestRejectActor = latestRejectActorRaw === '—' ? '' : latestRejectActorRaw;
    const latestRejectComment = String(latestReject?.comment || '').trim();
    const historyRejectText = latestReject
      ? `历史驳回 ${rejectRowsAll.length} 次（最近：${latestRejectWhen || '—'}${latestRejectActor ? `，${latestRejectActor}` : ''}${latestRejectComment ? `，意见：${latestRejectComment}` : ''}）`
      : '';

    return {
      nodeId: n.id,
      nodeName: n.title || n.id,
      reached,
      when,
      actor,
      statusText,
      statusColor:
        statusText === '已驳回'
          ? 'error'
          : statusText === '已通过' || statusText === '已完成' || statusText === '已提交'
            ? 'success'
            : statusText === '待处理'
              ? 'default'
              : 'processing',
      viewTraceText: viewed ? '已查看' : reached ? '未记录是否查看' : '未到达',
      comment,
      historyRejectText,
    };
  });
});

watch(
  mockAssigneeUserId,
  (v) => {
    setWorkflowRuntimeMockAssigneeUserId(v);
  },
  { immediate: true },
);

function clearMockAssignee() {
  mockAssigneeUserId.value = '';
  mockAssigneeName.value = '';
}

async function clearInstanceForNewRun() {
  runtimePerfLogs.value = [];
  inspectInstanceId.value = '';
  instanceDetail.value = null;
  timelineRows.value = [];
  todoRows.value = [];
  todoTotal.value = 0;
  lastStartResp.value = null;
  startSubmittedInstanceNo.value = '';
  startSubmittedHeaderFlowNo.value = '';
  submittedStartMainForm.value = null;
  submittedStartTabsData.value = null;
  await resetTaskBoundFormState('');
}

interface RuntimeStartDraftPayload {
  processCode?: string;
  processDefId?: string;
  businessKey?: string;
  title?: string;
  starterDeptId?: string;
  mockStarterUserId?: string;
  mockStarterName?: string;
  mainForm?: Record<string, unknown>;
  tabsData?: Record<string, unknown>;
}

function buildRuntimeDraftStorageKey() {
  const pid = processDefId.value.trim();
  const pcode = processCode.value.trim();
  const identity = pid || pcode || 'default';
  return `wf-runtime-start-draft:${identity}`;
}

function isEmptyRequiredValue(v: unknown): boolean {
  if (v === null || v === undefined) return true;
  if (typeof v === 'string') return v.trim().length === 0;
  if (Array.isArray(v)) return v.length === 0;
  return false;
}

function collectRequiredFieldKeysFromRules(
  rules: Record<string, WfNodeFormFieldRule> | undefined,
): { mainKeys: string[]; tabKeys: string[] } {
  const mainKeys: string[] = [];
  const tabKeys: string[] = [];
  for (const [k, rawRule] of Object.entries(rules || {})) {
    if (normalizeFieldRule(rawRule) !== 'required') continue;
    if (k.includes('::')) tabKeys.push(k);
    else mainKeys.push(k);
  }
  return { mainKeys, tabKeys };
}

function buildMainFieldLabelMap(schema: VbenFormSchema[]): Record<string, string> {
  const map: Record<string, string> = {};
  for (const item of schema || []) {
    const key = String(item?.fieldName || '').trim();
    if (!key) continue;
    const label = String((item as any)?.label || (item as any)?.fieldLabel || '').trim();
    map[key] = label || key;
  }
  return map;
}

function quoteCnList(values: string[]): string {
  return values.map((x) => `【${x}】`).join('、');
}

function validateRequiredByFieldRules(
  fieldRules: Record<string, WfNodeFormFieldRule> | undefined,
  mainForm: Record<string, unknown> | undefined,
  tabsData?: Record<string, unknown>,
  mainFieldLabelMap?: Record<string, string>,
): { message?: string; missingMainKeys?: string[]; valid: boolean } {
  const main = (mainForm || {}) as Record<string, unknown>;
  const tabs = (tabsData || {}) as Record<string, unknown>;
  const { mainKeys, tabKeys } = collectRequiredFieldKeysFromRules(fieldRules);
  const missingMain = mainKeys.filter((k) => isEmptyRequiredValue(main[k]));
  if (missingMain.length) {
    const names = missingMain.map((k) => String(mainFieldLabelMap?.[k] || k).trim() || k);
    return {
      valid: false,
      message: `以下字段未填写：${quoteCnList(names)}`,
      missingMainKeys: missingMain,
    };
  }
  for (const tk of tabKeys) {
    const idx = tk.indexOf('::');
    if (idx <= 0) continue;
    const tabKey = tk.slice(0, idx).trim();
    const colKey = tk.slice(idx + 2).trim();
    if (!tabKey || !colKey) continue;
    const rows = Array.isArray(tabs[tabKey]) ? (tabs[tabKey] as Array<Record<string, unknown>>) : [];
    if (!rows.length) {
      return {
        valid: false,
        message: `页签必填字段未填写：${tabKey} -> ${colKey}（无明细行）`,
      };
    }
    const missRow = rows.findIndex((r) => isEmptyRequiredValue((r || {})[colKey]));
    if (missRow >= 0) {
      return {
        valid: false,
        message: `页签必填字段未填写：${tabKey} 第 ${missRow + 1} 行 -> ${colKey}`,
      };
    }
  }
  return { valid: true };
}

async function collectStartRuntimePayload(opts?: { validate?: boolean }) {
  const validate = opts?.validate !== false;
  let mainForm: Record<string, unknown> = {};
  let tabsData: Record<string, unknown> | undefined;
  if (
    startBoundFormMode.value === 'designer' &&
    startLayoutIsTabs.value &&
    startTabsConfig.value.length > 0
  ) {
    const prev = startTabsTablePreviewRef.value as null | {
      validateAllTabs?: () => { valid: boolean; message?: string } | Promise<{ valid: boolean; message?: string }>;
      getWorkflowRuntimePayload?: () => Promise<{
        mainForm: Record<string, unknown>;
        tabsData: Record<string, unknown[]>;
      }>;
    };
    if (validate && prev?.validateAllTabs) {
      const v = await prev.validateAllTabs();
      if (v && v.valid === false) {
        message.error(v.message || '页签表格校验未通过');
        return null;
      }
    }
    if (prev?.getWorkflowRuntimePayload) {
      const payload = await prev.getWorkflowRuntimePayload();
      mainForm = (payload.mainForm || {}) as Record<string, unknown>;
      tabsData = payload.tabsData as Record<string, unknown>;
    }
  } else if (startBoundFormMode.value === 'designer' && startFormSchema.value.length > 0) {
    mainForm = ((await startBoundFormApi.getValues()) || {}) as Record<string, unknown>;
  } else {
    try {
      mainForm = mainFormJson.value.trim()
        ? (JSON.parse(mainFormJson.value) as Record<string, unknown>)
        : {};
    } catch {
      message.error('主表单 JSON 格式不正确');
      return null;
    }
  }
  if (validate) {
    const v = validateRequiredByFieldRules(
      startTabsFieldRulesMap.value,
      mainForm,
      tabsData as Record<string, unknown> | undefined,
      buildMainFieldLabelMap(startFormSchema.value as VbenFormSchema[]),
    );
    if (!v.valid) {
      await applyStartRequiredVisual(v.missingMainKeys || []);
      message.error(v.message || '存在未填写的必填字段');
      return null;
    }
    await applyStartRequiredVisual([]);
  }
  return {
    processCode: processCode.value.trim() || undefined,
    processDefId: processDefId.value.trim() || undefined,
    businessKey: businessKey.value.trim() || undefined,
    title: title.value.trim() || undefined,
    starterDeptId: starterDeptId.value.trim() || undefined,
    mockStarterUserId: mockStarterUserId.value.trim() || undefined,
    mockStarterName: mockStarterName.value.trim() || undefined,
    mainForm,
    tabsData,
  } as RuntimeStartDraftPayload;
}

async function saveStartDraft() {
  saveDraftLoading.value = true;
  try {
    const payload = await collectStartRuntimePayload({ validate: true });
    if (!payload) return;
    const key = buildRuntimeDraftStorageKey();
    localStorage.setItem(
      key,
      JSON.stringify({
        savedAt: new Date().toISOString(),
        payload,
      }),
    );
    message.success('已保存草稿');
  } catch (err) {
    pushDebugEvent('保存草稿', err);
    message.error('保存草稿失败');
  } finally {
    saveDraftLoading.value = false;
  }
}

async function restoreStartDraft() {
  const key = buildRuntimeDraftStorageKey();
  const raw = localStorage.getItem(key);
  if (!raw) return;
  try {
    const parsed = JSON.parse(raw) as {
      payload?: RuntimeStartDraftPayload;
    };
    const payload = parsed?.payload;
    if (!payload) return;
    businessKey.value = String(payload.businessKey || '').trim();
    title.value = String(payload.title || '').trim();
    starterDeptId.value = String(payload.starterDeptId || '').trim();
    if (!processCode.value.trim() && payload.processCode) {
      processCode.value = String(payload.processCode || '').trim();
    }
    if (!processDefId.value.trim() && payload.processDefId) {
      processDefId.value = String(payload.processDefId || '').trim();
    }
    if (payload.mockStarterUserId) {
      mockStarterUserId.value = String(payload.mockStarterUserId || '').trim();
    }
    if (payload.mockStarterName) {
      mockStarterName.value = String(payload.mockStarterName || '').trim();
    }
    if (payload.mainForm && typeof payload.mainForm === 'object') {
      submittedStartMainForm.value = jsonSafeClone(payload.mainForm as Record<string, any>) as Record<
        string,
        any
      >;
      mainFormJson.value = JSON.stringify(payload.mainForm, null, 2);
    }
    if (payload.tabsData && typeof payload.tabsData === 'object') {
      submittedStartTabsData.value = jsonSafeClone(payload.tabsData as Record<string, any[]>) as Record<
        string,
        any[]
      >;
    }
    await loadStartBoundForm();
    message.success('已恢复草稿');
  } catch (err) {
    pushDebugEvent('恢复草稿', err);
  }
}

/** 若当前实例仅剩一条待办，则自动把模拟办理人切换为该待办人，便于 A→B 连测 */
async function trySyncMockAssigneeFromInstance(instId: string) {
  const id = instId.trim();
  if (!id) return;
  try {
    const data = await wfEngineRuntimeInstanceDetail(id);
    const tasks = (data as any)?.tasks ?? [];
    const pending = tasks.filter((t: any) => Number(t.status ?? 0) === 0);
    if (pending.length !== 1) return;
    const t = pending[0];
    const uid = String(t.assigneeUserId ?? t.assignee_user_id ?? '').trim();
    const uname = String(t.assigneeName ?? t.assignee_name ?? '').trim();
    if (!uid) return;
    const changed =
      uid !== mockAssigneeUserId.value.trim() || uname !== mockAssigneeName.value.trim();
    mockAssigneeUserId.value = uid;
    mockAssigneeName.value = uname;
    if (changed) {
      message.success(`已切换模拟办理人为：${uname ? `${uname}（${uid}）` : uid}`);
    }
  } catch {
    /* ignore */
  }
}

async function startRuntime() {
  startLoading.value = true;
  try {
    runtimePerfLogs.value = [];
    if (!businessKey.value.trim()) {
      businessKey.value = String(startMetaWorkflowNo.value || '').trim();
    }
    startSubmittedHeaderFlowNo.value = String(startMetaDisplayFlowNo.value || '').trim();
    const payload = await collectStartRuntimePayload({ validate: true });
    if (!payload) return;
    const mainForm = (payload.mainForm || {}) as Record<string, unknown>;
    const tabsData = payload.tabsData as Record<string, unknown> | undefined;
    submittedStartMainForm.value = jsonSafeClone(mainForm as Record<string, any>) as Record<string, any>;
    submittedStartTabsData.value = tabsData
      ? (jsonSafeClone(tabsData as Record<string, any[]>) as Record<string, any[]>)
      : null;
    mainFormJson.value = JSON.stringify(submittedStartMainForm.value, null, 2);
    if (startBoundFormMode.value === 'designer') {
      if (startLayoutIsTabs.value && startTabsConfig.value.length) {
        startTabsInitialMainValues.value = jsonSafeClone(
          submittedStartMainForm.value as Record<string, any>,
        ) as Record<string, any>;
      } else {
        await startBoundFormApi.setValues(submittedStartMainForm.value as Record<string, any>);
      }
    }

    const requestPayload = payload;
    const resp = await wfEngineRuntimeStart(requestPayload);
    lastStartResp.value = resp as unknown as Record<string, unknown>;
    startSubmittedInstanceNo.value = String((resp as any)?.instanceNo || '').trim();
    const instId = String((resp as any)?.instanceId || '').trim();
    let autoOpenedApproval = false;
    if (instId) {
      inspectInstanceId.value = instId;
      await trySyncMockAssigneeFromInstance(instId);
      await Promise.all([loadTodos(), loadInstanceDetail(), loadTimeline()]);
      await profiled('loadTaskBoundForm', () => loadTaskBoundForm());
      /** 无节点专属表单时：仅一条待办则打开意见弹窗（旧测试闭环） */
      if (todoRows.value.length === 1 && !taskFormHasExclusiveUi() && currentPrimaryTodo.value) {
        await nextTick();
        openAction(currentPrimaryTodo.value as WfEngineRuntimeTodoItem, 'agree');
        autoOpenedApproval = true;
      }
    }
    message.success(
      autoOpenedApproval
        ? '已发起流程，已切换为下一审批人并打开办理'
        : taskFormHasExclusiveUi()
          ? '已发起流程，已进入下一节点绑定表单'
          : '已发起流程',
    );
  } catch (err) {
    pushDebugEvent('发起流程', err);
    const first = debugEvents.value[0];
    if (first) {
      first.requestPayload = {
        processCode: processCode.value.trim() || undefined,
        processDefId: processDefId.value.trim() || undefined,
        businessKey: businessKey.value.trim() || undefined,
        title: title.value.trim() || undefined,
        starterDeptId: starterDeptId.value.trim() || undefined,
        mockStarterUserId: mockStarterUserId.value.trim() || undefined,
        mockStarterName: mockStarterName.value.trim() || undefined,
        mainFormPreview: mainFormJson.value,
      };
    }
  } finally {
    startLoading.value = false;
  }
}

async function loadTodos() {
  todoLoading.value = true;
  try {
    const data = await profiled('loadTodos', () =>
      wfEngineRuntimeTodo({
        page: todoPage.value,
        pageSize: todoPageSize.value,
      }),
    );
    todoRows.value = data.items || [];
    todoTotal.value = Number(data.total || 0);
  } catch (err) {
    pushDebugEvent('加载待办', err);
  } finally {
    todoLoading.value = false;
  }
}

function openAction(row: WfEngineRuntimeTodoItem, type: 'agree' | 'reject') {
  if (type === 'reject' && !canRejectCurrentNode.value) {
    message.warning('当前节点未配置退回出口，不支持驳回');
    return;
  }
  actionRow.value = row;
  actionType.value = type;
  actionComment.value = '';
  actionRejectToNodeId.value = type === 'reject' ? defaultRejectTargetNodeId.value : '';
  actionModalOpen.value = true;
}

async function submitAction() {
  if (!actionRow.value) return;
  todoActionLoading.value = actionRow.value.taskId;
  try {
    let mainForm: Record<string, unknown> | undefined;
    let tabsData: Record<string, unknown> | undefined;
    if (
      taskBoundFormMode.value === 'designer' &&
      taskLayoutIsTabs.value &&
      taskTabsConfig.value.length > 0
    ) {
      const prev = taskTabsTablePreviewRef.value as null | {
        validateAllTabs?: () => { valid: boolean; message?: string } | Promise<{ valid: boolean; message?: string }>;
        getWorkflowRuntimePayload?: () => Promise<{
          mainForm: Record<string, unknown>;
          tabsData: Record<string, unknown[]>;
        }>;
      };
      if (prev?.validateAllTabs) {
        const v = await prev.validateAllTabs();
        if (v && v.valid === false) {
          message.error(v.message || '页签表格校验未通过');
          return;
        }
      }
      if (prev?.getWorkflowRuntimePayload) {
        const payload = await prev.getWorkflowRuntimePayload();
        mainForm = (payload.mainForm || {}) as Record<string, unknown>;
        tabsData = payload.tabsData as Record<string, unknown>;
      }
    } else if (taskBoundFormMode.value === 'designer' && taskFormSchema.value.length > 0) {
      mainForm = ((await taskBoundFormApi.getValues()) || {}) as Record<string, unknown>;
    }
    if (taskBoundFormMode.value === 'designer') {
      const rv = validateRequiredByFieldRules(
        taskTabsFieldRulesMap.value,
        mainForm,
        tabsData as Record<string, unknown> | undefined,
        buildMainFieldLabelMap(taskFormSchema.value as VbenFormSchema[]),
      );
      if (!rv.valid) {
        await applyTaskRequiredVisual(rv.missingMainKeys || []);
        message.error(rv.message || '存在未填写的必填字段');
        return;
      }
      await applyTaskRequiredVisual([]);
    }
    const resp = await wfEngineRuntimeCompleteTask({
      taskId: actionRow.value.taskId,
      action: actionType.value,
      comment: actionComment.value.trim() || undefined,
      rejectToNodeId:
        actionType.value === 'reject'
          ? actionRejectToNodeId.value.trim() || undefined
          : undefined,
      mainForm,
      tabsData,
    });
    actionModalOpen.value = false;
    message.success(actionType.value === 'agree' ? '已同意' : '已驳回');
    const instId = String((resp as any)?.instanceId || '').trim();
    if (instId) inspectInstanceId.value = instId;
    await loadTodos();
    if (inspectInstanceId.value) {
      await trySyncMockAssigneeFromInstance(inspectInstanceId.value);
      await loadTodos();
      await loadInstanceDetail();
      await loadTimeline();
      await profiled('loadTaskBoundForm', () => loadTaskBoundForm());
    }
    if (todoRows.value.length === 1 && !taskFormHasExclusiveUi() && currentPrimaryTodo.value) {
      await nextTick();
      openAction(currentPrimaryTodo.value as WfEngineRuntimeTodoItem, 'agree');
    }
  } catch (err) {
    pushDebugEvent(actionType.value === 'agree' ? '同意办理' : '驳回办理', err);
  } finally {
    todoActionLoading.value = '';
  }
}

async function loadInstanceDetail() {
  const id = inspectInstanceId.value.trim();
  if (!id) {
    message.warning('请先填写实例ID');
    return;
  }
  detailLoading.value = true;
  try {
    const data = await profiled('loadInstanceDetail', () => wfEngineRuntimeInstanceDetail(id));
    instanceDetail.value = data as unknown as Record<string, any>;
    if ((timelineRows.value || []).length) {
      try {
        await refreshOperatorDisplayCache();
      } catch {
        /* ignore */
      }
    }
  } catch (err) {
    pushDebugEvent('加载实例详情', err);
  } finally {
    detailLoading.value = false;
  }
}

async function loadTimeline() {
  const id = inspectInstanceId.value.trim();
  if (!id) {
    message.warning('请先填写实例ID');
    return;
  }
  timelineLoading.value = true;
  try {
    timelineRows.value = (await profiled('loadTimeline', () =>
      wfEngineRuntimeInstanceTimeline(id),
    )) as Array<Record<string, any>>;
    try {
      await refreshOperatorDisplayCache();
    } catch {
      /* ignore */
    }
  } catch (err) {
    pushDebugEvent('加载实例轨迹', err);
  } finally {
    timelineLoading.value = false;
  }
}

let hydrateFromRouteSeq = 0;
async function hydrateFromRoute() {
  hydrateFromRouteSeq += 1;
  const curSeq = hydrateFromRouteSeq;

  processCode.value = String(route.query.processCode || '').trim();
  processDefId.value = String(route.query.processDefId || '').trim();
  const qProcessName = String(route.query.processName || '').trim();
  if (qProcessName) loadedProcessName.value = qProcessName;
  runtimeDraftKey.value = String(route.query.runtimeDraftKey || '').trim();
  applyRuntimeDraftByKey(runtimeDraftKey.value);
  inspectInstanceId.value = String(route.query.instanceId || '').trim();
  mockStarterUserId.value = String(route.query.mockStarterUserId || '').trim();
  mockStarterName.value = String(route.query.mockStarterName || '').trim();
  mockStarterDeptName.value = String(route.query.mockStarterDeptName || '').trim();
  mockStarterPositionName.value = String(route.query.mockStarterPositionName || '').trim();

  // 若带了草稿定义，则统一用草稿定义渲染运行台（不区分发起/实例查看）
  if (runtimeDraftDefinitionJson.value.trim()) {
    runtimeDefinitionJson.value = runtimeDraftDefinitionJson.value.trim();
  }

  // 只在“发起流程”模式下加载发起节点绑定表单；查看实例时不要干扰界面
  if (!inspectInstanceId.value.trim()) {
    submittedStartMainForm.value = null;
    submittedStartTabsData.value = null;
    await loadStartBoundForm();
  }

  await loadTodos();
  if (curSeq !== hydrateFromRouteSeq) return;

  if (inspectInstanceId.value.trim()) {
    await loadInstanceDetail();
    if (curSeq !== hydrateFromRouteSeq) return;
    await loadTimeline();
    if (curSeq !== hydrateFromRouteSeq) return;
    await profiled('loadTaskBoundForm', () => loadTaskBoundForm());
  }
}

watch(
  () => route.fullPath,
  async () => {
    await hydrateFromRoute();
  },
  { immediate: true },
);

watch(
  showDebugPanel,
  (v) => {
    try {
      if (typeof localStorage === 'undefined') return;
      localStorage.setItem(DEBUG_PANEL_OPEN_KEY, v ? '1' : '0');
    } catch {
      // ignore
    }
  },
  { immediate: true },
);

async function refreshTodosAndTaskForm() {
  await loadTodos();
  await profiled('loadTaskBoundForm', () => loadTaskBoundForm());
}

watch(
  () =>
    [
      processDefId.value,
      runtimeDraftDefinitionJson.value,
      mockStarterUserId.value,
      mockStarterName.value,
      mockStarterDeptName.value,
      mockStarterPositionName.value,
    ] as const,
  async () => {
    refreshStartFixedMeta({ keepWorkflowNo: true });
    await loadStartBoundForm();
  },
);

/** 新开页时 userInfo / token 可能晚于首次 loadStartBoundForm，需回填内置字段 */
watch(
  () => [userStore.userInfo, accessStore.accessToken] as const,
  async () => {
    refreshStartFixedMeta({ keepWorkflowNo: true });
    if (inspectInstanceId.value.trim()) return;
    if (!processDefId.value.trim() && !runtimeDraftDefinitionJson.value.trim()) return;
    await loadStartBoundForm();
  },
  { deep: true },
);

watch(
  () => [processCode.value, processDefId.value, runtimeDraftDefinitionJson.value] as const,
  () => {
    startSubmittedHeaderFlowNo.value = '';
    submittedStartMainForm.value = null;
    submittedStartTabsData.value = null;
    refreshStartFixedMeta({ keepWorkflowNo: false });
  },
  { immediate: true },
);

watch(
  isMobilePreviewMode,
  async () => {
    await startBoundFormApi.setState(buildStartFormUiState(startFormSchema.value as VbenFormSchema[]));
    await taskBoundFormApi.setState(buildTaskFormUiState(taskFormSchema.value as VbenFormSchema[]));
  },
  { immediate: true },
);
</script>

<template>
  <Page title="发起流程" :description="pageDescription" content-class="min-h-0">
    <ProcessPreviewShell :frame="isMobilePreviewMode">
      <div class="flex flex-col gap-4" :class="isMobilePreviewMode ? 'wf-mobile-single gap-3' : ''">
        <Card size="small" :title="primaryFlowCardTitle">
          <template v-if="!inspectInstanceId.trim()" #extra>
            <Space>
              <Button @click="restoreStartDraft">恢复草稿</Button>
              <Button :loading="saveDraftLoading" @click="saveStartDraft">保存</Button>
              <Button type="primary" :loading="startLoading" @click="startRuntime">
                提交
              </Button>
            </Space>
          </template>
          <template v-if="!inspectInstanceId.trim()">
            <div
              v-if="isMobilePreviewMode"
              class="mb-3 divide-border/55 flex flex-col divide-y text-sm"
            >
              <div
                v-for="r in mobileStartHeaderRows"
                :key="r.key"
                class="flex flex-col gap-1 py-3 first:pt-1 last:pb-1"
              >
                <span class="text-muted-foreground text-[11px] leading-tight">{{ r.label }}</span>
                <Tag v-if="r.isStatus" color="processing" class="w-fit">
                  {{ r.value }}
                </Tag>
                <div v-else class="break-words text-[13px] leading-snug">{{ r.value }}</div>
              </div>
            </div>
            <div v-else class="mb-3 grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
              <div>
                <span class="text-muted-foreground">流程编号：</span>
                {{ startMetaDisplayFlowNo }}
              </div>
              <div>
                <span class="text-muted-foreground">流程名称：</span>
                {{ loadedProcessName || primaryFlowCardTitle || '—' }}
              </div>
              <div>
                <span class="text-muted-foreground">发起人：</span>
                {{ startMetaStarter || '—' }}
              </div>
              <div>
                <span class="text-muted-foreground">发起时间：</span>
                {{ startMetaTime }}
              </div>
              <div>
                <span class="text-muted-foreground">工号：</span>
                {{ startMetaDisplayEmployeeNo }}
              </div>
              <div>
                <span class="text-muted-foreground">部门：</span>
                {{ startMetaDisplayDept }}
              </div>
              <div>
                <span class="text-muted-foreground">岗位：</span>
                {{ startMetaDisplayPosition }}
              </div>
              <div class="md:col-span-2">
                <span class="text-muted-foreground">当前状态：</span>
                <Tag color="processing">发起中</Tag>
              </div>
              <div class="md:col-span-2">
                <span class="text-muted-foreground">当前节点：</span>
                {{ startMetaNodeName }}
              </div>
            </div>
            <div class="border-border border-t pt-1">
              <div class="wf-viewer-form-tight">
                <div
                  v-if="
                    startBoundFormMode === 'designer' &&
                    startFormSchema.length > 0 &&
                    startLayoutIsTabs &&
                    startTabsConfig.length
                  "
                >
                  <FormTabsTablePreview
                    ref="startTabsTablePreviewRef"
                    :form-schema="(startFormSchema as any)"
                    :tabs="startTabsConfig"
                    :field-rules-map="startTabsFieldRulesMap"
                    :show-form="true"
                    :grid-height="120"
                    :compact="true"
                    :hide-single-tab-nav="false"
                    :wrapper-class="
                      isMobilePreviewMode
                        ? 'wf-mobile-form-single grid-cols-1 gap-y-2'
                        : 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]'
                    "
                    :layout="isMobilePreviewMode ? 'vertical' : 'horizontal'"
                    :label-width="isMobilePreviewMode ? 88 : 110"
                    :initial-main-form-values="startTabsInitialMainValues"
                  />
                </div>
                <div v-else-if="startBoundFormMode === 'designer' && startFormSchema.length > 0">
                  <StartBoundForm />
                </div>
                <div v-else-if="startBoundFormMode === 'ext'">
                  <component v-if="startExtRuntimeRoot" :is="startExtRuntimeRoot" />
                  <div v-else class="text-muted-foreground py-2 text-center text-sm">表单加载中…</div>
                </div>
                <div v-else class="text-muted-foreground py-2 text-sm leading-relaxed">
                  当前流程未配置可视化发起表单。请联系管理员配置发起节点绑定，或在下方「调试」面板使用 JSON 发起。
                </div>
              </div>
            </div>
          </template>

          <template v-else>
            <div class="mb-4 grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
              <div>
                <span class="text-muted-foreground">流程编号：</span>
                {{ instanceMetaDisplayFlowNo }}
              </div>
              <div>
                <span class="text-muted-foreground">流程名称：</span>
                {{ instanceDetail?.process?.process_name || '—' }}
              </div>
              <div>
                <span class="text-muted-foreground">发起人：</span>
                {{ instanceMetaDisplayStarter }}
              </div>
              <div>
                <span class="text-muted-foreground">发起时间：</span>
                {{
                  (instanceDetail?.instance as any)?.started_at ||
                  (instanceDetail?.instance as any)?.startedAt
                    ? new Date(
                        (instanceDetail?.instance as any).started_at ||
                          (instanceDetail?.instance as any).startedAt,
                      ).toLocaleString()
                    : '—'
                }}
              </div>
              <div>
                <span class="text-muted-foreground">工号：</span>
                {{ instanceMetaDisplayEmployeeNo }}
              </div>
              <div>
                <span class="text-muted-foreground">部门：</span>
                {{ instanceMetaDisplayDept }}
              </div>
              <div>
                <span class="text-muted-foreground">岗位：</span>
                {{ instanceMetaDisplayPosition }}
              </div>
              <div class="md:col-span-2">
                <span class="text-muted-foreground">当前状态：</span>
                <Tag :color="instanceMetaStatus.color">{{ instanceMetaStatus.text }}</Tag>
              </div>
              <div class="md:col-span-2">
                <span class="text-muted-foreground">当前节点：</span>
                {{ runtimeNodeNameMap[resolvedCurrentNodeId] || resolvedCurrentNodeId || '—' }}
              </div>
            </div>

            <div
              v-if="SHOW_RUNTIME_PERF_LOG && runtimePerfLogs.length"
              class="mb-3 rounded border border-amber-200 bg-amber-50 p-2 text-xs"
            >
              <div class="mb-1 font-medium text-amber-800">加载耗时日志（本次）</div>
              <div
                v-for="(p, idx) in runtimePerfLogs.slice(0, 8)"
                :key="`${p.at}-${p.name}-${idx}`"
                class="flex flex-wrap items-center gap-2"
              >
                <span class="text-amber-700">{{ p.at }}</span>
                <span class="font-medium">{{ p.name }}</span>
                <span :class="p.ok ? 'text-emerald-600' : 'text-red-600'">
                  {{ p.ok ? 'OK' : 'FAIL' }}
                </span>
                <span class="text-muted-foreground">{{ p.ms }}ms</span>
                <span v-if="p.error" class="text-red-600">{{ p.error }}</span>
              </div>
            </div>

            <div v-if="taskBoundFormLoading" class="text-muted-foreground border-border mt-4 border-t pt-4 text-center text-sm">
              正在加载当前节点绑定表单…
            </div>
            <div v-else-if="taskBoundFormMode !== 'none' && resolvedCurrentNodeId" class="border-border mt-4 border-t pt-4">
              <div class="mb-2 text-sm font-medium">
                {{
                  currentPrimaryTodo
                    ? `办理节点：${currentPrimaryTodo.nodeName}（${currentPrimaryTodo.nodeId}）`
                    : `当前节点只读预览：${runtimeNodeNameMap[resolvedCurrentNodeId] || resolvedCurrentNodeId}`
                }}
              </div>
              <p v-if="taskBindingHint" class="text-muted-foreground mb-3 text-xs leading-relaxed">
                {{ taskBindingHint }}
              </p>
              <p v-if="taskBoundFormReuseError" class="mb-3 text-xs leading-relaxed text-red-500">
                复用失败原因：{{ taskBoundFormReuseError }}
              </p>
              <div
                v-if="
                  taskBoundFormMode === 'designer' &&
                  taskFormSchema.length > 0 &&
                  taskLayoutIsTabs &&
                  taskTabsConfig.length
                "
              >
                <FormTabsTablePreview
                  ref="taskTabsTablePreviewRef"
                  :form-schema="(taskFormSchema as any)"
                  :tabs="taskTabsConfig"
                  :field-rules-map="taskTabsFieldRulesMap"
                  :show-form="true"
                  :wrapper-class="
                    isMobilePreviewMode
                      ? 'wf-mobile-form-single grid-cols-1 gap-y-2'
                      : 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]'
                  "
                  :layout="isMobilePreviewMode ? 'vertical' : 'horizontal'"
                  :label-width="isMobilePreviewMode ? 88 : 110"
                  :initial-main-form-values="taskTabsInitialMainValues"
                />
              </div>
              <div v-else-if="taskBoundFormMode === 'designer' && taskFormSchema.length > 0">
                <TaskBoundForm />
              </div>
              <div v-else-if="taskBoundFormMode === 'ext'">
                <component v-if="taskExtRuntimeRoot" :is="taskExtRuntimeRoot" />
                <div v-else class="text-muted-foreground py-6 text-center text-sm">表单加载中…</div>
              </div>
              <div v-else-if="taskBoundFormMode === 'snapshot' && businessDataRows.length">
                <div class="mb-2 text-sm font-medium">业务数据（主表快照）</div>
                <Table
                  :columns="businessDataColumns"
                  :data-source="businessDataRows"
                  :pagination="false"
                  row-key="field"
                  size="small"
                />
              </div>
              <div v-else-if="taskBoundFormMode === 'snapshot'" class="text-muted-foreground text-xs">
                暂无主表快照
              </div>
            </div>
            <div v-else-if="businessDataRows.length" class="border-border mt-4 border-t pt-4">
              <div class="mb-2 text-sm font-medium">业务数据（主表快照）</div>
              <Table
                :columns="businessDataColumns"
                :data-source="businessDataRows"
                :pagination="false"
                row-key="field"
                size="small"
              />
            </div>
            <div v-else class="text-muted-foreground mt-4 border-t border-border pt-4 text-xs">
              暂无待办，仅展示流程信息。
            </div>

            <div class="mt-4 flex flex-wrap gap-2">
              <Button size="small" @click="clearInstanceForNewRun">再发起一笔</Button>
            </div>
          </template>
        </Card>

        <Card size="small" class="wf-viewer-tabs-card">
          <Tabs>
            <Tabs.TabPane key="nodes" tab="流程节点">
              <RuntimeGraphReadonly
                v-if="runtimeDefinitionJson.trim()"
                :definition-json="runtimeDefinitionJson"
                :current-node-id="resolvedCurrentNodeId"
                :timeline-rows="timelineRowsCurrentRound"
                :all-timeline-rows="timelineRows"
                :height="300"
              />
              <div v-else class="text-muted-foreground text-sm">流程图将在发起后显示</div>
            </Tabs.TabPane>
            <Tabs.TabPane key="timeline" tab="审批记录">
              <Timeline v-if="timelineNodeCards.length">
                <Timeline.Item
                  v-for="(row, tIdx) in timelineNodeCards"
                  :key="`${row.nodeId}-${tIdx}`"
                >
                  <div
                    class="rounded border border-border px-3 py-2 text-sm"
                    :class="row.reached ? '' : 'opacity-60'"
                  >
                    <div class="grid grid-cols-1 gap-1 md:grid-cols-2">
                      <div>
                        <span class="text-muted-foreground">提交时间：</span>
                        <span>{{ row.when }}</span>
                      </div>
                      <div>
                        <span class="text-muted-foreground">状态：</span>
                        <Tag class="w-fit" :color="row.statusColor">{{ row.statusText }}</Tag>
                      </div>
                      <div>
                        <span class="text-muted-foreground">节点：</span>
                        <span>{{ row.nodeName || row.nodeId || '—' }}</span>
                      </div>
                      <div>
                        <span class="text-muted-foreground">处理人：</span>
                        <span>{{ row.actor }}</span>
                      </div>
                      <div>
                        <span class="text-muted-foreground">是否查看：</span>
                        <Tag class="w-fit" color="processing">{{ row.viewTraceText }}</Tag>
                      </div>
                    </div>
                    <div v-if="row.comment" class="text-muted-foreground mt-1 text-xs">
                      审批意见：{{ row.comment }}
                    </div>
                    <div v-if="row.historyRejectText" class="mt-1 text-xs text-amber-600">
                      {{ row.historyRejectText }}
                    </div>
                  </div>
                </Timeline.Item>
              </Timeline>
              <div v-else class="text-muted-foreground text-sm">
                {{ inspectInstanceId.trim() ? '暂无记录，点「刷新轨迹」' : '发起流程后显示' }}
              </div>
            </Tabs.TabPane>
          </Tabs>
        </Card>

        <Card v-if="inspectInstanceId.trim()" size="small" title="办理">
          <div v-if="currentPrimaryTodo" class="rounded border border-border p-4">
            <div class="mb-4 text-base font-medium">
              {{ currentPrimaryTodo.nodeName }}
            </div>
            <Space wrap>
              <Button
                type="primary"
                :loading="todoActionLoading === currentPrimaryTodo.taskId"
                @click="openAction(currentPrimaryTodo, 'agree')"
              >
                同意
              </Button>
              <Button
                v-if="canRejectCurrentNode"
                danger
                :loading="todoActionLoading === currentPrimaryTodo.taskId"
                @click="openAction(currentPrimaryTodo, 'reject')"
              >
                驳回
              </Button>
              <Button :loading="todoLoading" @click="refreshTodosAndTaskForm">刷新</Button>
            </Space>
          </div>
          <div v-else class="text-muted-foreground text-sm">暂无待办任务</div>
        </Card>

        <Card size="small">
          <div class="mb-2 flex items-center justify-between">
            <div class="text-sm font-medium">调试（开发与联调）</div>
            <Space>
              <Button size="small" @click="showDebugPanel = !showDebugPanel">
                {{ showDebugPanel ? '收起' : '展开' }}
              </Button>
              <Button size="small" @click="debugEvents = []">清空日志</Button>
            </Space>
          </div>
          <p v-if="!showDebugPanel" class="text-muted-foreground text-xs">
            流程参数、测试身份、JSON 发起、接口日志等均在此展开，主界面保持与真实发起页一致。
          </p>
          <div v-if="showDebugPanel" class="space-y-4 text-xs">
            <div>
              <div class="mb-2 font-medium">测试身份</div>
              <div class="grid gap-2 md:grid-cols-2">
                <div class="rounded border border-dashed p-2">
                  <div class="text-muted-foreground">真实登录（JWT）</div>
                  <div>{{ realLoginSummary }}</div>
                </div>
                <div class="rounded border border-dashed p-2">
                  <div class="text-muted-foreground">模拟办理人（需 AllowRuntimeMockUser）</div>
                  <Space wrap class="mt-1">
                    <Input v-model:value="mockAssigneeUserId" placeholder="工号" class="min-w-[140px]" />
                    <Input v-model:value="mockAssigneeName" placeholder="姓名" class="min-w-[120px]" />
                    <Button size="small" @click="clearMockAssignee">清空</Button>
                  </Space>
                  <div class="mt-1">
                    <Tag v-if="mockAssigneeUserId.trim()" color="processing">
                      {{ mockAssigneeName || mockAssigneeUserId }}（{{ mockAssigneeUserId }}）
                    </Tag>
                    <Tag v-else color="default">与 JWT 一致</Tag>
                  </div>
                </div>
              </div>
            </div>
            <div>
              <div class="mb-2 font-medium">流程参数（接口原样）</div>
              <div class="grid grid-cols-1 gap-2 lg:grid-cols-2">
                <div>
                  <div class="text-muted-foreground">processCode</div>
                  <Input v-model:value="processCode" placeholder="HR_LEAVE" />
                </div>
                <div>
                  <div class="text-muted-foreground">processDefId</div>
                  <Input v-model:value="processDefId" placeholder="GUID" />
                </div>
                <div>
                  <div class="text-muted-foreground">businessKey</div>
                  <Input v-model:value="businessKey" />
                </div>
                <div>
                  <div class="text-muted-foreground">title</div>
                  <Input v-model:value="title" />
                </div>
                <div class="lg:col-span-2">
                  <div class="text-muted-foreground">starterDeptId</div>
                  <Input v-model:value="starterDeptId" />
                </div>
                <div class="lg:col-span-2">
                  <div class="text-muted-foreground">模拟发起人（路由或手改后需重新加载表单）</div>
                  <Space wrap>
                    <Input v-model:value="mockStarterUserId" placeholder="工号" class="min-w-[140px]" />
                    <Input v-model:value="mockStarterName" placeholder="姓名" class="min-w-[140px]" />
                  </Space>
                </div>
              </div>
              <div class="text-muted-foreground mt-2">
                已加载：{{ loadedProcessCode || '—' }} · {{ loadedProcessName || '—' }}
              </div>
            </div>
            <div>
              <div class="mb-2 font-medium">绑定状态</div>
              <div class="flex flex-wrap items-center gap-2">
                <Tag :color="startBoundFormMode === 'json' ? 'default' : 'processing'">
                  {{ startBoundFormMode === 'designer' ? '设计器' : startBoundFormMode === 'ext' ? '硬编码' : 'JSON' }}
                </Tag>
                <span class="text-muted-foreground">{{ startBindingHint }}</span>
              </div>
              <div v-if="startBoundFormCode || startBoundFormName" class="mt-1">
                表单编码：{{ startBoundFormName || '—' }}（{{ startBoundFormCode || 'ext' }}）
              </div>
            </div>
            <div v-if="startBoundFormMode === 'ext' || startBoundFormMode === 'json'">
              <div class="mb-2 font-medium">mainForm JSON（提交载荷）</div>
              <Input.TextArea v-model:value="mainFormJson" :rows="10" />
            </div>
            <div v-if="lastStartResp">
              <div class="mb-1 font-medium">上次发起响应</div>
              <pre class="max-h-32 overflow-auto rounded border p-2">{{ JSON.stringify(lastStartResp) }}</pre>
            </div>
            <div>
              <div class="mb-2 font-medium">实例与刷新</div>
              <Space wrap>
                <Input v-model:value="inspectInstanceId" placeholder="instanceId" class="max-w-md" />
                <Button size="small" :loading="detailLoading" @click="loadInstanceDetail">详情</Button>
                <Button size="small" :loading="timelineLoading" @click="loadTimeline">轨迹</Button>
                <Button size="small" :loading="todoLoading" @click="loadTodos">待办</Button>
              </Space>
            </div>
            <div>
              <div class="mb-1 font-medium">请求错误</div>
              <div v-if="!debugEvents.length" class="text-muted-foreground">暂无</div>
              <div v-for="(evt, idx) in debugEvents" v-else :key="idx" class="mb-2 rounded border p-2">
                <div>[{{ evt.at }}] {{ evt.action }} — {{ evt.summary }}</div>
                <pre class="mt-1 max-h-28 overflow-auto">{{ toPrettyJson(evt.payload) }}</pre>
              </div>
            </div>
            <div v-if="instanceDetail">
              <div class="mb-1 font-medium">latestData JSON</div>
              <pre class="max-h-40 overflow-auto rounded border p-2">{{ latestDataPretty }}</pre>
            </div>
          </div>
        </Card>
      </div>
    </ProcessPreviewShell>

    <Modal
      v-model:open="actionModalOpen"
      :title="actionType === 'agree' ? '同意' : '驳回'"
      :confirm-loading="!!todoActionLoading"
      @ok="submitAction"
    >
      <Input.TextArea
        v-model:value="actionComment"
        :rows="4"
        :placeholder="actionType === 'agree' ? '审批意见（可选）' : '驳回原因（建议填写）'"
      />
      <div v-if="actionType === 'reject'" class="mt-3">
        <div class="mb-1 text-xs text-muted-foreground">退回到节点ID（可选）</div>
        <Input
          v-model:value="actionRejectToNodeId"
          :placeholder="defaultRejectTargetNodeId ? `默认：${defaultRejectTargetNodeId}` : '请输入退回节点ID'"
        />
        <div v-if="currentNodeReturnEdges.length" class="text-muted-foreground mt-1 text-xs">
          可退回出口：
          {{
            currentNodeReturnEdges
              .map((x) => `${runtimeNodeNameMap[x.targetNodeId] || x.targetNodeId}（${x.targetNodeId}）`)
              .join('，')
          }}
        </div>
      </div>
    </Modal>
  </Page>
</template>

<style scoped>
.wf-viewer-form-tight {
  padding-top: 5px;
}

.wf-viewer-tabs-card :deep(.ant-card-body) {
  padding-top: 6px !important;
}

.wf-viewer-tabs-card :deep(.ant-tabs-nav) {
  margin: 0 0 6px 0 !important;
}

.wf-viewer-form-tight :deep(.form-tabs-table-preview > div.mb-4) {
  margin-bottom: 5px !important;
}

.wf-viewer-form-tight :deep(.form-tabs-table-preview > div.mt-4) {
  margin-top: 5px !important;
}

.wf-viewer-form-tight :deep(.form-tabs-table-preview .py-2) {
  padding-top: 5px !important;
  padding-bottom: 5px !important;
}

.wf-viewer-form-tight :deep(.form-tabs-table-preview .mb-2) {
  margin-bottom: 5px !important;
}

.wf-viewer-form-tight :deep(.ant-form-item) {
  margin-bottom: 5px !important;
}

.wf-viewer-form-tight :deep(.ant-form-item-label) {
  padding-bottom: 0 !important;
}

.wf-viewer-form-tight :deep(.ant-form-item-control) {
  min-height: auto !important;
}

.wf-viewer-form-tight :deep(.ant-input),
.wf-viewer-form-tight :deep(.ant-input-affix-wrapper),
.wf-viewer-form-tight :deep(.ant-select-selector) {
  min-height: 28px !important;
  height: 28px !important;
  padding-top: 2px !important;
  padding-bottom: 2px !important;
}

.wf-viewer-form-tight :deep(.ant-tabs-nav) {
  margin: 0 0 5px 0 !important;
}

.wf-viewer-form-tight :deep(.ant-tabs-content) {
  padding-top: 5px !important;
}

.wf-viewer-form-tight :deep(.ant-table) {
  margin-top: 5px !important;
}

.wf-viewer-form-tight :deep(.ant-table-container) {
  border-radius: 6px;
}

:deep(.wf-required-missing .ant-form-item-label > label::after) {
  content: ' 必填';
  color: #ff4d4f;
  font-size: 12px;
  font-weight: 600;
}

:deep(.wf-required-mark .ant-form-item-label) {
  padding-left: 0 !important;
}

:deep(.wf-required-mark .ant-form-item-label::before) {
  content: '';
}

:deep(.wf-required-mark .ant-form-item-control-input-content) {
  position: relative;
  overflow: visible !important;
}

:deep(.wf-required-mark .ant-form-item-control-input-content::after) {
  content: '*';
  position: absolute;
  right: -10px;
  top: 50%;
  transform: translateY(-50%);
  color: #ff4d4f;
  font-weight: 700;
  line-height: 1;
  z-index: 2;
}

:deep(label.wf-required-missing-label::after) {
  content: ' 必填';
  color: #ff4d4f;
  font-size: 12px;
  font-weight: 600;
}

:deep(.wf-required-inline-star) {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 10px;
  color: #ff4d4f;
  font-size: 14px;
  font-weight: 700;
  line-height: 1;
}

:deep(.wf-required-missing .ant-input),
:deep(.wf-required-missing .ant-input-affix-wrapper),
:deep(.wf-required-missing .ant-select-selector),
:deep(.wf-required-missing .ant-picker),
:deep(.wf-required-missing .ant-input-number),
:deep(.wf-required-missing .ant-input-number-affix-wrapper) {
  border-color: #ff4d4f !important;
  box-shadow: 0 0 0 2px rgb(255 77 79 / 12%) !important;
}

.wf-mobile-single :deep(.md\:grid-cols-2),
.wf-mobile-single :deep(.grid-cols-2) {
  grid-template-columns: minmax(0, 1fr) !important;
}

.wf-mobile-single :deep(.wf-mobile-form-single) {
  grid-template-columns: minmax(0, 1fr) !important;
}

.wf-mobile-single :deep(.wf-viewer-form-tight .grid),
.wf-mobile-single :deep(.wf-viewer-form-tight [class*='grid-cols-']) {
  grid-template-columns: minmax(0, 1fr) !important;
  column-gap: 0 !important;
}

.wf-mobile-single :deep(.ant-form-item) {
  width: 100% !important;
}

.wf-mobile-single :deep(.ant-form-item-control),
.wf-mobile-single :deep(.ant-form-item-control-input),
.wf-mobile-single :deep(.ant-form-item-control-input-content) {
  width: 99% !important;
}

.wf-mobile-single :deep(.ant-input),
.wf-mobile-single :deep(.ant-input-affix-wrapper),
.wf-mobile-single :deep(.ant-select),
.wf-mobile-single :deep(.ant-select-selector),
.wf-mobile-single :deep(.ant-picker),
.wf-mobile-single :deep(.ant-input-number),
.wf-mobile-single :deep(.ant-input-number-affix-wrapper),
.wf-mobile-single :deep(textarea.ant-input) {
  width: 99% !important;
  max-width: 99% !important;
}
</style>

