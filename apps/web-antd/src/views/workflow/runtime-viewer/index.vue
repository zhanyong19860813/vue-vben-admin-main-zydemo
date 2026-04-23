<script setup lang="ts">
import type { Component as VueConcreteComponent } from 'vue';
import { computed, h, nextTick, onMounted, ref, shallowRef, watch } from 'vue';
import { useRoute } from 'vue-router';

import { useAccessStore, useUserStore } from '@vben/stores';
import type { VbenFormSchema } from '#/adapter/form';
import type { WfNodeFormFieldRule } from '#/views/demos/workflow-designer/workflow-definition.schema';
import { useVbenForm } from '#/adapter/form';
import { getWorkflowFormSchemaList } from '#/api/workflow';
import { buildWorkflowBuiltinValuesFromUser } from '#/views/demos/form-designer/workflowFormRuntime';
import FormTabsTablePreview from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import type { TabTableConfig } from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import {
  applyFieldRulesToSchemaPlain,
  coerceLatestMainForm,
  coerceLatestTabsData,
  inferBizTypeFromGraphNode,
  isLikelyStartNode,
  jsonSafeClone,
  normalizeFieldRule,
  normalizeSchemaForPreview,
  parseStoredFormSchemaJson,
  resolveNodeFormBindingWithStartFallback,
} from '#/views/workflow/wfFormPreviewUtils';
import { createExtWorkflowFormComponent } from '#/views/workflowExtForm/registry';
import {
  collectEmployeeIdsForDisplay,
  fetchEmployeeDisplayLabelsByIds,
  formatOperatorLabel,
  resolveActorFromLatestAndPending,
} from '#/views/workflow/workflowOperatorDisplay';

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

import RuntimeGraphReadonly from '../runtime/RuntimeGraphReadonly.vue';
import ProcessPreviewShell from '#/views/workflow/process-preview/ProcessPreviewShell.vue';

import {
  type WfEngineRuntimeTodoItem,
  setWorkflowRuntimeMockAssigneeUserId,
  wfEngineRuntimeCompleteTask,
  wfEngineGetProcess,
  wfEngineRuntimeInstanceDetail,
  wfEngineRuntimeInstanceTimeline,
  wfEngineRuntimeTodo,
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

/** 独立页可能未走权限守卫的 fetchUserInfo，与 runtime-embed 一致补全身份 */
async function ensureUserInfoForRuntimeViewer() {
  if (!accessStore.accessToken) return;
  const u = userStore.userInfo as Record<string, any> | null | undefined;
  const hasUsable =
    u &&
    (String(u.realName || u.name || '').trim() ||
      String(u.username || '').trim() ||
      String(u.employeeCode || u.employeeNo || u.userId || '').trim());
  if (hasUsable) return;
  try {
    await authStore.fetchUserInfo();
  } catch {
    /* ignore */
  }
}

function normId(s: string): string {
  return String(s || '')
    .trim()
    .replace(/^\{|\}$/g, '')
    .replace(/-/g, '')
    .toLowerCase();
}

function sameActorOrInstanceId(a: string, b: string): boolean {
  const A = normId(a);
  const B = normId(b);
  if (!A || !B) return false;
  if (A.length >= 32 && B.length >= 32 && /^[0-9a-f]+$/.test(A) && /^[0-9a-f]+$/.test(B)) {
    return A.slice(0, 32) === B.slice(0, 32);
  }
  return String(a).trim() === String(b).trim();
}

function collectActorIdCandidates(): string[] {
  const out: string[] = [];
  const push = (v: unknown) => {
    const s = String(v ?? '').trim();
    if (s) out.push(s);
  };
  const u = (userStore.userInfo || {}) as Record<string, any>;
  push(u.userId);
  push(u.UserId);
  push(u.id);
  push(u.employee_id);
  push(u.employeeId);
  push(u.username);
  push(u.Username);
  push(u.employeeCode);
  const jwt = decodeJwtPayload(accessStore.accessToken);
  if (jwt) {
    push(jwt.sub);
    push(jwt.UserId);
    push(jwt.userId);
    push((jwt as any).employee_id);
    push((jwt as any).EmployeeId);
    push((jwt as any).unique_name);
    push((jwt as any).preferred_username);
  }
  // 若从「全员待办」以指定身份打开查看页，需把 mock 身份也纳入办理人匹配候选。
  push(route.query.mockAssigneeUserId);
  return [...new Set(out)];
}

function mapInstanceTaskToTodoItem(task: Record<string, any>): WfEngineRuntimeTodoItem | null {
  const detail = instanceDetail.value as any;
  if (!detail) return null;
  const inst = detail.instance || {};
  const proc = detail.process || {};
  const tid = String(task.id ?? task.taskId ?? '').trim();
  if (!tid) return null;
  const iid = String(inst.id ?? inst.Id ?? inspectInstanceId.value).trim();
  return {
    taskId: tid,
    taskNo: String(task.task_no ?? task.taskNo ?? ''),
    instanceId: iid,
    instanceNo: String(inst.instance_no ?? inst.instanceNo ?? ''),
    processName: String(proc.process_name ?? proc.processName ?? ''),
    nodeId: String(task.node_id ?? task.nodeId ?? ''),
    nodeName: String(task.node_name ?? task.nodeName ?? ''),
    assigneeUserId: String(task.assignee_user_id ?? task.assigneeUserId ?? ''),
    assigneeName: (task.assignee_name ?? task.assigneeName) as string | undefined,
    receivedAt: (task.received_at ?? task.receivedAt) as string | undefined,
  };
}

/** 待办列表缺页/格式不一致时，用实例详情里的 status=0 任务构造办理项 */
function pickTodoFromInstanceTasks(): WfEngineRuntimeTodoItem | null {
  const detail = instanceDetail.value as any;
  const rows = (detail?.tasks || []) as Record<string, any>[];
  const candidates = collectActorIdCandidates();
  const pending = rows.filter((t) => Number(t.status ?? t.Status ?? -1) === 0);
  const mine = pending.filter((t) => {
    const aid = String(t.assignee_user_id ?? t.assigneeUserId ?? '').trim();
    if (!aid || !candidates.length) return false;
    return candidates.some((c) => sameActorOrInstanceId(c, aid));
  });
  if (!mine.length) return null;
  const curNode = resolvedCurrentNodeId.value.trim();
  if (curNode) {
    const hit = mine.find((t) => sameActorOrInstanceId(String(t.node_id ?? t.nodeId ?? ''), curNode));
    if (hit) return mapInstanceTaskToTodoItem(hit);
  }
  return mapInstanceTaskToTodoItem(mine[0]!);
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

function toTimeMs(v: unknown): number {
  if (!v) return Number.NaN;
  try {
    const d = new Date(String(v));
    const n = d.getTime();
    return Number.isFinite(n) ? n : Number.NaN;
  } catch {
    return Number.NaN;
  }
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

function resolveEndNodeId(defJson: string): string {
  if (!defJson.trim()) return '';
  try {
    const parsed = JSON.parse(defJson) as { graphData?: { nodes?: any[] } };
    const nodes = parsed?.graphData?.nodes ?? [];
    const end = (Array.isArray(nodes) ? nodes : []).find((n) => {
      const biz = inferBizTypeFromGraphNode(n);
      return biz === 'end';
    });
    return String(end?.id ?? '').trim();
  } catch {
    return '';
  }
}

function hasEdgeToNode(defJson: string, fromNodeId: string, toNodeId: string): boolean {
  if (!defJson.trim() || !fromNodeId || !toNodeId) return false;
  try {
    const parsed = JSON.parse(defJson) as { graphData?: { edges?: any[] } };
    const edges = parsed?.graphData?.edges ?? [];
    return (Array.isArray(edges) ? edges : []).some((e) => {
      const s = String(e?.sourceNodeId ?? '').trim();
      const t = String(e?.targetNodeId ?? '').trim();
      return s === fromNodeId && t === toNodeId;
    });
  } catch {
    return false;
  }
}

const runtimeDraftKey = ref('');
const runtimeDraftDefinitionJson = ref('');
const runtimeDefinitionJson = ref('');
const processDefId = ref('');
const processCode = ref('');
const loadedProcessName = ref('');
const loadedProcessCode = ref('');

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
    runtimeDefinitionJson.value = definitionJson;
    if (!processCode.value.trim() && parsed?.processCode) {
      processCode.value = String(parsed.processCode || '').trim();
    }
    if (parsed?.processName) {
      loadedProcessName.value = String(parsed.processName || '').trim();
    }
    loadedProcessCode.value = processCode.value.trim();
  } catch {
    runtimeDraftDefinitionJson.value = '';
  }
}

const inspectInstanceId = ref('');
const detailLoading = ref(false);
const timelineLoading = ref(false);
const instanceDetail = ref<Record<string, any> | null>(null);
const timelineRows = ref<Array<Record<string, any>>>([]);
const runtimePerfLogs = ref<
  Array<{ at: string; error?: string; ms: number; name: string; ok: boolean }>
>([]);
const SHOW_RUNTIME_PERF_LOG = false;

const todoLoading = ref(false);
const myTodo = ref<WfEngineRuntimeTodoItem | null>(null);
const actionModalOpen = ref(false);
const actionType = ref<'agree' | 'reject'>('agree');
const actionComment = ref('');

async function loadInstanceDetail() {
  const id = inspectInstanceId.value.trim();
  if (!id) return;
  detailLoading.value = true;
  try {
    const data = await profiled('loadInstanceDetail', () =>
      withTimeout(wfEngineRuntimeInstanceDetail(id), 25_000, '加载实例详情'),
    );
    instanceDetail.value = data as unknown as Record<string, any>;
    if ((timelineRows.value || []).length) {
      try {
        await refreshOperatorDisplayCache();
      } catch {
        /* ignore */
      }
    }
  } catch (e) {
    message.error((e as Error)?.message || '加载实例详情失败');
  } finally {
    detailLoading.value = false;
  }
}

async function loadMyTodo() {
  const instId = inspectInstanceId.value.trim();
  if (!instId) {
    myTodo.value = null;
    return;
  }
  todoLoading.value = true;
  try {
    const data = await profiled('loadMyTodo', () =>
      withTimeout(wfEngineRuntimeTodo({ page: 1, pageSize: 100 }), 25_000, '加载我的待办'),
    );
    const items = (data?.items || []) as WfEngineRuntimeTodoItem[];
    const sameInst = (x: WfEngineRuntimeTodoItem) => sameActorOrInstanceId(String(x.instanceId || ''), instId);
    let hits = items.filter(sameInst);
    const curNode = resolvedCurrentNodeId.value.trim();
    if (hits.length > 1 && curNode) {
      const byNode = hits.filter((x) => sameActorOrInstanceId(String(x.nodeId || ''), curNode));
      if (byNode.length) hits = byNode;
    }
    let matched = hits[0] || null;
    if (!matched) {
      matched = pickTodoFromInstanceTasks();
    }
    myTodo.value = matched;
  } catch {
    myTodo.value = pickTodoFromInstanceTasks();
  } finally {
    todoLoading.value = false;
  }
}

async function submitMyAction(type: 'agree' | 'reject') {
  if (!myTodo.value) {
    message.warning('当前登录人不是该实例的办理人，无法提交/驳回');
    return;
  }
  actionType.value = type;
  actionComment.value = '';
  actionModalOpen.value = true;
}

const actionSubmitting = ref(false);

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

function applyBoundFormValuesNonBlocking(values: Record<string, any>, stage: string) {
  Promise.resolve(boundFormApi.setValues(values)).catch((err) => {
    pushRuntimePerfLog(
      `${stage}(setValues-async)`,
      0,
      false,
      (err as Error)?.message || 'setValues 异步失败',
    );
  });
}

function isEmptyRequiredValue(v: unknown): boolean {
  if (v === null || v === undefined) return true;
  if (typeof v === 'string') return v.trim().length === 0;
  if (Array.isArray(v)) return v.length === 0;
  return false;
}

function buildMainFieldLabelMap(schema: VbenFormSchema[]): Record<string, string> {
  const map: Record<string, string> = {};
  for (const item of schema || []) {
    const key = String((item as any)?.fieldName || '').trim();
    if (!key) continue;
    const label = String((item as any)?.label || (item as any)?.fieldLabel || '').trim();
    map[key] = label || key;
  }
  return map;
}

function quoteCnList(values: string[]): string {
  return values.map((x) => `【${x}】`).join('、');
}

function validateRequiredByFieldRulesForViewer(
  fieldRules: Record<string, WfNodeFormFieldRule> | undefined,
  mainForm: Record<string, unknown>,
  tabsData: Record<string, unknown>,
  mainFieldLabelMap?: Record<string, string>,
): { message?: string; missingMainKeys?: string[]; valid: boolean } {
  const missingMain: string[] = [];
  const missingTabs: string[] = [];
  for (const [k, rawRule] of Object.entries(fieldRules || {})) {
    if (normalizeFieldRule(rawRule) !== 'required') continue;
    if (!k.includes('::')) {
      if (isEmptyRequiredValue(mainForm[k])) missingMain.push(k);
      continue;
    }
    const idx = k.indexOf('::');
    if (idx <= 0) continue;
    const tabKey = k.slice(0, idx).trim();
    const colKey = k.slice(idx + 2).trim();
    const rows = Array.isArray(tabsData[tabKey]) ? (tabsData[tabKey] as Array<Record<string, unknown>>) : [];
    if (!rows.length) {
      missingTabs.push(`${tabKey}->${colKey}`);
      continue;
    }
    const missRow = rows.findIndex((r) => isEmptyRequiredValue((r || {})[colKey]));
    if (missRow >= 0) missingTabs.push(`${tabKey}第${missRow + 1}行->${colKey}`);
  }
  if (missingMain.length) {
    const names = missingMain.map((k) => String(mainFieldLabelMap?.[k] || k).trim() || k);
    return {
      valid: false,
      message: `以下字段未填写：${quoteCnList(names)}`,
      missingMainKeys: missingMain,
    };
  }
  if (missingTabs.length) {
    return { valid: false, message: `以下页签必填字段未填写：${missingTabs.join('、')}` };
  }
  return { valid: true };
}

async function collectCurrentFormPayloadForValidation(): Promise<{
  mainForm: Record<string, unknown>;
  tabsData: Record<string, unknown>;
}> {
  // 优先读取当前页面上的实时输入值；读取失败时再回退实例快照，避免误放行。
  try {
    if (layoutIsTabs.value && tabsTablePreviewRef.value?.getWorkflowRuntimePayload) {
      const payload = await tabsTablePreviewRef.value.getWorkflowRuntimePayload();
      return {
        mainForm: (payload?.mainForm || {}) as Record<string, unknown>,
        tabsData: (payload?.tabsData || {}) as Record<string, unknown>,
      };
    }
    const currentMain = ((await boundFormApi.getValues()) || {}) as Record<string, unknown>;
    return {
      mainForm: currentMain,
      tabsData: parseLatestTabsData() as unknown as Record<string, unknown>,
    };
  } catch {
    return {
      mainForm: parseLatestMainForm() as Record<string, unknown>,
      tabsData: parseLatestTabsData() as unknown as Record<string, unknown>,
    };
  }
}

function collectRequiredMainFieldKeysFromRules(
  fieldRules: Record<string, WfNodeFormFieldRule> | undefined,
): string[] {
  const out: string[] = [];
  for (const [k, rawRule] of Object.entries(fieldRules || {})) {
    if (normalizeFieldRule(rawRule) !== 'required') continue;
    const key = String(k || '').trim();
    if (!key || key.includes('::')) continue;
    out.push(key);
  }
  return [...new Set(out)];
}

function collectRequiredMainFieldKeysFromSchema(schema: VbenFormSchema[] = []): string[] {
  const out: string[] = [];
  for (const item of schema || []) {
    const key = String((item as any)?.fieldName || '').trim();
    if (!key) continue;
    if ((item as any)?.hide === true || (item as any)?.ifShow === false) continue;
    if ((item as any)?.required === true) out.push(key);
  }
  return [...new Set(out)];
}

function applyRequiredVisualToSchema(
  schema: VbenFormSchema[],
  requiredKeys: string[],
  missingKeys: string[] = [],
): VbenFormSchema[] {
  const required = new Set((requiredKeys || []).map((k) => String(k || '').trim()).filter(Boolean));
  const missing = new Set((missingKeys || []).map((k) => String(k || '').trim()).filter(Boolean));
  return (schema || []).map((item) => {
    const fieldKey = String((item as any)?.fieldName || '').trim();
    const oldCls = String((item as any)?.formItemClass || '')
      .split(/\s+/)
      .filter(Boolean)
      .filter((x) => x !== 'wf-required-mark')
      .filter((x) => x !== 'wf-required-missing');
    const oldLabelCls = String((item as any)?.labelClass || '')
      .split(/\s+/)
      .filter(Boolean)
      .filter((x) => x !== 'wf-required-label')
      .filter((x) => x !== 'wf-required-missing-label');
    const hasRequired = fieldKey && required.has(fieldKey);
    if (hasRequired) {
      oldCls.push('wf-required-mark');
      oldLabelCls.push('wf-required-label');
    }
    if (fieldKey && missing.has(fieldKey)) {
      oldCls.push('wf-required-missing');
      oldLabelCls.push('wf-required-missing-label');
    }
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
      ...(item as any),
      formItemClass: oldCls.join(' '),
      labelClass: oldLabelCls.join(' '),
      suffix: requiredSuffix,
    } as VbenFormSchema;
  });
}

async function onConfirmAction() {
  if (!myTodo.value) return;
  actionSubmitting.value = true;
  try {
    const currentPayload = await collectCurrentFormPayloadForValidation();
    const mainFieldLabelMap = buildMainFieldLabelMap(formSchema.value as VbenFormSchema[]);
    const requiredByRules = collectRequiredMainFieldKeysFromRules(tabsFieldRulesMap.value);
    const requiredBySchema = collectRequiredMainFieldKeysFromSchema(formSchema.value as VbenFormSchema[]);
    const requiredMainKeys = [...new Set([...requiredByRules, ...requiredBySchema])];
    const missingMainBySchema = requiredMainKeys.filter((k) =>
      isEmptyRequiredValue((currentPayload.mainForm || {})[k]),
    );
    const reqCheck = validateRequiredByFieldRulesForViewer(
      tabsFieldRulesMap.value,
      currentPayload.mainForm,
      currentPayload.tabsData,
      mainFieldLabelMap,
    );
    if (!reqCheck.valid || missingMainBySchema.length > 0) {
      const missingMainKeys = [
        ...new Set([...(reqCheck.missingMainKeys || []), ...missingMainBySchema]),
      ];
      if (formSchema.value.length) {
        formSchema.value = applyRequiredVisualToSchema(
          formSchema.value as VbenFormSchema[],
          requiredMainKeys,
          missingMainKeys,
        );
        if (!layoutIsTabs.value) {
          await boundFormApi.setState(buildBoundFormUiState(formSchema.value as VbenFormSchema[]));
        }
      }
      if (reqCheck.message) {
        message.error(reqCheck.message);
      } else {
        const names = missingMainKeys.map((k) => String(mainFieldLabelMap?.[k] || k).trim() || k);
        message.error(`以下字段未填写：${quoteCnList(names)}`);
      }
      return;
    }
    await withTimeout(
      wfEngineRuntimeCompleteTask({
        taskId: myTodo.value.taskId,
        action: actionType.value,
        comment: actionComment.value.trim() || undefined,
      }),
      25_000,
      actionType.value === 'agree' ? '提交' : '驳回',
    );
    message.success(actionType.value === 'agree' ? '已提交' : '已驳回');
    actionModalOpen.value = false;
    await loadInstanceDetail();
    await loadTimeline();
    await loadMyTodo();
    await loadBoundFormPreview();
  } catch (e) {
    message.error((e as Error)?.message || '操作失败');
  } finally {
    actionSubmitting.value = false;
  }
}

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

async function loadTimeline() {
  const id = inspectInstanceId.value.trim();
  if (!id) return;
  timelineLoading.value = true;
  try {
    timelineRows.value = (await profiled('loadTimeline', () =>
      withTimeout(wfEngineRuntimeInstanceTimeline(id), 25_000, '加载实例轨迹'),
    )) as Array<Record<string, any>>;
    try {
      await refreshOperatorDisplayCache();
    } catch {
      /* 解析失败时仍展示轨迹原文 */
    }
  } catch (e) {
    message.error((e as Error)?.message || '加载实例轨迹失败');
  } finally {
    timelineLoading.value = false;
  }
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
      (inst as any).process_def_id ??
      (inst as any).processDefId ??
      (inst as any).ProcessDefId;
    pid = String(raw ?? '').trim();
  }
  if (!pid) return;
  try {
    const proc = await profiled('ensureRuntimeDefinitionJson', () =>
      withTimeout(wfEngineGetProcess(pid), 25_000, '加载流程定义'),
    );
    const dj = String((proc as { version?: { definitionJson?: string } })?.version?.definitionJson ?? '').trim();
    if (dj) runtimeDefinitionJson.value = dj;
    const pn = String((proc as any)?.processDef?.processName ?? '').trim();
    const pc = String((proc as any)?.processDef?.processCode ?? '').trim();
    if (pn) loadedProcessName.value = pn;
    if (pc) loadedProcessCode.value = pc;
  } catch (e) {
    message.error((e as Error)?.message || '加载流程定义失败');
  }
}

const runtimeNodeList = computed(() => parseWorkflowGraphNodes(runtimeDefinitionJson.value));
const runtimeEndNodeId = computed(() => resolveEndNodeId(runtimeDefinitionJson.value));
const runtimeNodeNameMap = computed(() => {
  const map: Record<string, string> = {};
  for (const n of runtimeNodeList.value) {
    const id = String(n.id || '').trim();
    const title = String(n.title || '').trim();
    if (id) map[id] = title || id;
  }
  return map;
});

const resolvedCurrentNodeId = computed(() => {
  const tasks = (instanceDetail.value?.tasks as Array<Record<string, any>> | undefined) || [];
  const pending = tasks.find((x) => Number((x as any)?.status ?? (x as any)?.status_num ?? -1) === 0);
  if (pending) {
    const nid = String((pending as any)?.node_id ?? (pending as any)?.nodeId ?? '').trim();
    if (nid) return nid;
  }
  const endNodeId = runtimeEndNodeId.value.trim();
  const instStatus = Number((instanceDetail.value as any)?.instance?.status ?? -1);
  const latestNodeId = String(
    (instanceDetail.value as any)?.latestData?.node_id ?? (instanceDetail.value as any)?.latestData?.nodeId ?? '',
  ).trim();
  const tailAction = String((timelineRows.value.at(-1) as any)?.action_type ?? '')
    .trim()
    .toLowerCase();
  if (
    endNodeId &&
    !pending &&
    ((instStatus === 1 || instStatus === 2) ||
      ((tailAction === 'approve' || tailAction === 'agree') &&
        latestNodeId &&
        latestNodeId !== endNodeId &&
        hasEdgeToNode(runtimeDefinitionJson.value, latestNodeId, endNodeId)))
  ) {
    return endNodeId;
  }
  if (latestNodeId) return latestNodeId;
  const raw = (instanceDetail.value as any)?.instance?.current_node_ids;
  if (!raw) return '';
  return String(raw).split(',')[0].trim();
});

const businessDataColumns = [
  { title: '字段', dataIndex: 'field', key: 'field', width: 220 },
  { title: '值', dataIndex: 'value', key: 'value' },
];
const businessDataRows = computed(() => {
  const o = coerceLatestMainForm((instanceDetail.value as any)?.latestData);
  if (!o || !Object.keys(o).length) return [] as Array<{ field: string; value: string }>;
  return Object.entries(o).map(([field, value]) => ({
    field,
    value: typeof value === 'object' ? JSON.stringify(value) : String(value ?? ''),
  }));
});

function isLikelyGuidStr(s: string): boolean {
  const t = String(s || '').trim();
  if (!t) return false;
  const unbrace = t.startsWith('{') && t.endsWith('}') ? t.slice(1, -1) : t;
  return /^[\da-f]{8}-[\da-f]{4}-[1-5][\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i.test(unbrace);
}

function pickStringByKeys(source: null | Record<string, any> | undefined, keys: string[]): string {
  if (!source) return '';
  for (const k of keys) {
    const v = source[k];
    if (v !== undefined && v !== null && String(v).trim()) return String(v).trim();
  }
  return '';
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

const headerMainForm = computed<Record<string, any>>(() => parseLatestMainForm());
const headerFlowNo = computed(
  () =>
    String((instanceDetail.value?.instance as any)?.business_key || '').trim() ||
    String((instanceDetail.value?.instance as any)?.businessKey || '').trim() ||
    String((instanceDetail.value?.instance as any)?.instance_no || '').trim() ||
    extractFlowNoFromObject(headerMainForm.value) ||
    '—',
);
const headerStarter = computed(() => {
  const inst = (instanceDetail.value?.instance || {}) as Record<string, any>;
  const form = headerMainForm.value || {};
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
const headerEmployeeNo = computed(() => {
  const inst = (instanceDetail.value?.instance || {}) as Record<string, any>;
  const form = headerMainForm.value || {};
  const v =
    pickStringByKeys(form, ['EMP_ID', 'employeeNo', 'employeeCode', 'empNo', 'workNo', '工号']) ||
    pickStringByKeys(inst, ['starter_emp_id', 'starterEmpId', 'starter_user_id']);
  return !v || isLikelyGuidStr(v) ? '—' : v;
});
const headerDept = computed(
  () =>
    pickStringByKeys(headerMainForm.value, [
      'long_name',
      'deptName',
      'departmentName',
      'department',
      'dept',
      '部门',
    ]) || '—',
);
const headerPosition = computed(
  () =>
    pickStringByKeys(headerMainForm.value, [
      'positionName',
      'dutyName',
      'postName',
      'position',
      'post',
      '岗位',
      '职位',
    ]) ||
    pickStringByKeys((userStore.userInfo || {}) as Record<string, any>, [
      'positionName',
      'dutyName',
      'postName',
      'position',
      'post',
      'title',
      'jobTitle',
      'JobTitle',
      '岗位',
    ]) ||
    '—',
);
const headerStartTime = computed(() => {
  const raw =
    (instanceDetail.value?.instance as any)?.started_at ||
    (instanceDetail.value?.instance as any)?.startedAt;
  return raw ? new Date(raw).toLocaleString() : '—';
});
const currentLoginName = computed(() => {
  const u = (userStore.userInfo || {}) as Record<string, any>;
  return (
    pickStringByKeys(u, [
      'realName',
      'name',
      'displayName',
      'nickName',
      'username',
      'userName',
      'account',
    ]) || '—'
  );
});
const currentLoginEmpNo = computed(() => {
  const u = (userStore.userInfo || {}) as Record<string, any>;
  const v = pickStringByKeys(u, [
    'employeeCode',
    'employeeNo',
    'workNo',
    'jobNo',
    'empNo',
    'EMP_ID',
    '工号',
  ]);
  return !v || isLikelyGuidStr(v) ? '—' : v;
});
const effectiveActorName = computed(() => {
  const mockName = String(route.query.mockAssigneeName || '').trim();
  if (mockName) return mockName;
  return currentLoginName.value;
});
const effectiveActorEmpNo = computed(() => {
  const mockEmpNo = String(route.query.mockAssigneeEmpNo || '').trim();
  if (mockEmpNo && !isLikelyGuidStr(mockEmpNo)) return mockEmpNo;
  return currentLoginEmpNo.value;
});
const mobileHeaderRows = computed(() => [
  { key: 'flowNo', label: '流程编号', value: headerFlowNo.value },
  { key: 'processName', label: '流程名称', value: instanceDetail.value?.process?.process_name || loadedProcessName.value || '—' },
  { key: 'starter', label: '发起人', value: headerStarter.value },
  { key: 'startTime', label: '发起时间', value: headerStartTime.value },
  { key: 'employeeNo', label: '工号', value: headerEmployeeNo.value },
  { key: 'dept', label: '部门', value: headerDept.value },
  { key: 'position', label: '岗位', value: headerPosition.value },
  { key: 'status', label: '当前状态', value: instanceMetaStatus.value.text, isStatus: true, statusColor: instanceMetaStatus.value.color },
  { key: 'node', label: '当前节点', value: runtimeNodeNameMap.value[resolvedCurrentNodeId.value] || resolvedCurrentNodeId.value || '—' },
]);

// --- 表单真实预览（只读） ---
const formLoading = ref(false);
const boundFormMode = ref<'none' | 'designer' | 'ext' | 'snapshot'>('none');
const boundFormHint = ref('');
const formSchema = ref<VbenFormSchema[]>([]);
const extRuntimeRoot = shallowRef<VueConcreteComponent | null>(null);
const layoutIsTabs = ref(false);
const tabsConfig = ref<TabTableConfig[]>([]);
const tabsInitialMainValues = ref<Record<string, any>>({});
const tabsFieldRulesMap = ref<Record<string, WfNodeFormFieldRule>>({});
const tabsTablePreviewRef = ref<InstanceType<typeof FormTabsTablePreview> | null>(null);

const [BoundForm, boundFormApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as VbenFormSchema[],
  wrapperClass: 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
  layout: 'horizontal',
  formItemGapPx: 2 as any,
  commonConfig: { labelWidth: 110 } as any,
});

function buildBoundFormUiState(schema: VbenFormSchema[] = [] as VbenFormSchema[]) {
  const mob = isMobilePreviewMode.value;
  return {
    schema,
    layout: mob ? 'vertical' : 'horizontal',
    wrapperClass: mob ? 'grid-cols-1 gap-y-2' : 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
    commonConfig: mob ? ({ labelWidth: 78 } as any) : ({ labelWidth: 110 } as any),
  } as const;
}

watch(
  isMobilePreviewMode,
  async (mob) => {
    await boundFormApi.setState(buildBoundFormUiState());
  },
  { immediate: true },
);

function parseLatestMainForm() {
  return coerceLatestMainForm((instanceDetail.value as any)?.latestData);
}

function parseLatestTabsData() {
  return coerceLatestTabsData((instanceDetail.value as any)?.latestData);
}

async function loadBoundFormPreview() {
  const instId = inspectInstanceId.value.trim();
  const nodeId = resolvedCurrentNodeId.value.trim();
  if (!instId) return;
  if (!nodeId) {
    boundFormMode.value = 'snapshot';
    boundFormHint.value = '未解析到当前节点，已展示主表快照。';
    return;
  }
  const perfStart = performance.now();
  formLoading.value = true;
  try {
    extRuntimeRoot.value = null;
    formSchema.value = [];
    layoutIsTabs.value = false;
    tabsConfig.value = [];
    tabsFieldRulesMap.value = {};
    tabsInitialMainValues.value = {};

    await ensureRuntimeDefinitionJson();
    const defJson = runtimeDefinitionJson.value.trim();
    if (!defJson) {
      boundFormMode.value = 'snapshot';
      boundFormHint.value = '未加载到流程定义，已展示主表快照。';
      return;
    }
    const { binding, usedStartFallback, nodeFoundInGraph } = resolveNodeFormBindingWithStartFallback(
      defJson,
      nodeId,
    );
    if (!binding) {
      const knownIds = runtimeNodeList.value.map((n) => String(n.id || '').trim()).filter(Boolean);
      const inDefinition = knownIds.includes(String(nodeId || '').trim());
      boundFormMode.value = 'snapshot';
      if (!nodeFoundInGraph) {
        boundFormHint.value = `节点未绑定表单，已展示主表快照。（nodeId=${nodeId}；定义中${inDefinition ? '存在该节点' : '找不到该节点'}）`;
      } else {
        boundFormHint.value = `当前节点与发起节点均未绑定表单，已展示主表快照。（nodeId=${nodeId}）`;
      }
      return;
    }
    if (binding.formSource === 'ext' && binding.extFormKey) {
      const comp = createExtWorkflowFormComponent(binding.extFormKey);
      if (!comp) {
        boundFormMode.value = 'snapshot';
        boundFormHint.value = `硬编码表单加载失败：${binding.extFormKey}`;
        return;
      }
      boundFormMode.value = 'ext';
      extRuntimeRoot.value = comp as any;
      boundFormHint.value = `当前节点硬编码表单：${binding.formName || binding.extFormKey}`;
      await withTimeout(
        boundFormApi.setState(buildBoundFormUiState([] as VbenFormSchema[])),
        12_000,
        '渲染硬编码表单(setState)',
      );
      applyBoundFormValuesNonBlocking({}, '渲染硬编码表单');
      return;
    }
    const formCode = String(binding.formCode || '').trim();
    if (!formCode) {
      boundFormMode.value = 'snapshot';
      boundFormHint.value = '节点绑定表单编码为空，已展示主表快照。';
      return;
    }
    const rec = await withTimeout(
      getWorkflowFormSchemaByCode(formCode),
      20_000,
      '加载表单设计器定义',
    );
    const schemaJson = String(rec?.schemaJson || '').trim();
    if (!schemaJson) {
      boundFormMode.value = 'snapshot';
      boundFormHint.value = `未找到表单设计器定义：${formCode}`;
      return;
    }
    const parsed = parseStoredFormSchemaJson(schemaJson);
    if (!parsed) {
      boundFormMode.value = 'snapshot';
      boundFormHint.value = `表单 schema 解析失败：${formCode}`;
      return;
    }
    const normalized = normalizeSchemaForPreview(parsed.srcSchema);
    const decorated = applyFieldRulesToSchemaPlain(normalized, binding.fieldRules || {});
    const requiredMainKeys = collectRequiredMainFieldKeysFromRules(binding.fieldRules || {});
    formSchema.value = applyRequiredVisualToSchema(
      decorated as VbenFormSchema[],
      requiredMainKeys,
    );
    boundFormMode.value = 'designer';

    const layoutTabsFlag = !!(parsed.layoutIsTabs && parsed.tabs?.length);
    layoutIsTabs.value = layoutTabsFlag;
    tabsConfig.value = layoutTabsFlag ? (jsonSafeClone(parsed.tabs) as TabTableConfig[]) : [];
    tabsFieldRulesMap.value = ((binding.fieldRules || {}) as Record<string, WfNodeFormFieldRule>);

    const builtins = buildWorkflowBuiltinValuesFromUser(formSchema.value as VbenFormSchema[], {
      userInfo: userStore.userInfo as any,
      workflowNoPrefix: parsed.workflowNoPrefix || binding.workflowNoPrefix,
    });
    const latest = parseLatestMainForm();
    const mergedMain = { ...builtins, ...latest };
    tabsInitialMainValues.value = mergedMain;

    if (layoutTabsFlag) {
      await withTimeout(
        boundFormApi.setState(buildBoundFormUiState([] as VbenFormSchema[])),
        12_000,
        '渲染页签表单(setState)',
      );
      applyBoundFormValuesNonBlocking({}, '渲染页签表单');
      await nextTick();
      tabsTablePreviewRef.value?.loadTabsDataFromObject?.(parseLatestTabsData());
    } else {
      await withTimeout(
        boundFormApi.setState(buildBoundFormUiState(formSchema.value as VbenFormSchema[])),
        12_000,
        '渲染节点表单(setState)',
      );
      await nextTick();
      applyBoundFormValuesNonBlocking(mergedMain as Record<string, any>, '渲染节点表单');
    }
    boundFormHint.value = `${usedStartFallback ? '本节点未单独绑定表单，已沿用发起节点表单｜' : ''}${
      layoutTabsFlag
        ? `当前节点「上表+页签表格」：${binding.formName || formCode}`
        : `当前节点绑定表单：${binding.formName || formCode}`
    }`;
    pushRuntimePerfLog('loadBoundFormPreview', performance.now() - perfStart, true);
  } catch (e) {
    boundFormMode.value = 'snapshot';
    boundFormHint.value = `加载节点表单失败：${(e as Error).message}`;
    pushRuntimePerfLog(
      'loadBoundFormPreview',
      performance.now() - perfStart,
      false,
      (e as Error)?.message || '加载节点表单失败',
    );
  } finally {
    formLoading.value = false;
  }
}

// --- 审批记录（沿用运行台的“节点卡片”展示） ---
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
  const rows = (timelineRows.value || []) as Array<Record<string, any>>;
  const start = currentRoundStartMs.value;
  if (!Number.isFinite(start)) return rows;
  return rows.filter((r) => {
    const t = toTimeMs(r?.action_at);
    return !Number.isFinite(t) || t >= start;
  });
});

const timelineNodeCards = computed(() => {
  const dm = operatorDisplayMap.value;
  const nodes = runtimeNodeList.value;
  const allRows = (timelineRows.value || []) as Array<Record<string, any>>;
  const rows = timelineRowsCurrentRound.value as Array<Record<string, any>>;
  const roundStart = currentRoundStartMs.value;
  const tasks = ((instanceDetail.value?.tasks as Array<Record<string, any>>) || [])
    .map((t) => ({
      ...t,
      nodeId: String((t as any).node_id ?? (t as any).nodeId ?? '').trim(),
      statusNum: Number((t as any).status ?? -1),
    }))
    .filter((t) => {
      if (t.statusNum === 0) return true;
      if (!Number.isFinite(roundStart)) return true;
      const received = toTimeMs((t as any).received_at ?? (t as any).receivedAt);
      const completed = toTimeMs((t as any).completed_at ?? (t as any).completedAt);
      return (
        (Number.isFinite(received) && received >= roundStart) ||
        (Number.isFinite(completed) && completed >= roundStart)
      );
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

  function statusFromRow(r: Record<string, any> | undefined) {
    const action = String(r?.action_type || '').trim().toLowerCase();
    const res = String(r?.action_result || '').trim().toLowerCase();
    if (action === 'reject' || res === 'reject') return '已驳回';
    if (action === 'submit' || res === 'submitted') return '已提交';
    if (action === 'approve' || action === 'agree' || res === 'agree') return '已通过';
    if (action === 'withdraw' || res === 'withdraw') return '已撤回';
    return '待处理';
  }

  const cards = nodes.map((n, idx) => {
    const nodeRowsAll = byNodeAll.get(n.id) || [];
    const nodeRows = byNode.get(n.id) || [];
    const nodeTasks = tasksByNode.get(n.id) || [];
    const latestDecision = nodeRows.length ? nodeRows[nodeRows.length - 1] : undefined;
    const latest = latestDecision || (nodeRowsAll.length ? nodeRowsAll[nodeRowsAll.length - 1] : undefined);
    const viewed = nodeRowsAll.some((r) => {
      const v = r?.view_trace;
      if (v === null || v === undefined) return false;
      return Boolean(v);
    });
    const pendingTask = nodeTasks.find((t) => Number(t.statusNum) === 0);
    const passedTask = nodeTasks.find((t) => Number(t.statusNum) === 2);
    const rejectedTask = nodeTasks.find((t) => Number(t.statusNum) === 3);
    const canceledTask = nodeTasks.find((t) => Number(t.statusNum) === 4);
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
      (latest as any)?.action_at ??
      (pendingTask as any)?.received_at ??
      (pendingTask as any)?.receivedAt ??
      (passedTask as any)?.completed_at ??
      (passedTask as any)?.completedAt;
    const when = whenRaw ? new Date(whenRaw).toLocaleString() : '—';
    const actor = resolveActorFromLatestAndPending(dm, latest as any, pendingTask as any);
    const comment = String((latestDecision as any)?.comment || '').trim();
    const rejectRowsAll = nodeRowsAll.filter((r) => {
      const a = String(r.action_type || '').trim().toLowerCase();
      const res = String(r.action_result || '').trim().toLowerCase();
      return a === 'reject' || res === 'reject';
    });
    const latestReject = rejectRowsAll.length ? rejectRowsAll[rejectRowsAll.length - 1] : undefined;
    const latestRejectWhen = (latestReject as any)?.action_at
      ? new Date((latestReject as any).action_at).toLocaleString()
      : '';
    const latestRejectActorRaw = formatOperatorLabel(
      dm,
      (latestReject as any)?.operator_name,
      (latestReject as any)?.operator_user_id,
    );
    const latestRejectActor = latestRejectActorRaw === '—' ? '' : latestRejectActorRaw;
    const latestRejectComment = String((latestReject as any)?.comment || '').trim();
    const historyRejectText = latestReject
      ? `历史驳回 ${rejectRowsAll.length} 次（最近：${latestRejectWhen || '—'}${
          latestRejectActor ? `，${latestRejectActor}` : ''
        }${latestRejectComment ? `，意见：${latestRejectComment}` : ''}）`
      : '';

    const whenSortMs = toTimeMs(whenRaw);
    const endLike = /结束|完成/.test(String(n.title || n.id || ''));
    const sortKey = Number.isFinite(whenSortMs)
      ? whenSortMs
      : endLike
        ? 1e16
        : reached
          ? 8e15 + idx
          : 9e15 + idx;

    return {
      nodeId: n.id,
      nodeName: n.title || n.id,
      reached,
      when,
      actor,
      statusText,
      sortKey,
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
  return [...cards].sort((a, b) => {
    const d = (a.sortKey ?? 0) - (b.sortKey ?? 0);
    if (d !== 0) return d;
    return String(a.nodeId).localeCompare(String(b.nodeId));
  });
});

const instanceMetaStatus = computed(() => {
  const st = Number((instanceDetail.value as any)?.instance?.status ?? -1);
  if (st === 2) return { text: '已完成', color: 'success' };
  if (st === 3) return { text: '已驳回', color: 'error' };
  if (st === 4) return { text: '已撤回', color: 'default' };
  return { text: '运行中', color: 'processing' };
});

async function hydrate() {
  runtimePerfLogs.value = [];
  const mockAid = String(route.query.mockAssigneeUserId || '').trim();
  setWorkflowRuntimeMockAssigneeUserId(mockAid);
  inspectInstanceId.value = String(route.query.instanceId || '').trim();
  processDefId.value = String(route.query.processDefId || '').trim();
  processCode.value = String(route.query.processCode || '').trim();
  runtimeDraftKey.value = String(route.query.runtimeDraftKey || '').trim();
  applyRuntimeDraftByKey(runtimeDraftKey.value);
  if (!inspectInstanceId.value.trim()) {
    message.warning('请在地址栏传 instanceId');
    return;
  }
  await Promise.all([loadInstanceDetail(), loadTimeline(), ensureUserInfoForRuntimeViewer()]);
  await Promise.all([loadMyTodo(), ensureRuntimeDefinitionJson()]);
  await loadBoundFormPreview();
}

watch(
  () => route.fullPath,
  async () => {
    await hydrate();
  },
  { immediate: true },
);

watch(
  () =>
    [
      resolvedCurrentNodeId.value,
      runtimeDefinitionJson.value,
      inspectInstanceId.value,
      (instanceDetail.value as any)?.latestData?.node_id,
      (instanceDetail.value as any)?.latestData?.nodeId,
    ] as const,
  async () => {
    if (!inspectInstanceId.value.trim()) return;
    await loadMyTodo();
    await loadBoundFormPreview();
  },
);
</script>

<template>
  <div class="wf-viewer-page">
    <ProcessPreviewShell :frame="isMobilePreviewMode">
      <div
        class="wf-viewer-root flex flex-col gap-2"
        :class="isMobilePreviewMode ? 'wf-mobile-single gap-3' : 'p-2'"
      >
      <Card size="small" :title="loadedProcessName || '流程'">
        <template #extra>
          <Space>
            <span class="text-muted-foreground text-xs md:text-sm">
              当前办理身份：{{ effectiveActorName }}（{{ effectiveActorEmpNo }}）
            </span>
            <Button
              type="primary"
              :loading="todoLoading || actionSubmitting"
              :disabled="!myTodo"
              @click="submitMyAction('agree')"
            >
              提交
            </Button>
            <Button
              danger
              :loading="todoLoading || actionSubmitting"
              :disabled="!myTodo"
              @click="submitMyAction('reject')"
            >
              驳回
            </Button>
          </Space>
        </template>
        <div
          v-if="isMobilePreviewMode"
          class="mb-3 divide-border/55 flex flex-col divide-y text-sm"
        >
          <div
            v-for="r in mobileHeaderRows"
            :key="r.key"
            class="flex flex-col gap-1 py-3 first:pt-1 last:pb-1"
          >
            <span class="text-muted-foreground text-[11px] leading-tight">{{ r.label }}</span>
            <Tag v-if="r.isStatus" :color="r.statusColor || 'processing'" class="w-fit">
              {{ r.value }}
            </Tag>
            <div v-else class="break-words text-[13px] leading-snug">{{ r.value }}</div>
          </div>
        </div>
        <div v-else class="mb-3 grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
          <div>
            <span class="text-muted-foreground">流程编号：</span>
            {{ headerFlowNo }}
          </div>
          <div>
            <span class="text-muted-foreground">流程名称：</span>
            {{ instanceDetail?.process?.process_name || loadedProcessName || '—' }}
          </div>
          <div>
            <span class="text-muted-foreground">发起人：</span>
            {{ headerStarter }}
          </div>
          <div>
            <span class="text-muted-foreground">发起时间：</span>
            {{ headerStartTime }}
          </div>
          <div>
            <span class="text-muted-foreground">工号：</span>
            {{ headerEmployeeNo }}
          </div>
          <div>
            <span class="text-muted-foreground">部门：</span>
            {{ headerDept }}
          </div>
          <div>
            <span class="text-muted-foreground">岗位：</span>
            {{ headerPosition }}
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

        <div class="border-border border-t pt-1">
          <div class="wf-viewer-form-tight">
            <div v-if="formLoading" class="text-muted-foreground py-2 text-center text-sm">表单加载中…</div>
          <div
            v-else-if="
              boundFormMode === 'designer' &&
              formSchema.length > 0 &&
              layoutIsTabs &&
              tabsConfig.length
            "
          >
            <FormTabsTablePreview
              ref="tabsTablePreviewRef"
              :form-schema="(formSchema as any)"
              :tabs="tabsConfig"
              :field-rules-map="tabsFieldRulesMap"
              :show-form="true"
              :grid-height="120"
              :compact="true"
              :hide-single-tab-nav="isMobilePreviewMode ? true : false"
              :wrapper-class="
                isMobilePreviewMode ? 'grid-cols-1 gap-y-2' : 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]'
              "
              :layout="isMobilePreviewMode ? 'vertical' : 'horizontal'"
              :label-width="isMobilePreviewMode ? 88 : 110"
              :initial-main-form-values="tabsInitialMainValues"
            />
          </div>
          <div v-else-if="boundFormMode === 'designer' && formSchema.length > 0">
            <BoundForm />
          </div>
          <div v-else-if="boundFormMode === 'ext'">
            <component v-if="extRuntimeRoot" :is="extRuntimeRoot" />
            <div v-else class="text-muted-foreground py-2 text-center text-sm">表单加载中…</div>
          </div>
          <div v-else-if="boundFormMode === 'snapshot' && businessDataRows.length">
            <div class="mb-2 text-sm font-medium">业务数据（主表快照）</div>
            <Table
              :columns="businessDataColumns"
              :data-source="businessDataRows"
              :pagination="false"
              row-key="field"
              size="small"
            />
          </div>
          <div v-else class="text-muted-foreground text-xs">暂无数据</div>
          </div>
        </div>
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
              :height="280"
              :fit-padding-x="40"
              :fit-padding-y="32"
            />
            <div v-else class="text-muted-foreground text-sm">未加载到流程定义</div>
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
                      <span class="text-muted-foreground">时间：</span>
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
              {{ timelineLoading ? '加载中…' : '暂无记录' }}
            </div>
          </Tabs.TabPane>
        </Tabs>
      </Card>
      </div>
    </ProcessPreviewShell>
    <Modal
      v-model:open="actionModalOpen"
      :title="actionType === 'agree' ? '提交' : '驳回'"
      :confirm-loading="actionSubmitting"
      @ok="onConfirmAction"
    >
      <Input.TextArea
        v-model:value="actionComment"
        :rows="4"
        :placeholder="actionType === 'agree' ? '意见（可选）' : '原因（建议填写）'"
      />
    </Modal>
  </div>
</template>

<style scoped>
.wf-viewer-root :deep(.ant-card-body) {
  padding: 10px !important;
}

.wf-viewer-tabs-card :deep(.ant-card-body) {
  padding-top: 6px !important;
}

.wf-viewer-tabs-card :deep(.ant-tabs-nav) {
  margin: 0 0 6px 0 !important;
}

.wf-viewer-form-tight {
  padding-top: 5px;
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

.wf-viewer-form-tight :deep(.wf-required-inline-star) {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 10px;
  color: #ff4d4f;
  font-size: 14px;
  font-weight: 700;
  line-height: 1;
}

.wf-viewer-form-tight :deep(.wf-required-mark .ant-form-item-control-input-content) {
  position: relative;
  overflow: visible !important;
}

.wf-viewer-form-tight :deep(.wf-required-missing .ant-input),
.wf-viewer-form-tight :deep(.wf-required-missing .ant-input-affix-wrapper),
.wf-viewer-form-tight :deep(.wf-required-missing .ant-select-selector),
.wf-viewer-form-tight :deep(.wf-required-missing .ant-picker),
.wf-viewer-form-tight :deep(.wf-required-missing .ant-input-number),
.wf-viewer-form-tight :deep(.wf-required-missing textarea.ant-input) {
  border-color: #ff4d4f !important;
  box-shadow: 0 0 0 2px rgba(255, 77, 79, 0.12) !important;
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

/* 让页签表格区域更紧凑 */
.wf-viewer-form-tight :deep(.ant-table) {
  margin-top: 5px !important;
}

.wf-viewer-form-tight :deep(.ant-table-container) {
  border-radius: 6px;
}

/* 移动端预览兜底：强制所有表单网格单列，避免 md:grid-cols-2 在大窗口下仍生效 */
.wf-mobile-single :deep(.md\:grid-cols-2),
.wf-mobile-single :deep(.grid-cols-2) {
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
