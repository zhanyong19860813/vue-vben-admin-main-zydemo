<script setup lang="ts">
import type { Component as VueConcreteComponent } from 'vue';
import { computed, nextTick, ref, shallowRef, watch } from 'vue';
import { useRoute } from 'vue-router';

import { useAccessStore, useUserStore } from '@vben/stores';
import type { VbenFormSchema } from '#/adapter/form';
import type { WfNodeFormFieldRule } from '#/views/demos/workflow-designer/workflow-definition.schema';
import { useVbenForm } from '#/adapter/form';
import { buildWorkflowBuiltinValuesFromUser } from '#/views/demos/form-designer/workflowFormRuntime';
import type { TabTableConfig } from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import {
  coerceLatestMainForm,
  coerceLatestTabsData,
  jsonSafeClone,
  resolveNodeFormBindingWithStartFallback,
} from '#/views/workflow/wfFormPreviewUtils';
import { hasEdgeToNode, parseWorkflowGraphNodes, resolveEndNodeId } from './runtimeViewerGraph';
import {
  buildMainFieldLabelMap,
  collectRequiredMainFieldKeysFromSchema,
  collectRequiredMainFieldKeysFromRules,
  isEmptyRequiredValue,
  quoteCnList,
} from './runtimeViewerValidation';
import { withTimeout } from './runtimeViewerData';
import { applyRequiredVisualToSchema } from './runtimeViewerUi';
import { getWorkflowFormSchemaByCode } from './runtimeViewerFormSchemaRepo';
import { sameActorOrInstanceId } from './runtimeViewerIdentity';
import { collectActorIdCandidates, pickTodoFromInstanceTasks } from './runtimeViewerTodoHelpers';
import { buildTimelineNodeCards } from './runtimeViewerTimelineModel';
import { setupRuntimeViewerHydration } from './runtimeViewerHydrate';
import { buildDesignerFormPreview } from './runtimeViewerFormPreviewBuilder';
import { tryApplyExtFormPreview } from './runtimeViewerExtForm';
import {
  buildMobileHeaderRows,
  extractFlowNoFromObject,
  resolveHeaderDept,
  resolveHeaderEmployeeNo,
  resolveHeaderFlowNo,
  resolveHeaderPosition,
  resolveHeaderStartTime,
  resolveHeaderStarter,
} from './runtimeViewerHeaderModel';
import { isLikelyGuidStr, pickStringByKeys } from './runtimeViewerCommon';
import {
  computeCurrentRoundStartMs,
  filterTimelineRowsCurrentRound,
  resolveRuntimeStartNodeId,
} from './runtimeViewerTimelineRound';
import { applyRuntimeDraftByKey as applyRuntimeDraftByKeyCore } from './runtimeViewerDraft';
import { applyDesignerRender } from './runtimeViewerDesignerRender';
import { ensureRuntimeDefinitionJson as ensureRuntimeDefinitionJsonCore } from './runtimeViewerDefinition';
import { resolveCurrentNodeId } from './runtimeViewerNodeResolver';
import { mapBusinessDataRows } from './runtimeViewerBusinessData';
import { loadBoundFormPreviewCore } from './runtimeViewerBoundFormLoader';
import {
  buildBoundFormUiStateByMode,
  parseLatestMainFormFromDetail,
  parseLatestTabsDataFromDetail,
} from './runtimeViewerFormState';
import {
  resolveCurrentLoginEmpNo,
  resolveCurrentLoginName,
  resolveEffectiveActorEmpNo,
  resolveEffectiveActorName,
} from './runtimeViewerActor';
import {
  applyBoundFormValuesNonBlocking as applyBoundFormValuesNonBlockingCore,
  profiled as profiledCore,
  pushRuntimePerfLog as pushRuntimePerfLogCore,
} from './runtimeViewerPerf';
import {
  collectEmployeeIdsForDisplay,
  fetchEmployeeDisplayLabelsByIds,
} from '#/views/workflow/workflowOperatorDisplay';

import { message } from 'ant-design-vue';

import ProcessPreviewShell from '#/views/workflow/process-preview/ProcessPreviewShell.vue';
import RuntimeViewerTimelinePanel from './RuntimeViewerTimelinePanel.vue';
import RuntimeViewerMainCard from './RuntimeViewerMainCard.vue';
import { collectRuntimePayloadFromFormHost } from '#/views/workflow/shared/runtimeFormHostPayload';
import { validateRequiredByFieldRules } from '../runtime/form/runtimeWorkflowValidation';
import { submitRuntimeTaskAction } from '../runtime/domain/runtimeWorkflowTaskSubmit';

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

function collectActorCandidatesForTodo(): string[] {
  return collectActorIdCandidates({
    accessToken: accessStore.accessToken || '',
    mockAssigneeUserId: route.query.mockAssigneeUserId,
    userInfo: (userStore.userInfo || {}) as Record<string, any>,
  });
}

const runtimeDraftKey = ref('');
const runtimeDraftDefinitionJson = ref('');
const runtimeDefinitionJson = ref('');
const processDefId = ref('');
const processCode = ref('');
const loadedProcessName = ref('');
const loadedProcessCode = ref('');

function applyRuntimeDraftByKey(key: string) {
  applyRuntimeDraftByKeyCore({
    key,
    runtimeDraftDefinitionJson,
    runtimeDefinitionJson,
    processCode,
    loadedProcessName,
    loadedProcessCode,
  });
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
const DEBUG_VIEWER = true;
const viewerDebugInfo = ref<Record<string, any>>({});

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
      matched = pickTodoFromInstanceTasks({
        actorCandidates: collectActorCandidatesForTodo(),
        currentNodeId: resolvedCurrentNodeId.value.trim(),
        inspectInstanceId: inspectInstanceId.value,
        instanceDetail: instanceDetail.value,
      });
    }
    myTodo.value = matched;
  } catch {
    myTodo.value = pickTodoFromInstanceTasks({
      actorCandidates: collectActorCandidatesForTodo(),
      currentNodeId: resolvedCurrentNodeId.value.trim(),
      inspectInstanceId: inspectInstanceId.value,
      instanceDetail: instanceDetail.value,
    });
  } finally {
    todoLoading.value = false;
  }
}

const actionSubmitting = ref(false);

function pushRuntimePerfLog(name: string, ms: number, ok: boolean, error?: string) {
  pushRuntimePerfLogCore(runtimePerfLogs, name, ms, ok, error);
}

async function profiled<T>(name: string, fn: () => Promise<T>): Promise<T> {
  return await profiledCore(runtimePerfLogs, name, fn);
}

function applyBoundFormValuesNonBlocking(values: Record<string, any>, stage: string) {
  applyBoundFormValuesNonBlockingCore(boundFormApi as any, runtimePerfLogs, values, stage);
}

async function applyViewerRequiredVisual(missingKeys: string[]) {
  const requiredByRules = collectRequiredMainFieldKeysFromRules(tabsFieldRulesMap.value);
  const requiredBySchema = collectRequiredMainFieldKeysFromSchema(formSchema.value as VbenFormSchema[]);
  const requiredMainKeys = [...new Set([...requiredByRules, ...requiredBySchema])];
  if (!formSchema.value.length) return;
  formSchema.value = applyRequiredVisualToSchema(
    formSchema.value as VbenFormSchema[],
    requiredMainKeys,
    missingKeys || [],
  );
  if (!layoutIsTabs.value) {
    await boundFormApi.setState(buildBoundFormUiState(formSchema.value as VbenFormSchema[]));
  }
}

function validateViewerRequired(
  fieldRules: Record<string, WfNodeFormFieldRule> | undefined,
  mainForm: Record<string, unknown> | undefined,
  tabsData?: Record<string, unknown>,
  mainFieldLabelMap?: Record<string, string>,
) {
  const base = validateRequiredByFieldRules(fieldRules, mainForm, tabsData, mainFieldLabelMap);
  const requiredBySchema = collectRequiredMainFieldKeysFromSchema(formSchema.value as VbenFormSchema[]);
  const schemaMissing = requiredBySchema.filter((k) => isEmptyRequiredValue((mainForm || {})[k]));
  if (!base.valid || schemaMissing.length > 0) {
    const missingMainKeys = [...new Set([...(base.missingMainKeys || []), ...schemaMissing])];
    const names = missingMainKeys.map((k) => String(mainFieldLabelMap?.[k] || k).trim() || k);
    return {
      valid: false,
      missingMainKeys,
      message: base.message || `以下字段未填写：${quoteCnList(names)}`,
    };
  }
  return { valid: true, missingMainKeys: [] as string[] };
}

async function precheckBeforeOpenAction(): Promise<boolean> {
  const payload = layoutIsTabs.value
    ? await collectRuntimePayloadFromFormHost(formPanelRef.value as any, { validate: true })
    : {
        mainForm: (((await boundFormApi.getValues()) || {}) as Record<string, unknown>),
        tabsData: parseLatestTabsData(),
      };
  if (!payload) return false;
  const mainFieldLabelMap = buildMainFieldLabelMap(formSchema.value as VbenFormSchema[]);
  const requiredByRules = collectRequiredMainFieldKeysFromRules(tabsFieldRulesMap.value);
  const requiredBySchema = collectRequiredMainFieldKeysFromSchema(formSchema.value as VbenFormSchema[]);
  const req = validateViewerRequired(
    tabsFieldRulesMap.value,
    payload.mainForm,
    payload.tabsData as Record<string, unknown> | undefined,
    mainFieldLabelMap,
  );
  const payloadMain = (payload.mainForm || {}) as Record<string, unknown>;
  const mergedRequiredKeys = [...new Set([...requiredByRules, ...requiredBySchema])];
  const missingByRequired = mergedRequiredKeys.filter((k) => isEmptyRequiredValue(payloadMain[k]));
  viewerDebugInfo.value = {
    at: new Date().toISOString(),
    currentNodeId: resolvedCurrentNodeId.value,
    inspectInstanceId: inspectInstanceId.value,
    layoutIsTabs: layoutIsTabs.value,
    boundFormMode: boundFormMode.value,
    rulesCount: Object.keys(tabsFieldRulesMap.value || {}).length,
    requiredByRules,
    requiredBySchema,
    mergedRequiredKeys,
    missingByRequired,
    reqValid: req.valid,
    reqMessage: (req as any)?.message || '',
    reqMissingMainKeys: (req as any)?.missingMainKeys || [],
    mainFormKeys: Object.keys(payloadMain),
    mainFormSample: payloadMain,
  };
  if (!req.valid) {
    await applyViewerRequiredVisual(req.missingMainKeys || []);
    message.error(req.message || '存在未填写的必填字段');
    return false;
  }
  await applyViewerRequiredVisual([]);
  return true;
}

async function onOpenAction(type: 'agree' | 'reject') {
  if (!myTodo.value) {
    message.warning('当前登录人不是该实例的办理人，无法提交/驳回');
    return;
  }
  if (!(await precheckBeforeOpenAction())) return;
  actionType.value = type;
  actionComment.value = '';
  actionModalOpen.value = true;
}

async function onConfirmAction() {
  if (!myTodo.value) return;
  actionSubmitting.value = true;
  try {
    await submitRuntimeTaskAction({
      actionComment: actionComment.value,
      actionRejectToNodeId: '',
      actionRow: myTodo.value,
      actionType: actionType.value,
      applyTaskRequiredVisual: applyViewerRequiredVisual,
      buildMainFieldLabelMap: (schema) => buildMainFieldLabelMap(schema),
      collectRuntimePayloadFromFormHost: async () => {
        if (layoutIsTabs.value) {
          return await collectRuntimePayloadFromFormHost(formPanelRef.value as any);
        }
        return {
          mainForm: (((await boundFormApi.getValues()) || {}) as Record<string, unknown>),
          tabsData: parseLatestTabsData(),
        };
      },
      completeTask: async (req) => {
        return await withTimeout(
          wfEngineRuntimeCompleteTask({
            taskId: req.taskId,
            action: req.action,
            comment: req.comment,
            mainForm: req.mainForm,
            tabsData: req.tabsData,
          }),
          25_000,
          req.action === 'agree' ? '提交' : '驳回',
        );
      },
      getInspectInstanceId: () => inspectInstanceId.value,
      hasCurrentPrimaryTodo: () => Boolean(myTodo.value),
      isTaskFormExclusiveUi: () => boundFormMode.value === 'designer' || boundFormMode.value === 'ext',
      loadInstanceDetail,
      loadTaskBoundForm: loadBoundFormPreview,
      loadTimeline,
      loadTodos: loadMyTodo,
      nextTick,
      openAgreeAction: () => {},
      profiled,
      setActionModalOpen: (v) => {
        actionModalOpen.value = v;
      },
      setInspectInstanceId: (id) => {
        inspectInstanceId.value = String(id || '').trim();
      },
      startBoundFormGetValues: async () =>
        (((await boundFormApi.getValues()) || {}) as Record<string, unknown>),
      startFormSchema: formSchema.value as VbenFormSchema[],
      taskBoundFormMode: boundFormMode.value,
      taskLayoutIsTabs: layoutIsTabs.value,
      taskTabsConfigLength: tabsConfig.value.length,
      taskTabsFieldRulesMap: tabsFieldRulesMap.value,
      todoRowsLength: () => (myTodo.value ? 1 : 0),
      trySyncMockAssigneeFromInstance: async () => {},
      validateRequiredByFieldRules: validateViewerRequired,
    });
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
  await ensureRuntimeDefinitionJsonCore({
    runtimeDefinitionJson,
    runtimeDraftDefinitionJson,
    processDefId,
    instanceDetail: instanceDetail as any,
    loadedProcessName,
    loadedProcessCode,
    profiled,
    withTimeout,
    wfEngineGetProcess,
    message,
  });
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
  return resolveCurrentNodeId({
    instanceDetail: instanceDetail.value,
    runtimeDefinitionJson: runtimeDefinitionJson.value,
    runtimeEndNodeId: runtimeEndNodeId.value,
    timelineRows: (timelineRows.value || []) as Array<Record<string, any>>,
  });
});

const businessDataColumns = [
  { title: '字段', dataIndex: 'field', key: 'field', width: 220 },
  { title: '值', dataIndex: 'value', key: 'value' },
];
const businessDataRows = computed(() => {
  const o = coerceLatestMainForm((instanceDetail.value as any)?.latestData);
  return mapBusinessDataRows(o as Record<string, any>);
});

const headerMainForm = computed<Record<string, any>>(() => parseLatestMainForm());
const headerFlowNo = computed(() =>
  resolveHeaderFlowNo({
    instance: (instanceDetail.value?.instance as any) || null,
    headerMainForm: headerMainForm.value,
    extractFlowNoFromObject,
  }),
);
const headerStarter = computed(() =>
  resolveHeaderStarter({
    form: headerMainForm.value || {},
    inst: ((instanceDetail.value?.instance || {}) as Record<string, any>) || {},
    isLikelyGuidStr,
    pickStringByKeys,
  }),
);
const headerEmployeeNo = computed(() =>
  resolveHeaderEmployeeNo({
    form: headerMainForm.value || {},
    inst: ((instanceDetail.value?.instance || {}) as Record<string, any>) || {},
    isLikelyGuidStr,
    pickStringByKeys,
  }),
);
const headerDept = computed(() =>
  resolveHeaderDept({
    form: headerMainForm.value || {},
    pickStringByKeys,
  }),
);
const headerPosition = computed(() =>
  resolveHeaderPosition({
    form: headerMainForm.value || {},
    userInfo: ((userStore.userInfo || {}) as Record<string, any>) || {},
    pickStringByKeys,
  }),
);
const headerStartTime = computed(() => resolveHeaderStartTime((instanceDetail.value?.instance as any) || null));
const currentLoginName = computed(() => {
  const u = (userStore.userInfo || {}) as Record<string, any>;
  return resolveCurrentLoginName(u, pickStringByKeys);
});
const currentLoginEmpNo = computed(() => {
  const u = (userStore.userInfo || {}) as Record<string, any>;
  return resolveCurrentLoginEmpNo(u, pickStringByKeys, isLikelyGuidStr);
});
const effectiveActorName = computed(() => {
  return resolveEffectiveActorName(route.query.mockAssigneeName, currentLoginName.value);
});
const effectiveActorEmpNo = computed(() => {
  return resolveEffectiveActorEmpNo(route.query.mockAssigneeEmpNo, currentLoginEmpNo.value, isLikelyGuidStr);
});
const mobileHeaderRows = computed(() =>
  buildMobileHeaderRows({
    headerFlowNo: headerFlowNo.value,
    processName: String(instanceDetail.value?.process?.process_name || ''),
    loadedProcessName: loadedProcessName.value,
    headerStarter: headerStarter.value,
    headerStartTime: headerStartTime.value,
    headerEmployeeNo: headerEmployeeNo.value,
    headerDept: headerDept.value,
    headerPosition: headerPosition.value,
    statusText: instanceMetaStatus.value.text,
    statusColor: instanceMetaStatus.value.color,
    runtimeNodeNameMap: runtimeNodeNameMap.value,
    resolvedCurrentNodeId: resolvedCurrentNodeId.value,
  }),
);

// --- 表单真实预览（只读） ---
const formLoading = ref(false);
const boundFormMode = ref<'none' | 'designer' | 'ext' | 'snapshot'>('none');
const boundFormModeForPanel = computed<'designer' | 'ext' | 'snapshot'>(() =>
  boundFormMode.value === 'none' ? 'snapshot' : boundFormMode.value,
);
const boundFormHint = ref('');
const formSchema = ref<VbenFormSchema[]>([]);
const extRuntimeRoot = shallowRef<VueConcreteComponent | null>(null);
const layoutIsTabs = ref(false);
const tabsConfig = ref<TabTableConfig[]>([]);
const tabsInitialMainValues = ref<Record<string, any>>({});
const tabsFieldRulesMap = ref<Record<string, WfNodeFormFieldRule>>({});
const formPanelRef = ref<InstanceType<typeof RuntimeViewerMainCard> | null>(null);

const [BoundForm, boundFormApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as VbenFormSchema[],
  wrapperClass: 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
  layout: 'horizontal',
  formItemGapPx: 2 as any,
  commonConfig: { labelWidth: 110 } as any,
});

function buildBoundFormUiState(schema: VbenFormSchema[] = [] as VbenFormSchema[]) {
  return buildBoundFormUiStateByMode(isMobilePreviewMode.value, schema);
}

watch(
  isMobilePreviewMode,
  async () => {
    await boundFormApi.setState(buildBoundFormUiState());
  },
  { immediate: true },
);

function parseLatestMainForm() {
  return parseLatestMainFormFromDetail(instanceDetail.value);
}

function parseLatestTabsData() {
  return parseLatestTabsDataFromDetail(instanceDetail.value);
}

async function loadBoundFormPreview() {
  await loadBoundFormPreviewCore({
    inspectInstanceId,
    resolvedCurrentNodeId,
    boundFormMode: boundFormMode as any,
    boundFormHint,
    formLoading,
    extRuntimeRoot,
    formSchema,
    layoutIsTabs,
    tabsConfig,
    tabsFieldRulesMap,
    tabsInitialMainValues,
    ensureRuntimeDefinitionJson,
    runtimeDefinitionJson,
    resolveNodeFormBindingWithStartFallback,
    runtimeNodeList: runtimeNodeList as any,
    tryApplyExtFormPreview,
    boundFormApi: boundFormApi as any,
    buildBoundFormUiState,
    applyBoundFormValuesNonBlocking,
    withTimeout,
    getWorkflowFormSchemaByCode,
    buildDesignerFormPreview,
    jsonSafeClone,
    buildWorkflowBuiltinValuesFromUser,
    userInfo: userStore.userInfo as any,
    parseLatestMainForm,
    applyDesignerRender: applyDesignerRender as any,
    formPanelRef: formPanelRef as any,
    nextTick,
    parseLatestTabsData,
    profiledPush: pushRuntimePerfLog,
    instanceDetail: instanceDetail as any,
  });
}

// --- 审批记录（沿用运行台的“节点卡片”展示） ---
const runtimeStartNodeId = computed(() => resolveRuntimeStartNodeId(runtimeDefinitionJson.value));

const currentRoundStartMs = computed(() => {
  return computeCurrentRoundStartMs(
    (timelineRows.value || []) as Array<Record<string, any>>,
    runtimeStartNodeId.value,
  );
});

const timelineRowsCurrentRound = computed(() => {
  return filterTimelineRowsCurrentRound(
    (timelineRows.value || []) as Array<Record<string, any>>,
    currentRoundStartMs.value,
  );
});

const timelineNodeCards = computed(() => {
  return buildTimelineNodeCards({
    currentRoundStartMs: currentRoundStartMs.value,
    operatorDisplayMap: operatorDisplayMap.value,
    runtimeNodeList: runtimeNodeList.value,
    timelineRows: (timelineRows.value || []) as Array<Record<string, any>>,
    timelineRowsCurrentRound: timelineRowsCurrentRound.value as Array<Record<string, any>>,
    tasks: ((instanceDetail.value?.tasks as Array<Record<string, any>>) || []) as Array<Record<string, any>>,
  });
});

const instanceMetaStatus = computed(() => {
  const st = Number((instanceDetail.value as any)?.instance?.status ?? -1);
  if (st === 2) return { text: '已完成', color: 'success' };
  if (st === 3) return { text: '已驳回', color: 'error' };
  if (st === 4) return { text: '已撤回', color: 'default' };
  return { text: '运行中', color: 'processing' };
});

setupRuntimeViewerHydration({
  route,
  message,
  runtimePerfLogs,
  setWorkflowRuntimeMockAssigneeUserId,
  inspectInstanceId,
  processDefId,
  processCode,
  runtimeDraftKey,
  applyRuntimeDraftByKey,
  loadInstanceDetail,
  loadTimeline,
  ensureUserInfoForRuntimeViewer,
  loadMyTodo,
  ensureRuntimeDefinitionJson,
  loadBoundFormPreview,
  instanceDetail,
  resolvedCurrentNodeId,
  runtimeDefinitionJson,
  hydrateMain: async () => {},
});
</script>

<template>
  <div class="wf-viewer-page">
    <ProcessPreviewShell :frame="isMobilePreviewMode">
      <div
        class="wf-viewer-root flex flex-col gap-2"
        :class="isMobilePreviewMode ? 'wf-mobile-single gap-3' : 'p-2'"
      >
      <RuntimeViewerMainCard
        ref="formPanelRef"
        :user-name="effectiveActorName"
        :user-emp-no="effectiveActorEmpNo"
        :todo-loading="todoLoading"
        :action-submitting="actionSubmitting"
        :my-todo="!!myTodo"
        :action-open="actionModalOpen"
        :action-type="actionType"
        :action-comment="actionComment"
        :is-mobile-preview-mode="isMobilePreviewMode"
        :mobile-header-rows="mobileHeaderRows"
        :header-flow-no="headerFlowNo"
        :process-name="String(instanceDetail?.process?.process_name || '')"
        :loaded-process-name="loadedProcessName"
        :header-starter="headerStarter"
        :header-start-time="headerStartTime"
        :header-employee-no="headerEmployeeNo"
        :header-dept="headerDept"
        :header-position="headerPosition"
        :instance-meta-status="instanceMetaStatus"
        :runtime-node-name-map="runtimeNodeNameMap"
        :current-node-id="resolvedCurrentNodeId"
        :show-runtime-perf-log="SHOW_RUNTIME_PERF_LOG"
        :runtime-perf-logs="runtimePerfLogs"
        :form-loading="formLoading"
        :bound-form-mode="boundFormModeForPanel"
        :form-schema="(formSchema as any)"
        :layout-is-tabs="layoutIsTabs"
        :tabs-config="tabsConfig"
        :tabs-field-rules-map="tabsFieldRulesMap"
        :tabs-initial-main-values="tabsInitialMainValues"
        :bound-form-component="BoundForm"
        :ext-runtime-root="extRuntimeRoot"
        :business-data-rows="businessDataRows"
        :business-data-columns="businessDataColumns"
        @open-action="onOpenAction"
        @confirm-action="onConfirmAction"
        @update:action-open="(v) => (actionModalOpen = v)"
        @update:action-type="(v) => (actionType = v)"
        @update:action-comment="(v) => (actionComment = v)"
      />

      <a-card
        v-if="DEBUG_VIEWER"
        size="small"
        title="查看页调试信息"
      >
        <pre class="text-xs whitespace-pre-wrap">{{ JSON.stringify(viewerDebugInfo, null, 2) }}</pre>
      </a-card>

      <RuntimeViewerTimelinePanel
        :definition-json="runtimeDefinitionJson"
        :current-node-id="resolvedCurrentNodeId"
        :timeline-rows-current-round="timelineRowsCurrentRound"
        :timeline-rows="timelineRows"
        :timeline-node-cards="(timelineNodeCards as any)"
        :timeline-loading="timelineLoading"
      />
      </div>
    </ProcessPreviewShell>
  </div>
</template>

<style scoped src="./runtimeViewer.css"></style>
