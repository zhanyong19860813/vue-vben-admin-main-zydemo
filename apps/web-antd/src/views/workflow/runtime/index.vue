<script setup lang="ts">
import type { Component as VueConcreteComponent } from 'vue';
import { computed, nextTick, onMounted, ref, shallowRef, watch } from 'vue';
import { useRoute } from 'vue-router';

import { Page } from '@vben/common-ui';
import { useAccessStore, useUserStore } from '@vben/stores';
import type { VbenFormSchema } from '#/adapter/form';
import { useVbenForm } from '#/adapter/form';
import { getWorkflowFormSchemaList } from '#/api/workflow';
import { buildWorkflowBuiltinValuesFromUser } from '#/views/demos/form-designer/workflowFormRuntime';
import FormTabsTablePreview from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import type { TabTableConfig } from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import {
  applyFieldRulesToSchemaPlain,
  inferBizTypeFromGraphNode,
  jsonSafeClone,
  normalizeSchemaForPreview,
  parseStoredFormSchemaJson,
} from '#/views/workflow/wfFormPreviewUtils';
import { createExtWorkflowFormComponent } from '#/views/workflowExtForm/registry';
import ProcessPreviewShell from '#/views/workflow/process-preview/ProcessPreviewShell.vue';
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

const route = useRoute();
const userStore = useUserStore();
const accessStore = useAccessStore();

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

const showDebugPanel = ref(false);

const processCode = ref('');
const processDefId = ref('');
const businessKey = ref('');
const title = ref('');
const starterDeptId = ref('');
const mockStarterUserId = ref('');
const mockStarterName = ref('');
const mockStarterDeptName = ref('');
const mockStarterPositionName = ref('');
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

const startLoading = ref(false);
const lastStartResp = ref<Record<string, unknown> | null>(null);

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
const debugEvents = ref<Array<Record<string, any>>>([]);
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
const startTabsFieldRulesMap = ref<Record<string, 'hidden' | 'readonly' | 'visible'>>({});
const startTabsTablePreviewRef = ref<InstanceType<typeof FormTabsTablePreview> | null>(null);
/** 当前流程定义 JSON，用于渲染与「流程预览」一致的步骤条 */
const runtimeDefinitionJson = ref('');
/** 从接口加载的流程名称/编码（主界面展示，不暴露技术参数） */
const loadedProcessName = ref('');
const loadedProcessCode = ref('');

const [StartBoundForm, startBoundFormApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as VbenFormSchema[],
  wrapperClass: 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
  layout: 'horizontal',
  formItemGapPx: 2 as any,
  commonConfig: { labelWidth: 110 } as any,
});

/** 当前待办节点绑定的办理表单（设计器 / 硬编码 / 无绑定时仅快照） */
const taskBoundFormLoading = ref(false);
/** 并发多次 loadTaskBoundForm 时计数，避免先完成的请求错误地关掉仍在进行的 loading */
let taskFormLoadInFlight = 0;
let taskFormLoadLatestSeq = 0;
let taskFormLoadSafetyTimer: ReturnType<typeof setTimeout> | null = null;
const taskBoundFormMode = ref<'none' | 'designer' | 'ext' | 'snapshot'>('none');
const taskFormSchema = ref<VbenFormSchema[]>([]);
const taskExtRuntimeRoot = shallowRef<VueConcreteComponent | null>(null);
const taskBindingHint = ref('');
const taskLayoutIsTabs = ref(false);
const taskTabsConfig = ref<TabTableConfig[]>([]);
const taskTabsInitialMainValues = ref<Record<string, any>>({});
const taskTabsFieldRulesMap = ref<Record<string, 'hidden' | 'readonly' | 'visible'>>({});
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

function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const tid = setTimeout(
      () => reject(new Error(`${label} 超时（${Math.round(ms / 1000)}s）`)),
      ms,
    );
    p.then(
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

function isLikelyStartNode(n: any) {
  if (String(n?.properties?.bizType || '').trim() === 'start') return true;
  const biz = inferBizTypeFromGraphNode(n);
  if (biz === 'start') return true;
  const tv = String(n?.text?.value ?? n?.text ?? '').trim();
  return /发起|开始|起草/.test(tv);
}

type WfRuntimeNodeBinding = {
  formCode: string;
  formName: string;
  formSource?: string;
  extFormKey?: string;
  fieldRules?: Record<string, any>;
  workflowNoPrefix?: string;
};

function parseFormBindingRecord(fb: Record<string, any>): WfRuntimeNodeBinding | null {
  const formCode = String(fb.formCode || '').trim();
  const formName = String(fb.formName || '').trim();
  const formSource = String(fb.formSource || '').trim();
  const extFormKey = String(fb.extFormKey || '').trim();
  if (!formCode && !(formSource === 'ext' && extFormKey)) return null;
  return {
    formCode,
    formName: formName || formCode || extFormKey,
    formSource,
    extFormKey,
    fieldRules: (fb.fieldRules || {}) as Record<string, any>,
    workflowNoPrefix: String(fb.workflowNoPrefix || '').trim() || undefined,
  };
}

function getStartNodeBinding(definitionJson: string): WfRuntimeNodeBinding | null {
  try {
    const parsed = JSON.parse(definitionJson) as Record<string, any>;
    const graphData = (parsed?.graphData ?? {}) as { nodes?: any[] };
    const nodes = Array.isArray(graphData.nodes) ? graphData.nodes : [];
    const start = nodes.find((n) => isLikelyStartNode(n)) ?? nodes[0];
    if (!start) return null;
    const fb = (start?.properties?.formBinding ?? {}) as Record<string, any>;
    return parseFormBindingRecord(fb);
  } catch {
    return null;
  }
}

/** 按节点 id 读取 graphData 中的 formBinding（与流程管理/预览一致） */
function getNodeBindingFromDefinition(
  definitionJson: string,
  nodeId: string,
): WfRuntimeNodeBinding | null {
  const id = String(nodeId || '').trim();
  if (!id || !definitionJson.trim()) return null;
  try {
    const parsed = JSON.parse(definitionJson) as Record<string, any>;
    const nodes = (parsed?.graphData?.nodes ?? []) as any[];
    const node = Array.isArray(nodes) ? nodes.find((n) => String(n?.id ?? '').trim() === id) : null;
    if (!node) return null;
    const fb = (node?.properties?.formBinding ?? {}) as Record<string, any>;
    return parseFormBindingRecord(fb);
  } catch {
    return null;
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
  await startBoundFormApi.setState({ schema: [] as VbenFormSchema[] });
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

async function loadStartBoundForm() {
  startBindingLoading.value = true;
  try {
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
    const definitionJson = String(proc?.version?.definitionJson || '').trim();
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
      await startBoundFormApi.setState({ schema: [] as VbenFormSchema[] });
      await startBoundFormApi.setValues({});
      return;
    }
    const formCode = String(binding.formCode || '').trim();
    if (!formCode) {
      await resetBoundFormState('发起节点表单编码为空，使用 JSON 方式发起。');
      return;
    }
    const listRaw = (await getWorkflowFormSchemaList()) as any;
    const formRows = (Array.isArray(listRaw) ? listRaw : listRaw?.items || listRaw?.records || []) as Array<Record<string, any>>;
    const rec = formRows.find((x) => String(x?.code || '').trim() === formCode);
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
    startFormSchema.value = decorated as VbenFormSchema[];
    startBoundFormMode.value = 'designer';
    startExtRuntimeRoot.value = null;

    const layoutTabs = !!(parsed.layoutIsTabs && parsed.tabs?.length);
    startLayoutIsTabs.value = layoutTabs;
    startTabsConfig.value = layoutTabs ? (jsonSafeClone(parsed.tabs) as TabTableConfig[]) : [];
    startTabsFieldRulesMap.value = ((binding.fieldRules || {}) as Record<
      string,
      'hidden' | 'readonly' | 'visible'
    >);

    const seedUser = {
      ...(userStore.userInfo || {}),
      realName: mockStarterName.value || (userStore.userInfo as any)?.realName,
      name: mockStarterName.value || (userStore.userInfo as any)?.name,
      employeeCode: mockStarterUserId.value || (userStore.userInfo as any)?.employeeCode,
      employeeNo: mockStarterUserId.value || (userStore.userInfo as any)?.employeeNo,
      userCode: mockStarterUserId.value || (userStore.userInfo as any)?.userCode,
      username: mockStarterUserId.value || (userStore.userInfo as any)?.username,
      deptName: mockStarterDeptName.value || (userStore.userInfo as any)?.deptName,
      departmentName: mockStarterDeptName.value || (userStore.userInfo as any)?.departmentName,
      dutyName: mockStarterPositionName.value || (userStore.userInfo as any)?.dutyName,
      positionName: mockStarterPositionName.value || (userStore.userInfo as any)?.positionName,
      postName: mockStarterPositionName.value || (userStore.userInfo as any)?.postName,
      position: mockStarterPositionName.value || (userStore.userInfo as any)?.position,
    } as Record<string, any>;
    const builtins = buildWorkflowBuiltinValuesFromUser(startFormSchema.value as VbenFormSchema[], {
      userInfo: seedUser,
      workflowNoPrefix: parsed.workflowNoPrefix || binding.workflowNoPrefix,
    });
    let jsonValues: Record<string, any> = {};
    try {
      jsonValues = mainFormJson.value.trim()
        ? (JSON.parse(mainFormJson.value) as Record<string, any>)
        : {};
    } catch {
      jsonValues = {};
    }
    const mergedMain = { ...builtins, ...jsonValues };
    startTabsInitialMainValues.value = mergedMain;

    if (layoutTabs) {
      await startBoundFormApi.setState({ schema: [] as VbenFormSchema[] });
      await startBoundFormApi.setValues({});
      startBindingHint.value = `已按发起节点「上表+页签表格」渲染：${binding.formName || formCode}`;
    } else {
      await startBoundFormApi.setState({ schema: startFormSchema.value as VbenFormSchema[] });
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
  taskBoundFormMode.value = 'none';
  taskFormSchema.value = [];
  taskExtRuntimeRoot.value = null;
  taskLayoutIsTabs.value = false;
  taskTabsConfig.value = [];
  taskTabsInitialMainValues.value = {};
  taskTabsFieldRulesMap.value = {};
  taskPendingTabsData.value = {};
  await taskBoundFormApi.setState({ schema: [] as VbenFormSchema[] });
  await taskBoundFormApi.setValues({});
}

function parseLatestMainForm(): Record<string, any> {
  const raw = instanceDetail.value?.latestData?.main_form_json;
  if (raw === null || raw === undefined) return {};
  try {
    if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
      return raw as Record<string, any>;
    }
    const s = String(raw).trim();
    if (!s) return {};
    return JSON.parse(s) as Record<string, any>;
  } catch {
    return {};
  }
}

function parseLatestTabsData(): Record<string, any[]> {
  const raw = instanceDetail.value?.latestData?.tabs_data_json;
  if (raw === null || raw === undefined) return {};
  try {
    if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
      const o = raw as Record<string, unknown>;
      const out: Record<string, any[]> = {};
      for (const k of Object.keys(o)) {
        if (Array.isArray(o[k])) out[k] = o[k] as any[];
      }
      return out;
    }
    const s = String(raw).trim();
    if (!s) return {};
    const o = JSON.parse(s) as Record<string, any>;
    const out: Record<string, any[]> = {};
    for (const k of Object.keys(o)) {
      if (Array.isArray(o[k])) out[k] = o[k];
    }
    return out;
  } catch {
    return {};
  }
}

async function ensureRuntimeDefinitionJson() {
  if (runtimeDefinitionJson.value.trim()) return;
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
  const todo = todoRows.value[0] as WfEngineRuntimeTodoItem | undefined;
  if (!todo) {
    taskBoundFormMode.value = 'none';
    await resetTaskBoundFormState('暂无待办，仅查看流程信息。');
    return;
  }
  const nodeId = String(todo.nodeId || '').trim();
  taskFormLoadLatestSeq += 1;
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
  }, 20_000);
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
      await taskBoundFormApi.setState({ schema: [] as VbenFormSchema[] });
      taskBindingHint.value = '未加载到流程定义，已展示主表快照。';
      return;
    }
    const binding = getNodeBindingFromDefinition(defJson, nodeId);
    if (!binding) {
      taskBoundFormMode.value = 'snapshot';
      await taskBoundFormApi.setState({ schema: [] as VbenFormSchema[] });
      taskBindingHint.value = `节点「${todo.nodeName || nodeId}」未绑定表单，已展示主表快照。`;
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
      await taskBoundFormApi.setState({ schema: [] as VbenFormSchema[] });
      await taskBoundFormApi.setValues({});
      taskBindingHint.value = `当前节点硬编码表单：${binding.formName || binding.extFormKey}`;
      return;
    }
    const formCode = String(binding.formCode || '').trim();
    if (!formCode) {
      taskBoundFormMode.value = 'snapshot';
      taskBindingHint.value = '节点绑定表单编码为空，已展示主表快照。';
      return;
    }
    const listRaw = (await withTimeout(
      getWorkflowFormSchemaList(),
      45_000,
      '加载表单设计器列表',
    )) as any;
    const formRows = (Array.isArray(listRaw) ? listRaw : listRaw?.items || listRaw?.records || []) as Array<Record<string, any>>;
    const rec = formRows.find((x) => String(x?.code || '').trim() === formCode);
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
    taskFormSchema.value = decorated as VbenFormSchema[];
    taskBoundFormMode.value = 'designer';

    const layoutTabs = !!(parsed.layoutIsTabs && parsed.tabs?.length);
    taskLayoutIsTabs.value = layoutTabs;
    taskTabsConfig.value = layoutTabs ? (jsonSafeClone(parsed.tabs) as TabTableConfig[]) : [];
    taskTabsFieldRulesMap.value = ((binding.fieldRules || {}) as Record<
      string,
      'hidden' | 'readonly' | 'visible'
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
      taskBoundFormApi.setState({ schema: [] as VbenFormSchema[] });
      taskBoundFormApi.setValues({});
    } else {
      await withTimeout(
        (async () => {
          await taskBoundFormApi.setState({ schema: taskFormSchema.value as VbenFormSchema[] });
          await nextTick();
          await taskBoundFormApi.setValues(mergedMain);
        })(),
        45_000,
        '渲染办理表单',
      );
    }
    taskBindingHint.value = layoutTabs
      ? `当前节点「上表+页签表格」：${binding.formName || formCode}`
      : `当前节点绑定表单：${binding.formName || formCode}`;
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
  const t = todoRows.value[0]?.nodeId;
  if (t) return String(t);
  const raw = instanceDetail.value?.instance?.current_node_ids;
  if (!raw) return '';
  return String(raw).split(',')[0].trim();
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
  const st = instanceDetail.value?.instance?.status;
  if (st === 0 || st === '0') return { text: '运行中', color: 'processing' as const };
  if (st === 1 || st === '1') return { text: '已完成', color: 'success' as const };
  return { text: String(st ?? '—'), color: 'default' as const };
});

const currentPrimaryTodo = computed(
  () => todoRows.value[0] as WfEngineRuntimeTodoItem | undefined,
);

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

const timelineViewRows = computed(() =>
  (timelineRows.value || []).map((row) => {
    const actor = String(row.operator_name || row.operator_user_id || '系统');
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
  }),
);

const timelineNodeCards = computed(() => {
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
    const passedTask = nodeTasks.find((t) => t.statusNum === 1);
    const rejectedTask = nodeTasks.find((t) => t.statusNum === 2);
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
    const actor = String(
      latest?.operator_name ||
        latest?.operator_user_id ||
        pendingTask?.assignee_name ||
        pendingTask?.assignee_user_id ||
        '—',
    );
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
    const latestRejectActor = String(
      latestReject?.operator_name || latestReject?.operator_user_id || '',
    ).trim();
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
  inspectInstanceId.value = '';
  instanceDetail.value = null;
  timelineRows.value = [];
  todoRows.value = [];
  todoTotal.value = 0;
  lastStartResp.value = null;
  await resetTaskBoundFormState('');
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
    } else if (startBoundFormMode.value === 'designer' && startFormSchema.value.length > 0) {
      mainForm = ((await startBoundFormApi.getValues()) || {}) as Record<string, unknown>;
    } else {
      try {
        mainForm = mainFormJson.value.trim()
          ? (JSON.parse(mainFormJson.value) as Record<string, unknown>)
          : {};
      } catch {
        message.error('主表单 JSON 格式不正确');
        return;
      }
    }

    const requestPayload = {
      processCode: processCode.value.trim() || undefined,
      processDefId: processDefId.value.trim() || undefined,
      businessKey: businessKey.value.trim() || undefined,
      title: title.value.trim() || undefined,
      starterDeptId: starterDeptId.value.trim() || undefined,
      mockStarterUserId: mockStarterUserId.value.trim() || undefined,
      mockStarterName: mockStarterName.value.trim() || undefined,
      mainForm,
      tabsData,
    };
    const resp = await wfEngineRuntimeStart(requestPayload);
    lastStartResp.value = resp as unknown as Record<string, unknown>;
    const instId = String((resp as any)?.instanceId || '').trim();
    let autoOpenedApproval = false;
    if (instId) {
      inspectInstanceId.value = instId;
      await trySyncMockAssigneeFromInstance(instId);
      await loadTodos();
      await loadInstanceDetail();
      await loadTimeline();
      await loadTaskBoundForm();
      /** 无节点专属表单时：仅一条待办则打开意见弹窗（旧测试闭环） */
      if (todoRows.value.length === 1 && !taskFormHasExclusiveUi()) {
        await nextTick();
        openAction(todoRows.value[0] as WfEngineRuntimeTodoItem, 'agree');
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
    const data = await wfEngineRuntimeTodo({
      page: todoPage.value,
      pageSize: todoPageSize.value,
    });
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
      await loadTaskBoundForm();
    }
    if (todoRows.value.length === 1 && !taskFormHasExclusiveUi()) {
      await nextTick();
      openAction(todoRows.value[0] as WfEngineRuntimeTodoItem, 'agree');
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
    const data = await wfEngineRuntimeInstanceDetail(id);
    instanceDetail.value = data as unknown as Record<string, any>;
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
    timelineRows.value = (await wfEngineRuntimeInstanceTimeline(id)) as Array<Record<string, any>>;
  } catch (err) {
    pushDebugEvent('加载实例轨迹', err);
  } finally {
    timelineLoading.value = false;
  }
}

onMounted(async () => {
  processCode.value = String(route.query.processCode || '').trim();
  processDefId.value = String(route.query.processDefId || '').trim();
  mockStarterUserId.value = String(route.query.mockStarterUserId || '').trim();
  mockStarterName.value = String(route.query.mockStarterName || '').trim();
  mockStarterDeptName.value = String(route.query.mockStarterDeptName || '').trim();
  mockStarterPositionName.value = String(route.query.mockStarterPositionName || '').trim();
  await loadStartBoundForm();
  inspectInstanceId.value = String(route.query.instanceId || '').trim();
  await loadTodos();
  if (inspectInstanceId.value) {
    await loadInstanceDetail();
    await loadTimeline();
    await loadTaskBoundForm();
  }
});

async function refreshTodosAndTaskForm() {
  await loadTodos();
  await loadTaskBoundForm();
}

watch(
  () =>
    [
      processDefId.value,
      mockStarterUserId.value,
      mockStarterName.value,
      mockStarterDeptName.value,
      mockStarterPositionName.value,
    ] as const,
  async () => {
    await loadStartBoundForm();
  },
);
</script>

<template>
  <Page title="发起流程" :description="pageDescription" content-class="min-h-0">
    <ProcessPreviewShell :frame="false">
      <div class="flex flex-col gap-4">
        <Card size="small" :title="primaryFlowCardTitle">
          <template v-if="!inspectInstanceId.trim()">
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
                wrapper-class="grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]"
                layout="horizontal"
                :label-width="110"
                :initial-main-form-values="startTabsInitialMainValues"
              />
              <div class="mt-6 flex justify-end border-t pt-4">
                <Button type="primary" size="large" :loading="startLoading" @click="startRuntime">
                  提交
                </Button>
              </div>
            </div>
            <div v-else-if="startBoundFormMode === 'designer' && startFormSchema.length > 0">
              <StartBoundForm />
              <div class="mt-6 flex justify-end border-t pt-4">
                <Button type="primary" size="large" :loading="startLoading" @click="startRuntime">
                  提交
                </Button>
              </div>
            </div>
            <div v-else-if="startBoundFormMode === 'ext'">
              <component v-if="startExtRuntimeRoot" :is="startExtRuntimeRoot" />
              <div v-else class="text-muted-foreground py-8 text-center">表单加载中…</div>
              <div class="mt-6 flex justify-end border-t pt-4">
                <Button type="primary" size="large" :loading="startLoading" @click="startRuntime">
                  提交
                </Button>
              </div>
            </div>
            <div v-else>
              <p class="text-muted-foreground mb-4 text-sm leading-relaxed">
                当前流程未配置可视化发起表单。请联系管理员配置发起节点绑定，或在下方「调试」面板使用 JSON 发起。
              </p>
              <div class="flex justify-end">
                <Button type="primary" size="large" :loading="startLoading" @click="startRuntime">
                  提交
                </Button>
              </div>
            </div>
          </template>

          <template v-else>
            <div class="mb-4 grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
              <div>
                <span class="text-muted-foreground">流程编号：</span>
                {{ instanceDetail?.instance?.instance_no || '—' }}
              </div>
              <div>
                <span class="text-muted-foreground">流程名称：</span>
                {{ instanceDetail?.process?.process_name || '—' }}
              </div>
              <div>
                <span class="text-muted-foreground">发起人：</span>
                {{ instanceDetail?.instance?.starter_user_id || '—' }}
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
              <div class="md:col-span-2">
                <span class="text-muted-foreground">当前状态：</span>
                <Tag :color="instanceMetaStatus.color">{{ instanceMetaStatus.text }}</Tag>
              </div>
              <div class="md:col-span-2">
                <span class="text-muted-foreground">当前节点：</span>
                {{ resolvedCurrentNodeId || '—' }}
              </div>
            </div>

            <div v-if="taskBoundFormLoading" class="text-muted-foreground border-border mt-4 border-t pt-4 text-center text-sm">
              正在加载当前节点绑定表单…
            </div>
            <div v-else-if="currentPrimaryTodo" class="border-border mt-4 border-t pt-4">
              <div class="mb-2 text-sm font-medium">
                办理节点：{{ currentPrimaryTodo.nodeName }}（{{ currentPrimaryTodo.nodeId }}）
              </div>
              <p v-if="taskBindingHint" class="text-muted-foreground mb-3 text-xs leading-relaxed">
                {{ taskBindingHint }}
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
                  wrapper-class="grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]"
                  layout="horizontal"
                  :label-width="110"
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

        <Card size="small">
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

