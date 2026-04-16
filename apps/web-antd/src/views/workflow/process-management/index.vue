<script setup lang="ts">
import type { TreeProps } from 'ant-design-vue';

import { computed, h, nextTick, onUnmounted, reactive, ref, watch } from 'vue';
import { useRouter } from 'vue-router';

import { Page } from '@vben/common-ui';
import { useUserStore } from '@vben/stores';

import type { TableColumnType } from 'ant-design-vue';

import {
  Button,
  Card,
  Checkbox,
  Form,
  Input,
  InputNumber,
  message,
  Segmented,
  Space,
  Table,
  Tabs,
  Tag,
  Tree,
} from 'ant-design-vue';

import type { WfNodeFormBinding } from '#/views/demos/workflow-designer/workflow-definition.schema';
import WorkflowDesigner from '#/views/demos/workflow-designer/index.vue';
import { formatDebugLine, useDebugHelper } from '#/views/workflow/debug/useDebugHelper';
import { buildWfProcessPreviewSessionPayload } from '#/views/workflow/process-preview/buildSessionPayload';
import type { WfProcessPreviewJson } from '#/views/workflow/process-preview/types';
import {
  WF_PROCESS_PREVIEW_LOCAL_KEY,
  WF_PROCESS_PREVIEW_SESSION_KEY,
  isWfProcessPreviewJson,
} from '#/views/workflow/process-preview/types';

import NodeFormBindingModal from './NodeFormBindingModal.vue';

const TextArea = Input.TextArea;

const router = useRouter();
const userStore = useUserStore();

const TREE_PANE_WIDTH_KEY = 'wf-process-mgmt-tree-pane-width';
const TREE_PANE_MIN = 200;
const TREE_PANE_MAX = 520;

function clampTreePaneWidth(w: number) {
  return Math.min(TREE_PANE_MAX, Math.max(TREE_PANE_MIN, Math.round(w)));
}

const storedTreeW = Number(
  typeof localStorage !== 'undefined'
    ? localStorage.getItem(TREE_PANE_WIDTH_KEY)
    : NaN,
);
const treePaneWidth = ref(
  Number.isFinite(storedTreeW) && storedTreeW > 0
    ? clampTreePaneWidth(storedTreeW)
    : 260,
);

let splitDragStartX = 0;
let splitDragStartW = 0;

function onSplitterMove(e: MouseEvent) {
  const delta = e.clientX - splitDragStartX;
  treePaneWidth.value = clampTreePaneWidth(splitDragStartW + delta);
}

function onSplitterUp() {
  window.removeEventListener('mousemove', onSplitterMove);
  window.removeEventListener('mouseup', onSplitterUp);
  try {
    localStorage.setItem(TREE_PANE_WIDTH_KEY, String(treePaneWidth.value));
  } catch {
    /* ignore */
  }
  void nextTick(() => {
    void nextTick(() => {
      workflowDesignerRef.value?.resizeToParent?.();
    });
  });
}

function onSplitterDown(e: MouseEvent) {
  e.preventDefault();
  splitDragStartX = e.clientX;
  splitDragStartW = treePaneWidth.value;
  window.addEventListener('mousemove', onSplitterMove);
  window.addEventListener('mouseup', onSplitterUp);
}

onUnmounted(() => {
  window.removeEventListener('mousemove', onSplitterMove);
  window.removeEventListener('mouseup', onSplitterUp);
  if (pendingApplyRetryTimer) {
    clearTimeout(pendingApplyRetryTimer);
    pendingApplyRetryTimer = null;
  }
});

/** ??????????????? */
const treeData: TreeProps['treeData'] = [
  {
    title: '????',
    key: 'cat-hr',
    children: [
      { title: '1. ????', key: 'proc-leave', isLeaf: true },
      { title: '2. ????', key: 'proc-overtime', isLeaf: true },
    ],
  },
  {
    title: '????',
    key: 'cat-admin',
    children: [{ title: '1. ????', key: 'proc-car', isLeaf: true }],
  },
];

const selectedKeys = ref<string[]>(['proc-leave']);

interface BasicFormModel {
  code: string;
  name: string;
  version: string;
  initiatorScope: string;
  remark: string;
}

const basicForm = reactive<BasicFormModel>({
  code: '',
  name: '',
  version: '',
  initiatorScope: '',
  remark: '',
});

/** ??????????????*/
const basicFormLabelCol = { flex: '0 0 100px' };
const basicFormWrapperCol = { flex: '1 1 auto', minWidth: 0 };

/** ????????????????????????*/
/** ???????????????key????????????*/
const basicFormSeed: Record<string, Partial<BasicFormModel>> = {
  'proc-leave': {
    code: 'HR_LEAVE',
    name: '????',
    version: '1.0',
    initiatorScope: '????',
    remark: '??????????,
  },
  'proc-overtime': {
    code: 'HR_OT',
    name: '????',
    version: '1.0',
    initiatorScope: '????',
    remark: '?????????,
  },
  'proc-car': {
    code: 'ADM_CAR',
    name: '????',
    version: '1.0',
    initiatorScope: '??????????,
    remark: '????????,
  },
};

function resetBasicFormFromSelection(key: string | undefined) {
  const k = key && basicFormSeed[key] ? key : 'proc-leave';
  const seed = basicFormSeed[k] ?? {};
  basicForm.code = seed.code ?? '';
  basicForm.name = seed.name ?? '';
  basicForm.version = seed.version ?? '';
  basicForm.initiatorScope = seed.initiatorScope ?? '';
  basicForm.remark = seed.remark ?? '';
}

function isPersistableProcessKey(key: string | undefined): key is string {
  return typeof key === 'string' && key in basicFormSeed;
}

const LOCAL_DRAFT_PREFIX = 'wf-process-mgmt-local-draft:';

function localDraftStorageKey(processKey: string) {
  return `${LOCAL_DRAFT_PREFIX}${processKey}`;
}

interface ProcessMgmtLocalDraftV1 {
  formatVersion: 1;
  processKey: string;
  savedAt: string;
  basic: BasicFormModel;
  definition: Record<string, unknown> | null;
}

const pendingApplyDefinition = ref<Record<string, unknown> | null>(null);
let pendingApplyRetryCount = 0;
let pendingApplyRetryTimer: ReturnType<typeof setTimeout> | null = null;

const { events: debugEvents, push: pushDebugEvent } = useDebugHelper({ maxEvents: 10 });

function countBindingNodesFromDefinition(def: Record<string, unknown> | null | undefined) {
  const gd = (def?.graphData ?? {}) as { nodes?: any[] };
  const nodes = Array.isArray(gd?.nodes) ? gd.nodes : [];
  let boundCount = 0;
  for (const n of nodes) {
    const p = (n?.properties || {}) as Record<string, any>;
    const fb = p?.formBinding as Record<string, any> | undefined;
    const isExt =
      fb?.formSource === 'ext' && String(fb?.extFormKey || '').trim().length > 0;
    const code = String(fb?.formCode || p?.formCode || p?.bindFormCode || '').trim();
    const name = String(
      fb?.formName ||
        p?.formName ||
        p?.bindFormName ||
        p?.formTitle ||
        p?.formLabel ||
        '',
    ).trim();
    if (isExt || code || name) boundCount += 1;
  }
  return { nodeCount: nodes.length, boundCount };
}

function loadLocalDraftForProcessKey(key: string) {
  pushDebugEvent(`load.start processKey=${key}`);
  let raw: string | null = null;
  try {
    raw = localStorage.getItem(localDraftStorageKey(key));
  } catch {
    raw = null;
  }
  if (!raw) {
    resetBasicFormFromSelection(key);
    pendingApplyDefinition.value = null;
    pushDebugEvent(`load.empty processKey=${key}`);
    return;
  }
  try {
    const draft = JSON.parse(raw) as ProcessMgmtLocalDraftV1;
    if (draft?.basic && typeof draft.basic === 'object') {
      Object.assign(basicForm, {
        code: String(draft.basic.code ?? ''),
        name: String(draft.basic.name ?? ''),
        version: String(draft.basic.version ?? ''),
        initiatorScope: String(draft.basic.initiatorScope ?? ''),
        remark: String(draft.basic.remark ?? ''),
      });
    } else {
      resetBasicFormFromSelection(key);
    }
    pendingApplyDefinition.value =
      draft?.definition && typeof draft.definition === 'object'
        ? (draft.definition as Record<string, unknown>)
        : null;
    const cnt = countBindingNodesFromDefinition(pendingApplyDefinition.value);
    pushDebugEvent(
      `load.ok processKey=${key}, rawLen=${raw.length}, nodes=${cnt.nodeCount}, boundNodes=${cnt.boundCount}`,
    );
  } catch {
    resetBasicFormFromSelection(key);
    pendingApplyDefinition.value = null;
    pushDebugEvent(`load.parse_fail processKey=${key}, rawLen=${raw.length}`);
  }
}

function flushPendingDefinitionToDesigner() {
  const snap = pendingApplyDefinition.value;
  if (!snap) return;
  const apply = workflowDesignerRef.value?.applyWorkflowDraftFromObject;
  if (!apply) {
    schedulePendingApplyRetry('designer_not_ready');
    return;
  }
  if (apply(snap)) {
    const cnt = countBindingNodesFromDefinition(snap);
    pushDebugEvent(
      `apply.ok processKey=${selectedKeys.value[0] || '??}, nodes=${cnt.nodeCount}, boundNodes=${cnt.boundCount}`,
    );
    pendingApplyDefinition.value = null;
    pendingApplyRetryCount = 0;
    if (pendingApplyRetryTimer) {
      clearTimeout(pendingApplyRetryTimer);
      pendingApplyRetryTimer = null;
    }
    const rows = workflowDesignerRef.value?.getMgmtNodeTableRows?.();
    if (rows) nodeInfoRows.value = rows;
    const exits = workflowDesignerRef.value?.getMgmtExitTableRows?.();
    if (exits) exitInfoRows.value = exits;
  } else {
    pushDebugEvent(`apply.fail processKey=${selectedKeys.value[0] || '??}`);
    schedulePendingApplyRetry('apply_return_false');
  }
}

function schedulePendingApplyRetry(reason: string) {
  if (!pendingApplyDefinition.value) return;
  if (pendingApplyRetryCount >= 20) {
    pushDebugEvent(`apply.give_up reason=${reason}`);
    return;
  }
  pendingApplyRetryCount += 1;
  if (pendingApplyRetryTimer) clearTimeout(pendingApplyRetryTimer);
  const delay = Math.min(600, 80 * pendingApplyRetryCount);
  pushDebugEvent(`apply.retry#${pendingApplyRetryCount} in ${delay}ms reason=${reason}`);
  pendingApplyRetryTimer = setTimeout(() => {
    pendingApplyRetryTimer = null;
    flushPendingDefinitionToDesigner();
  }, delay);
}

watch(
  () => selectedKeys.value[0],
  (key) => {
    if (isPersistableProcessKey(key)) {
      loadLocalDraftForProcessKey(key);
      pendingApplyRetryCount = 0;
    } else {
      resetBasicFormFromSelection(key);
      pendingApplyDefinition.value = null;
      pendingApplyRetryCount = 0;
    }
    void nextTick(() => {
      void nextTick(() => {
        flushPendingDefinitionToDesigner();
      });
    });
  },
  { immediate: true },
);

const canPersistCurrentProcess = computed(() =>
  isPersistableProcessKey(selectedKeys.value[0]),
);

const debugStorageInfo = computed(() => {
  const key = selectedKeys.value[0];
  if (!key) return 'debug.storage key=??;
  const storageKey = localDraftStorageKey(key);
  let hit = false;
  let rawLen = 0;
  try {
    const raw = localStorage.getItem(storageKey) ?? '';
    hit = !!raw;
    rawLen = raw.length;
  } catch {
    hit = false;
    rawLen = 0;
  }
  const def = workflowDesignerRef.value?.getWorkflowDraftSnapshot?.() ?? null;
  const cnt = countBindingNodesFromDefinition(def as Record<string, unknown> | null);
  return formatDebugLine('debug.storage', {
    processKey: key,
    persistable: canPersistCurrentProcess.value,
    hit,
    rawLen,
    nodes: cnt.nodeCount,
    boundNodes: cnt.boundCount,
  });
});

function saveCurrentPageToLocal() {
  persistCurrentPageToLocal({ silent: false });
}

function persistCurrentPageToLocal(options?: { silent?: boolean }): boolean {
  const silent = !!options?.silent;
  const processKey = selectedKeys.value[0];
  if (!isPersistableProcessKey(processKey)) {
    if (!silent) message.warning('????????????????');
    pushDebugEvent(`persist.skip processKey=${processKey || '??} (not leaf)`);
    return false;
  }
  const definition = workflowDesignerRef.value?.getWorkflowDraftSnapshot?.() ?? null;
  const cnt = countBindingNodesFromDefinition(definition as Record<string, unknown> | null);
  const draft: ProcessMgmtLocalDraftV1 = {
    formatVersion: 1,
    processKey,
    savedAt: new Date().toISOString(),
    basic: {
      code: basicForm.code,
      name: basicForm.name,
      version: basicForm.version,
      initiatorScope: basicForm.initiatorScope,
      remark: basicForm.remark,
    },
    definition,
  };
  try {
    localStorage.setItem(localDraftStorageKey(processKey), JSON.stringify(draft));
    if (!silent) message.success('??????????localStorage??);
    pushDebugEvent(
      `persist.ok processKey=${processKey}, nodes=${cnt.nodeCount}, boundNodes=${cnt.boundCount}, silent=${silent}`,
    );
    return true;
  } catch (e) {
    if (!silent) message.error(`??????{(e as Error).message}`);
    pushDebugEvent(`persist.fail processKey=${processKey}, error=${(e as Error).message}`);
    return false;
  }
}

function pickUserLabel(u: Record<string, any> | null | undefined): string {
  if (!u) return '??;
  return (
    String(u.realName || u.name || u.username || u.userName || '').trim() || '????'
  );
}

function pickDeptLabel(u: Record<string, any> | null | undefined): string {
  if (!u) return '??;
  return String(u.deptName || u.departmentName || u.orgName || '').trim() || '??;
}

async function fetchDemoPreviewTemplate(): Promise<WfProcessPreviewJson | null> {
  const base = (import.meta.env.BASE_URL || '/').replace(/\/?$/, '/');
  try {
    const res = await fetch(`${base}workflow/process-preview-demo.json`, {
      cache: 'no-store',
    });
    if (!res.ok) return null;
    const v = await res.json();
    return isWfProcessPreviewJson(v) ? v : null;
  } catch {
    return null;
  }
}

async function openProcessPreviewWindow(mode: 'desktop' | 'mobile' = 'desktop') {
  const baseJson = await fetchDemoPreviewTemplate();
  if (!baseJson) {
    message.error('????????????????public/workflow/process-preview-demo.json');
    return;
  }
  const definition = workflowDesignerRef.value?.getWorkflowDraftSnapshot?.() ?? null;
  const built = await buildWfProcessPreviewSessionPayload({
    baseJson,
    basicForm,
    userInfo: userStore.userInfo as Record<string, any> | undefined,
    definition,
  });
  if (!built.ok) {
    message.error(built.message);
    return;
  }
  try {
    sessionStorage.setItem(WF_PROCESS_PREVIEW_SESSION_KEY, JSON.stringify(built.merged));
    localStorage.setItem(WF_PROCESS_PREVIEW_LOCAL_KEY, JSON.stringify(built.merged));
  } catch (e) {
    message.error(`??????????${(e as Error).message}`);
    return;
  }
  /** ??path ???????? coreRoutes ??name ??????????????*/
  const href = router.resolve({
    path: '/workflow/process-preview',
    query: mode === 'mobile' ? { mode: 'mobile' } : undefined,
  }).href;
  const feature =
    mode === 'mobile'
      ? 'noopener,noreferrer,width=1320,height=940'
      : 'noopener,noreferrer,width=1280,height=880';
  window.open(href, '_blank', feature);
}

function findTitleByKey(
  nodes: TreeProps['treeData'],
  key: string,
): string | undefined {
  if (!nodes) return undefined;
  for (const n of nodes) {
    if (!n) continue;
    if (n.key === key) return String(n.title ?? '');
    const hit = findTitleByKey(n.children as TreeProps['treeData'], key);
    if (hit) return hit;
  }
  return undefined;
}

const currentProcessTitle = computed(() => {
  const k = selectedKeys.value[0];
  if (!k) return '??????;
  return findTitleByKey(treeData, k) ?? k;
});

/** ????????????????/?????????????????????? */
const designerMetaDraft = computed(() => ({
  processName: basicForm.name,
  processCode: basicForm.code,
  processVersion: basicForm.version,
}));

const activeTab = ref('basic');
/** ???????????*/
const activeFlowSubTab = ref('graph');

interface NodeInfoTableRow {
  key: string;
  nodeName: string;
  nodeType: string;
  operator: string;
  formContent: string;
  formBinding?: WfNodeFormBinding | null;
}

interface ExitInfoTableRow {
  key: string;
  priority: number;
  selected: boolean;
  sourceNodeName: string;
  isReturn: boolean;
  hasCondition: boolean;
  extraRulesLabel: string;
  generateNumber: boolean;
  exitName: string;
  targetNodeName: string;
  exitHint: string;
}

const workflowDesignerRef = ref<{
  resizeToParent?: () => void;
  getMgmtNodeTableRows?: () => NodeInfoTableRow[];
  getMgmtExitTableRows?: () => ExitInfoTableRow[];
  getNodeFormBinding?: (nodeId: string) => WfNodeFormBinding | null;
  applyNodeFormBinding?: (
    nodeId: string,
    binding: WfNodeFormBinding | null,
  ) => boolean;
  getWorkflowDraftSnapshot?: () => Record<string, unknown> | null;
  applyWorkflowDraftFromObject?: (parsed: Record<string, unknown> | null) => boolean;
  applyEdgePriority?: (edgeId: string, priority: number) => boolean;
} | null>(null);

watch(
  () => [activeTab.value, workflowDesignerRef.value] as const,
  () => {
    if (activeTab.value !== 'flow') return;
    void nextTick(() => {
      void nextTick(() => {
        flushPendingDefinitionToDesigner();
      });
    });
  },
  { flush: 'post' },
);

const nodeInfoRows = ref<NodeInfoTableRow[]>([]);
const exitInfoRows = ref<ExitInfoTableRow[]>([]);

const flowSubSegmentedOptions = [
  { label: '??????, value: 'graph' },
  { label: '????', value: 'nodes' },
  { label: '????', value: 'exits' },
];

const nodeFormBindingOpen = ref(false);
const nodeFormBindingNodeId = ref('');
const nodeFormBindingNodeName = ref('');
const nodeFormBindingInitialState = ref<WfNodeFormBinding | null>(null);

const nodeFormBindingInitial = computed<WfNodeFormBinding | null>(() => {
  if (nodeFormBindingInitialState.value) return nodeFormBindingInitialState.value;
  const id = nodeFormBindingNodeId.value;
  if (!id) return null;
  return workflowDesignerRef.value?.getNodeFormBinding?.(id) ?? null;
});

const nodeBindingSyncOptions = computed(() =>
  nodeInfoRows.value.map((r) => ({
    value: r.key,
    label: `${r.nodeName}??{r.nodeType}?`,
  })),
);

function openNodeFormBinding(record: NodeInfoTableRow) {
  nodeFormBindingNodeId.value = record.key;
  nodeFormBindingNodeName.value = record.nodeName;
  nodeFormBindingInitialState.value = record.formBinding ?? null;
  nodeFormBindingOpen.value = true;
}

watch(
  () => nodeFormBindingOpen.value,
  (v) => {
    if (!v) nodeFormBindingInitialState.value = null;
  },
);

function onNodeFormBindingSaved(binding: WfNodeFormBinding | null) {
  const id = nodeFormBindingNodeId.value;
  const ok = workflowDesignerRef.value?.applyNodeFormBinding?.(id, binding);
  if (ok) {
    message.success(binding ? '?????????? : '????????);
    persistCurrentPageToLocal({ silent: true });
    void nextTick(() => {
      const rows = workflowDesignerRef.value?.getMgmtNodeTableRows?.();
      if (rows) nodeInfoRows.value = rows;
    });
  } else {
    message.error('????????????????');
  }
}

function onNodeFormBindingSyncToNodes(payload: {
  nodeIds: string[];
  binding: WfNodeFormBinding;
}) {
  const ids = Array.from(new Set(payload.nodeIds.filter(Boolean)));
  if (!ids.length) {
    message.warning('?????????);
    return;
  }
  let okCount = 0;
  for (const id of ids) {
    const ok = workflowDesignerRef.value?.applyNodeFormBinding?.(id, payload.binding);
    if (ok) okCount += 1;
  }
  if (okCount === ids.length) {
    message.success(`???? ${okCount} ???`);
  } else {
    message.warning(`????${okCount}/${ids.length} ????????????`);
  }
  persistCurrentPageToLocal({ silent: true });
  void nextTick(() => {
    const rows = workflowDesignerRef.value?.getMgmtNodeTableRows?.();
    if (rows) nodeInfoRows.value = rows;
  });
}

const nodeInfoColumns = computed<TableColumnType<NodeInfoTableRow>[]>(() => [
  {
    title: '????',
    dataIndex: 'nodeName',
    key: 'nodeName',
    ellipsis: true,
  },
  {
    title: '????',
    dataIndex: 'nodeType',
    key: 'nodeType',
    width: 108,
  },
  {
    title: '????,
    dataIndex: 'operator',
    key: 'operator',
    ellipsis: true,
  },
  {
    title: '????',
    dataIndex: 'formContent',
    key: 'formContent',
    ellipsis: true,
    width: 160,
    customRender: ({ record }) =>
      h(
        Button,
        {
          type: 'link',
          size: 'small',
          class: '!h-auto px-0 py-0',
          onClick: () => openNodeFormBinding(record),
        },
        () => record.formContent || '????,
      ),
  },
]);

function onDesignerGraphNodeRows(rows: NodeInfoTableRow[]) {
  nodeInfoRows.value = rows;
}

function onDesignerGraphExitRows(rows: ExitInfoTableRow[]) {
  exitInfoRows.value = rows;
}

function onExitPriorityChange(record: ExitInfoTableRow, value: number | null) {
  const edgeId = String(record?.key || '').trim();
  if (!edgeId || edgeId.startsWith('e-')) {
    message.warning('???????? ID????????????????????');
    return;
  }
  const next = value == null ? 100 : Math.trunc(value);
  const ok = workflowDesignerRef.value?.applyEdgePriority?.(edgeId, next);
  if (ok) {
    message.success('????????);
    const rows = workflowDesignerRef.value?.getMgmtExitTableRows?.();
    if (rows) exitInfoRows.value = rows;
  } else {
    message.error('????????????????????);
  }
}

async function moveExitPriority(record: ExitInfoTableRow, direction: -1 | 1) {
  const rows = [...exitInfoRows.value];
  const idx = rows.findIndex((r) => String(r.key) === String(record.key));
  if (idx < 0) return;
  const targetIdx = idx + direction;
  if (targetIdx < 0 || targetIdx >= rows.length) return;
  const moved = rows[idx];
  rows.splice(idx, 1);
  rows.splice(targetIdx, 0, moved);

  // ?????????????????= ???????
  const base = 10;
  for (let i = 0; i < rows.length; i++) {
    const edgeId = String(rows[i]?.key || '').trim();
    if (!edgeId || edgeId.startsWith('e-')) {
      message.warning('?????? ID??????????????????);
      return;
    }
    const ok = workflowDesignerRef.value?.applyEdgePriority?.(edgeId, (i + 1) * base);
    if (!ok) {
      message.error('????????????????????);
      return;
    }
  }
  const latest = workflowDesignerRef.value?.getMgmtExitTableRows?.();
  if (latest) exitInfoRows.value = latest;
  message.success('????????);
}

const exitInfoColumns: TableColumnType<ExitInfoTableRow>[] = [
  {
    title: '??',
    key: 'selected',
    width: 56,
    align: 'center',
    customRender: ({ record }) =>
      h(Checkbox, { checked: record.selected, disabled: true }),
  },
  {
    title: '????',
    dataIndex: 'sourceNodeName',
    key: 'sourceNodeName',
    ellipsis: true,
    width: 120,
  },
  {
    title: '??',
    key: 'priority',
    width: 108,
    align: 'center',
    customRender: ({ record }) =>
      h(InputNumber, {
        min: 0,
        max: 99_999,
        size: 'small',
        class: 'w-[88px]',
        value: record.priority,
        onChange: (v: number | string | null) =>
          onExitPriorityChange(record, v == null || v === '' ? null : Number(v)),
      }),
  },
  {
    title: '??',
    key: 'move',
    width: 118,
    align: 'center',
    customRender: ({ record, index }) =>
      h(Space, { size: 4 }, () => [
        h(
          Button,
          {
            size: 'small',
            disabled: (index ?? 0) <= 0,
            onClick: () => void moveExitPriority(record, -1),
          },
          () => '??',
        ),
        h(
          Button,
          {
            size: 'small',
            disabled: (index ?? 0) >= exitInfoRows.value.length - 1,
            onClick: () => void moveExitPriority(record, 1),
          },
          () => '??',
        ),
      ]),
  },
  {
    title: '?????,
    key: 'isReturn',
    width: 88,
    align: 'center',
    customRender: ({ record }) =>
      h(Checkbox, { checked: record.isReturn, disabled: true }),
  },
  {
    title: '??',
    key: 'hasCondition',
    width: 100,
    align: 'center',
    customRender: ({ record }) =>
      h(
        Tag,
        { color: record.hasCondition ? 'success' : 'default' },
        () => (record.hasCondition ? '???? : '????),
      ),
  },
  {
    title: '????',
    dataIndex: 'extraRulesLabel',
    key: 'extraRulesLabel',
    width: 88,
    align: 'center',
  },
  {
    title: '????',
    key: 'generateNumber',
    width: 88,
    align: 'center',
    customRender: ({ record }) =>
      h(Checkbox, { checked: record.generateNumber, disabled: true }),
  },
  {
    title: '????',
    dataIndex: 'exitName',
    key: 'exitName',
    ellipsis: true,
    width: 120,
  },
  {
    title: '????',
    dataIndex: 'targetNodeName',
    key: 'targetNodeName',
    ellipsis: true,
    width: 120,
  },
  {
    title: '??????',
    dataIndex: 'exitHint',
    key: 'exitHint',
    ellipsis: true,
    minWidth: 140,
  },
];

watch(
  () => [activeTab.value, activeFlowSubTab.value] as const,
  ([tab, sub]) => {
    if (tab !== 'flow') return;
    if (sub === 'graph') {
      void nextTick(() => {
        void nextTick(() => {
          workflowDesignerRef.value?.resizeToParent?.();
        });
      });
    }
    if (sub === 'nodes') {
      void nextTick(() => {
        const rows = workflowDesignerRef.value?.getMgmtNodeTableRows?.();
        if (rows) nodeInfoRows.value = rows;
      });
    }
    if (sub === 'exits') {
      void nextTick(() => {
        const rows = workflowDesignerRef.value?.getMgmtExitTableRows?.();
        if (rows) exitInfoRows.value = rows;
      });
    }
  },
  { flush: 'post' },
);

/** ?????????????????????????Tabs ????????????*/
watch(
  () => activeTab.value,
  (tab) => {
    if (tab !== 'flow') return;
    void nextTick(() => {
      void nextTick(() => {
        workflowDesignerRef.value?.resizeToParent?.();
      });
    });
  },
  { flush: 'post' },
);

function onTreeSelect(keys: (number | string)[]) {
  const k = keys[0];
  if (k !== undefined && k !== null) {
    pushDebugEvent(`tree.select from=${selectedKeys.value[0] || '??} to=${String(k)}`);
    if (selectedKeys.value[0] && selectedKeys.value[0] !== String(k)) {
      persistCurrentPageToLocal({ silent: true });
    }
    selectedKeys.value = [String(k)];
  }
}
</script>

<template>
  <Page
    auto-content-height
    content-class="flex min-h-0 flex-col overflow-hidden"
  >
    <div class="wf-mgmt-layout">
      <div class="wf-mgmt-tree-pane" :style="{ width: `${treePaneWidth}px` }">
        <Card class="wf-mgmt-tree-card" size="small" title="????">
          <Tree
            :tree-data="treeData"
            :selected-keys="selectedKeys"
            block-node
            default-expand-all
            show-line
            @select="onTreeSelect"
          />
        </Card>
      </div>
      <div
        class="wf-mgmt-splitter"
        role="separator"
        aria-orientation="vertical"
        aria-label="??????????"
        title="??????"
        @mousedown="onSplitterDown"
      />
      <Card class="wf-mgmt-main-card" size="small" :title="`????{currentProcessTitle}`">
        <template #extra>
          <Space :size="8" wrap>
            <Button
              size="small"
              type="default"
              :disabled="!canPersistCurrentProcess"
              @click="saveCurrentPageToLocal"
            >
              ??????
            </Button>
            <Button
              size="small"
              type="default"
              :disabled="!canPersistCurrentProcess"
              @click="openProcessPreviewWindow"
            >
              ??
            </Button>
            <Button
              size="small"
              type="default"
              :disabled="!canPersistCurrentProcess"
              @click="openProcessPreviewWindow('mobile')"
            >
              ?????
            </Button>
          </Space>
        </template>
        <div class="wf-mgmt-debug-panel">
          <div class="wf-mgmt-debug-line">{{ debugStorageInfo }}</div>
          <div class="wf-mgmt-debug-events">
            <div v-for="(row, idx) in debugEvents" :key="idx" class="wf-mgmt-debug-line">
              {{ row }}
            </div>
          </div>
        </div>
        <Tabs
          v-model:active-key="activeTab"
          class="wf-mgmt-tabs"
          type="card"
        >
          <Tabs.TabPane key="basic" tab="????">
            <div class="wf-mgmt-tab-scroll">
              <Form
                :label-col="basicFormLabelCol"
                :model="basicForm"
                :wrapper-col="basicFormWrapperCol"
                class="wf-mgmt-basic-form"
                label-align="right"
                layout="horizontal"
              >
                <Form.Item label="????" name="code">
                  <Input
                    v-model:value="basicForm.code"
                    allow-clear
                    placeholder="????????
                  />
                </Form.Item>
                <Form.Item label="??" name="name">
                  <Input
                    v-model:value="basicForm.name"
                    allow-clear
                    placeholder="????????
                  />
                </Form.Item>
                <Form.Item label="??" name="version">
                  <Input
                    v-model:value="basicForm.version"
                    allow-clear
                    placeholder="??1.0"
                  />
                </Form.Item>
                <Form.Item
                  class="wf-mgmt-form-item-multiline"
                  label="??????
                  name="initiatorScope"
                >
                  <TextArea
                    v-model:value="basicForm.initiatorScope"
                    :auto-size="{ minRows: 2, maxRows: 6 }"
                    allow-clear
                    placeholder="??????????????"
                  />
                </Form.Item>
                <Form.Item
                  class="wf-mgmt-form-item-multiline"
                  label="??"
                  name="remark"
                >
                  <TextArea
                    v-model:value="basicForm.remark"
                    :auto-size="{ minRows: 3, maxRows: 8 }"
                    allow-clear
                    placeholder="?????????"
                  />
                </Form.Item>
              </Form>
            </div>
          </Tabs.TabPane>
          <Tabs.TabPane key="flow" tab="????">
            <div class="wf-mgmt-flow-body">
              <Segmented
                v-model:value="activeFlowSubTab"
                class="wf-mgmt-flow-seg"
                :options="flowSubSegmentedOptions"
                size="small"
              />
              <div class="wf-mgmt-flow-panels">
                <div
                  class="wf-mgmt-flow-panel"
                  :class="{
                    'wf-mgmt-flow-panel--active': activeFlowSubTab === 'graph',
                  }"
                >
                  <div class="wf-mgmt-graph-embed">
                    <WorkflowDesigner
                      v-if="activeTab === 'flow'"
                      ref="workflowDesignerRef"
                      embedded
                      :meta-draft="designerMetaDraft"
                      @graph-data-change="onDesignerGraphNodeRows"
                      @graph-exit-data-change="onDesignerGraphExitRows"
                    />
                  </div>
                </div>
                <div
                  class="wf-mgmt-flow-panel"
                  :class="{
                    'wf-mgmt-flow-panel--active': activeFlowSubTab === 'nodes',
                  }"
                >
                  <div class="wf-mgmt-node-table-wrap">
                    <Table
                      :columns="nodeInfoColumns"
                      :data-source="nodeInfoRows"
                      :pagination="{
                        pageSize: 10,
                        showSizeChanger: true,
                        pageSizeOptions: ['10', '20', '50'],
                        showTotal: (t: number) => `??${t} ?`,
                      }"
                      row-key="key"
                      size="small"
                      :scroll="{ x: 720 }"
                    />
                  </div>
                </div>
                <div
                  class="wf-mgmt-flow-panel"
                  :class="{
                    'wf-mgmt-flow-panel--active': activeFlowSubTab === 'exits',
                  }"
                >
                  <div class="wf-mgmt-node-table-wrap">
                    <Table
                      :columns="exitInfoColumns"
                      :data-source="exitInfoRows"
                      :pagination="{
                        pageSize: 10,
                        showSizeChanger: true,
                        pageSizeOptions: ['10', '20', '50'],
                        showTotal: (t: number) => `??${t} ?`,
                      }"
                      row-key="key"
                      size="small"
                      :scroll="{ x: 1280 }"
                    />
                  </div>
                </div>
              </div>
            </div>
          </Tabs.TabPane>
          <Tabs.TabPane key="form" tab="????">
            <div class="wf-mgmt-tab-scroll">
              <p>???????????/p>
              <p class="text-sm text-muted-foreground">
                ????????????????????????????
              </p>
            </div>
          </Tabs.TabPane>
        </Tabs>
      </Card>
    </div>
    <NodeFormBindingModal
      v-model:open="nodeFormBindingOpen"
      :node-id="nodeFormBindingNodeId"
      :node-name="nodeFormBindingNodeName"
      :initial-binding="nodeFormBindingInitial"
      :node-options="nodeBindingSyncOptions"
      @saved="onNodeFormBindingSaved"
      @sync-to-nodes="onNodeFormBindingSyncToNodes"
    />
  </Page>
</template>

<style scoped>
.wf-mgmt-layout {
  display: flex;
  flex: 1;
  gap: 0;
  align-items: stretch;
  min-height: 0;
}

.wf-mgmt-tree-pane {
  display: flex;
  flex-shrink: 0;
  flex-direction: column;
  min-height: 0;
  min-width: 0;
  overflow: hidden;
}

.wf-mgmt-splitter {
  flex: 0 0 10px;
  box-sizing: border-box;
  width: 10px;
  margin: 0 2px;
  cursor: col-resize;
  touch-action: none;
  user-select: none;
  background: transparent;
}

.wf-mgmt-splitter::after {
  content: '';
  display: block;
  width: 4px;
  height: 100%;
  margin: 0 auto;
  border-radius: 2px;
  background: hsl(var(--border) / 0.85);
  transition: background 0.15s ease;
}

.wf-mgmt-splitter:hover::after {
  background: hsl(var(--primary) / 0.55);
}

.wf-mgmt-splitter:active::after {
  background: hsl(var(--primary));
}

.wf-mgmt-tree-card {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
  min-width: 0;
  overflow: hidden;
}

.wf-mgmt-tree-card :deep(.ant-card-body) {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
  overflow: auto;
}

.wf-mgmt-main-card {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-width: 0;
  min-height: 0;
  overflow: hidden;
}

.wf-mgmt-main-card :deep(.ant-card-body) {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
  padding-top: 12px;
  overflow: hidden;
}

.wf-mgmt-tabs {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
}

.wf-mgmt-tabs :deep(.ant-tabs-nav) {
  flex-shrink: 0;
}

.wf-mgmt-tabs :deep(.ant-tabs-content-holder) {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
  overflow: hidden;
}

.wf-mgmt-tabs :deep(.ant-tabs-content) {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
  height: 100%;
}

.wf-mgmt-tabs :deep(.ant-tabs-tabpane) {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
  height: 100%;
  overflow: hidden;
}

.wf-mgmt-tab-scroll {
  height: 100%;
  padding: 8px 4px 16px;
  overflow: auto;
}

.wf-mgmt-basic-form {
  max-width: 900px;
}

.wf-mgmt-basic-form :deep(.ant-form-item) {
  margin-bottom: 5px;
}

.wf-mgmt-basic-form :deep(.ant-form-item-with-help) {
  margin-bottom: 5px;
}

.wf-mgmt-basic-form :deep(.wf-mgmt-form-item-multiline .ant-form-item-label) {
  align-self: flex-start;
  padding-top: 5px;
}

.wf-mgmt-placeholder--sub {
  padding-top: 8px;
}

.wf-mgmt-graph-embed {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
  overflow: hidden;
}

.wf-mgmt-graph-embed :deep(.wf-designer-root) {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
}

.wf-mgmt-flow-body {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 360px;
  height: 100%;
  overflow: hidden;
}

.wf-mgmt-flow-seg {
  flex-shrink: 0;
  margin-bottom: 10px;
}

.wf-mgmt-flow-panels {
  position: relative;
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 280px;
  overflow: hidden;
}

.wf-mgmt-flow-panel {
  position: absolute;
  inset: 0;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  min-height: 0;
  overflow: hidden;
  visibility: hidden;
  pointer-events: none;
  z-index: 0;
}

.wf-mgmt-flow-panel--active {
  visibility: visible;
  pointer-events: auto;
  z-index: 1;
}

.wf-mgmt-node-table-wrap {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
  padding: 4px 0 8px;
  overflow: auto;
}

.wf-mgmt-debug-panel {
  margin-bottom: 8px;
  border: 1px dashed hsl(var(--border));
  border-radius: 6px;
  padding: 6px 8px;
  background: hsl(var(--muted) / 0.35);
}

.wf-mgmt-debug-events {
  margin-top: 4px;
  max-height: 84px;
  overflow: auto;
}

.wf-mgmt-debug-line {
  font-size: 11px;
  line-height: 1.35;
  color: #b45309;
  word-break: break-all;
}

.text-muted-foreground {
  color: hsl(var(--muted-foreground));
}
</style>
