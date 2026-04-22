<script setup lang="ts">
import type { TreeProps } from 'ant-design-vue';

import { computed, h, nextTick, onMounted, onUnmounted, reactive, ref, watch } from 'vue';
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
  Modal,
  Segmented,
  Select,
  Space,
  Switch,
  Table,
  Tabs,
  Tree,
} from 'ant-design-vue';

import { queryForVbenPaged } from '#/components/org-picker/orgPickerQuery';
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

import {
  type WfEngineCategoryRow,
  type WfEngineProcessRow,
  wfEngineCreateCategory,
  wfEngineCreateProcess,
  wfEngineDeleteCategory,
  wfEngineDeleteProcess,
  wfEngineGetProcess,
  wfEngineGetTree,
  wfEnginePublishProcess,
  wfEngineSaveProcess,
  wfEngineSeedDemoTree,
  wfEngineUpdateCategory,
  wfEngineUpdateProcessMeta,
} from '#/api/workflowEngine';

import NodeFormBindingModal from '../process-management/NodeFormBindingModal.vue';

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

const { events: debugEvents, push: pushDebugEvent } = useDebugHelper({ maxEvents: 10 });
/** 调试面板默认关闭，改成 true 可显示。 */
const showDebugPanel = false;

const treeData = ref<TreeProps['treeData']>([]);
const treeLoading = ref(false);
const lastTreeSnapshot = ref<{ categories: WfEngineCategoryRow[]; processes: WfEngineProcessRow[] }>(
  { categories: [], processes: [] },
);

type TreeCrudMode = 'addCat' | 'addProc' | 'editCat' | 'editProc';
const treeCrudModalOpen = ref(false);
const treeCrudSubmitting = ref(false);
const treeCrudMode = ref<TreeCrudMode>('addCat');
const treeCrudModalTitle = computed(() => {
  const m: Record<TreeCrudMode, string> = {
    addCat: '新建目录',
    addProc: '新建流程',
    editCat: '编辑目录',
    editProc: '编辑流程',
  };
  return m[treeCrudMode.value];
});

const treeForm = reactive({
  /** 新建目录时的父目录；为空表示顶级目录。 */
  newCategoryParentId: '',
  categoryName: '',
  folderCode: '',
  sortNo: 0,
  processCode: '',
  processName: '',
  processCategoryId: undefined as string | undefined,
  editingCategoryId: '',
  editingProcessId: '',
});

const categorySelectOptions = computed(() =>
  (lastTreeSnapshot.value.categories || []).map((c) => ({
    value: c.id,
    label: c.name,
  })),
);

/** 计算目录距根节点的层级，用于下拉缩进显示。 */
function categoryRootDepth(id: string): number {
  const cats = lastTreeSnapshot.value.categories || [];
  let depth = 0;
  let cur = cats.find((x) => x.id === id);
  while (cur?.parentId) {
    depth += 1;
    const pid = String(cur.parentId);
    cur = cats.find((x) => x.id === pid);
    if (depth > 50) break;
  }
  return depth;
}

const parentCategoryOptionsForNewFolder = computed(() => {
  const rootOpt = {
    value: '',
    label: '作为顶级目录（无上级）',
  };
  const cats = [...(lastTreeSnapshot.value.categories || [])].sort(
    (a, b) => a.sortNo - b.sortNo || a.name.localeCompare(b.name, 'zh-CN'),
  );
  const indent = '\u3000';
  const rest = cats.map((c) => ({
    value: c.id,
    label: `${indent.repeat(categoryRootDepth(c.id))}${c.name}`,
  }));
  return [rootOpt, ...rest];
});

function buildTreeFromPayload(
  categories: WfEngineCategoryRow[],
  processes: WfEngineProcessRow[],
): TreeProps['treeData'] {
  const catList = [...categories].sort((a, b) => a.sortNo - b.sortNo);
  const procList = [...processes];

  function childrenOfCategory(categoryId: string): NonNullable<TreeProps['treeData']> {
    const nodes: NonNullable<TreeProps['treeData']> = [];
    for (const c of catList.filter((x) => (x.parentId || '') === categoryId)) {
      nodes.push({
        title: c.name,
        key: `c-${c.id}`,
        children: childrenOfCategory(c.id),
      });
    }
    for (const p of procList.filter((x) => (x.categoryId || '') === categoryId)) {
      nodes.push({
        title: `${p.processName}（${p.processCode}）`,
        key: `p-${p.id}`,
        isLeaf: true,
      });
    }
    return nodes;
  }

  const roots: NonNullable<TreeProps['treeData']> = [];
  for (const c of catList.filter((x) => x.parentId == null || x.parentId === '')) {
    roots.push({
      title: c.name,
      key: `c-${c.id}`,
      children: childrenOfCategory(c.id),
    });
  }
  for (const p of procList.filter((x) => !x.categoryId)) {
    roots.push({
      title: `${p.processName}（${p.processCode}）`,
      key: `p-${p.id}`,
      isLeaf: true,
    });
  }
  return roots;
}

async function loadTree(selectFirstProcess = false) {
  treeLoading.value = true;
  try {
    const data = await wfEngineGetTree();
    lastTreeSnapshot.value = {
      categories: [...(data.categories ?? [])],
      processes: [...(data.processes ?? [])],
    };
    treeData.value = buildTreeFromPayload(data.categories ?? [], data.processes ?? []);
    if (selectFirstProcess || !selectedKeys.value.length) {
      const first = findFirstProcessKey(treeData.value);
      if (first) selectedKeys.value = [first];
    }
    pushDebugEvent(`tree.loaded cats=${data.categories?.length ?? 0} procs=${data.processes?.length ?? 0}`);
  } catch (e) {
    message.error(`加载流程目录失败：${(e as Error).message}`);
    pushDebugEvent(`tree.fail ${(e as Error).message}`);
  } finally {
    treeLoading.value = false;
  }
}

function findFirstProcessKey(nodes: TreeProps['treeData']): string | undefined {
  if (!nodes) return undefined;
  for (const n of nodes) {
    if (!n) continue;
    if (n.isLeaf && typeof n.key === 'string' && n.key.startsWith('p-')) return n.key;
    const hit = findFirstProcessKey(n.children as TreeProps['treeData']);
    if (hit) return hit;
  }
  return undefined;
}

async function seedDemoTree() {
  try {
    await wfEngineSeedDemoTree();
    message.success('演示目录初始化成功');
    await loadTree(true);
  } catch (e) {
    message.error(`初始化演示目录失败：${(e as Error).message}`);
  }
}

const selectedKeys = ref<string[]>([]);

const canEditTreeSelection = computed(() => {
  const k = selectedKeys.value[0];
  return typeof k === 'string' && (k.startsWith('c-') || k.startsWith('p-'));
});

const currentProcessDefId = ref<string | null>(null);
const lastLoadedVersionNo = ref<number | null>(null);
/** 当前流程所属目录，对应 wf_process_def.category_id。 */
const currentCategoryId = ref<string | null>(null);

interface BasicFormModel {
  code: string;
  name: string;
  version: string;
  initiatorScope: string;
  remark: string;
  /** 当前流程是否有效，对应 wf_process_def.is_valid。 */
  isValid: boolean;
}

const basicForm = reactive<BasicFormModel>({
  code: '',
  name: '',
  version: '',
  initiatorScope: '',
  remark: '',
  isValid: true,
});

/** 基础信息表单列宽配置。 */
const basicFormLabelCol = { flex: '0 0 100px' };
const basicFormWrapperCol = { flex: '1 1 auto', minWidth: 0 };

function resetBasicFormEmpty() {
  basicForm.code = '';
  basicForm.name = '';
  basicForm.version = '';
  basicForm.initiatorScope = '';
  basicForm.remark = '';
  basicForm.isValid = true;
}

function isProcessLeafKey(key: string | undefined): key is string {
  return typeof key === 'string' && key.startsWith('p-');
}

function processDefIdFromKey(key: string): string {
  return key.slice(2);
}

const pendingApplyDefinition = ref<Record<string, unknown> | null>(null);
let pendingApplyRetryCount = 0;
let pendingApplyRetryTimer: ReturnType<typeof setTimeout> | null = null;

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

async function loadProcessFromApi(leafKey: string) {
  const id = processDefIdFromKey(leafKey);
  currentProcessDefId.value = id;
  pushDebugEvent(`load.api start defId=${id}`);
  try {
    const data = await wfEngineGetProcess(id);
    const pd = data.processDef;
    currentCategoryId.value = pd.categoryId ?? null;
    basicForm.code = pd.processCode ?? '';
    basicForm.name = pd.processName ?? '';
    basicForm.isValid = pd.isValid !== false;
    lastLoadedVersionNo.value = data.version?.versionNo ?? null;
    basicForm.version =
      data.version?.versionNo != null ? String(data.version.versionNo) : '0';

    if (data.version?.definitionJson) {
      try {
        const parsed = JSON.parse(data.version.definitionJson) as Record<string, unknown>;
        /** 兼容旧数据：仅有 graph 而无 graphData */
        if (
          parsed &&
          !(parsed as { graphData?: unknown }).graphData &&
          (parsed as { graph?: { nodes?: unknown[] } }).graph?.nodes
        ) {
          (parsed as { graphData?: unknown }).graphData = (
            parsed as { graph?: unknown }
          ).graph;
        }
        pendingApplyDefinition.value = parsed;
        basicForm.initiatorScope = String(
          (parsed as any)?.initiatorScope ?? (parsed as any)?.wfMeta?.initiatorScope ?? '',
        );
        basicForm.remark = String((parsed as any)?.remark ?? (parsed as any)?.wfMeta?.remark ?? '');
      } catch {
        pendingApplyDefinition.value = null;
        basicForm.initiatorScope = '';
        basicForm.remark = '';
      }
    } else {
      message.warning(
        '该流程尚无已保存的版本定义，画布为空。请设计后点击「保存到数据库」；若为新库可重新执行演示种子。',
      );
      pendingApplyDefinition.value = {
        processCode: basicForm.code,
        processName: basicForm.name,
        processVersion: basicForm.version || '1',
        graphData: { nodes: [], edges: [] },
        engineModel: { nodes: [], edges: [] },
      } as Record<string, unknown>;
      basicForm.initiatorScope = '';
      basicForm.remark = '';
    }
    const cnt = countBindingNodesFromDefinition(pendingApplyDefinition.value);
    pushDebugEvent(
      `load.api ok defId=${id}, ver=${basicForm.version}, nodes=${cnt.nodeCount}, bound=${cnt.boundCount}`,
    );
  } catch (e) {
    resetBasicFormEmpty();
    pendingApplyDefinition.value = null;
    currentProcessDefId.value = null;
    lastLoadedVersionNo.value = null;
    currentCategoryId.value = null;
    pushDebugEvent(`load.api fail defId=${id} ${(e as Error).message}`);
  }
}

/** 嵌入设计器在 await+rAF 后才 init LogicFlow，晚于父级双 nextTick，首次 apply 常失败；画布就绪后再灌入一次。 */
function onWorkflowDesignerCanvasReady() {
  if (!pendingApplyDefinition.value) return;
  flushPendingDefinitionToDesigner();
}

function flushPendingDefinitionToDesigner() {
  const snap = pendingApplyDefinition.value;
  const apply = workflowDesignerRef.value?.applyWorkflowDraftFromObject;
  if (!apply) {
    if (snap) schedulePendingApplyRetry('designer_not_ready');
    return;
  }
  if (!snap) {
    /** 灌入成功后 pending 会置空；后续延时/rAF 再次 flush 时不得用空图覆盖，否则会出现「闪一下又没了」 */
    if (isProcessLeafKey(selectedKeys.value[0])) {
      return;
    }
    const cleared = {
      processCode: basicForm.code,
      processName: basicForm.name,
      processVersion: basicForm.version || '1',
      graphData: { nodes: [], edges: [] },
      engineModel: { nodes: [], edges: [] },
    } as Record<string, unknown>;
    if (apply(cleared)) {
      nodeInfoRows.value = [];
      exitInfoRows.value = [];
    }
    return;
  }
  if (apply(snap)) {
    const cnt = countBindingNodesFromDefinition(snap);
    pushDebugEvent(
      `apply.ok processKey=${selectedKeys.value[0] || '?'}, nodes=${cnt.nodeCount}, boundNodes=${cnt.boundCount}`,
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
    pushDebugEvent(`apply.fail processKey=${selectedKeys.value[0] || '?'}`);
    schedulePendingApplyRetry('apply_return_false');
  }
}

function schedulePendingApplyRetry(reason: string) {
  if (!pendingApplyDefinition.value) return;
  if (pendingApplyRetryCount >= 40) {
    pushDebugEvent(`apply.give_up reason=${reason}`);
    return;
  }
  pendingApplyRetryCount += 1;
  if (pendingApplyRetryTimer) clearTimeout(pendingApplyRetryTimer);
  const delay = Math.min(800, 60 * pendingApplyRetryCount);
  pushDebugEvent(`apply.retry#${pendingApplyRetryCount} in ${delay}ms reason=${reason}`);
  pendingApplyRetryTimer = setTimeout(() => {
    pendingApplyRetryTimer = null;
    flushPendingDefinitionToDesigner();
  }, delay);
}

/**
 * 与嵌入 WorkflowDesigner 内 initLogicFlow 的 nextTick + 双 rAF 对齐，避免首次灌入时 lf 尚未创建。
 * 只调度一次 flush，避免成功灌入后二次 flush 因 pending 已空而误清空画布。
 */
function scheduleFlushAfterProcessLoad() {
  void nextTick(() => {
    void nextTick(() => {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          flushPendingDefinitionToDesigner();
        });
      });
    });
  });
}

watch(
  () => selectedKeys.value[0],
  async (key) => {
    pendingApplyRetryCount = 0;
    if (isProcessLeafKey(key)) {
      await loadProcessFromApi(key);
    } else {
      resetBasicFormEmpty();
      currentProcessDefId.value = null;
      lastLoadedVersionNo.value = null;
      currentCategoryId.value = null;
      pendingApplyDefinition.value = null;
    }
    scheduleFlushAfterProcessLoad();
  },
  { immediate: true },
);

onMounted(() => {
  void loadTree(true);
});

const canPersistCurrentProcess = computed(() => isProcessLeafKey(selectedKeys.value[0]));

const debugStorageInfo = computed(() => {
  const key = selectedKeys.value[0];
  const def = workflowDesignerRef.value?.getWorkflowDraftSnapshot?.() ?? null;
  const cnt = countBindingNodesFromDefinition(def as Record<string, unknown> | null);
  return formatDebugLine('debug.db', {
    treeKey: key || '?',
    processDefId: currentProcessDefId.value,
    lastVer: lastLoadedVersionNo.value,
    persistable: canPersistCurrentProcess.value,
    nodes: cnt.nodeCount,
    boundNodes: cnt.boundCount,
  });
});

async function saveCurrentToDatabase() {
  const id = currentProcessDefId.value;
  if (!id || !canPersistCurrentProcess.value) {
    message.warning(uiText.saveWarnSelectProcess);
    return;
  }
  const definition = workflowDesignerRef.value?.getWorkflowDraftSnapshot?.() ?? null;
  if (!definition || typeof definition !== 'object') {
    message.warning(uiText.saveWarnNoDraft);
    return;
  }
  try {
    const res = await wfEngineSaveProcess({
      processDefId: id,
      processName: basicForm.name || basicForm.code,
      categoryId: currentCategoryId.value,
      initiatorScope: basicForm.initiatorScope,
      remark: basicForm.remark,
      isValid: basicForm.isValid,
      definition: definition as Record<string, unknown>,
    });
    lastLoadedVersionNo.value = res.versionNo;
    basicForm.version = String(res.versionNo);
    message.success(`${uiText.saveSuccess}${res.versionNo}`);
    pushDebugEvent(`db.save.ok ver=${res.versionNo}`);
  } catch (e) {
    message.error(`${uiText.errSavePrefix}${(e as Error).message}`);
    pushDebugEvent(`db.save.fail ${(e as Error).message}`);
  }
}

async function publishCurrentVersion() {
  const id = currentProcessDefId.value;
  const ver = lastLoadedVersionNo.value;
  if (!id || ver == null) {
    message.warning(uiText.publishWarnNoVer);
    return;
  }
  try {
    await wfEnginePublishProcess({ processDefId: id, versionNo: ver });
    message.success(`${uiText.publishSuccess}${ver}`);
    pushDebugEvent(`db.publish.ok ver=${ver}`);
  } catch (e) {
    message.error(`${uiText.errPublishPrefix}${(e as Error).message}`);
  }
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
    message.error('未找到预览模板，请确认 `public/workflow/process-preview-demo.json` 存在');
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
    message.error(`写入预览缓存失败：${(e as Error).message}`);
    return;
  }
  /** 直接使用 path，避免依赖路由 name 导致嵌套路由解析异常。 */
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

function openRuntimeWorkbench() {
  runtimeStarterPickerOpen.value = true;
}

const runtimeStarterPickerOpen = ref(false);
const runtimeStarterLoading = ref(false);
const runtimeStarterKeyword = ref('');
const runtimeStarterValue = ref<string>();
const runtimeUseDraftDefinition = ref(true);
const WF_RUNTIME_DRAFT_STORAGE_PREFIX = 'wf-runtime-draft:';
type RuntimeStarterOption = {
  id: string;
  empId: string;
  name: string;
  deptName: string;
  dutyName: string;
  label: string;
};
const runtimeStarterOptions = ref<RuntimeStarterOption[]>([]);
const runtimeStarterCache = ref<Record<string, RuntimeStarterOption>>({});
const runtimeStarterLastPicked = ref<RuntimeStarterOption | null>(null);

const runtimeStarterSelectOptions = computed(() =>
  runtimeStarterOptions.value.map((x) => ({
    value: x.id,
    label: x.label,
  })),
);

function pickRuntimeField(row: Record<string, any>, ...keys: string[]) {
  for (const k of keys) {
    const v = row[k];
    if (v !== undefined && v !== null && String(v).trim()) return String(v).trim();
  }
  return '';
}

async function loadRuntimeStarterOptions(keyword: string) {
  const kw = String(keyword || '').trim();
  runtimeStarterKeyword.value = kw;
  if (!kw) {
    runtimeStarterOptions.value = [];
    return;
  }
  runtimeStarterLoading.value = true;
  try {
    const where = {
      Logic: 'AND',
      Conditions: [{ Field: 'leave_status', Operator: 'eq', Value: '0' }],
      Groups: [
        {
          Logic: 'OR',
          Conditions: [
            { Field: 'name', Operator: 'contains', Value: kw },
            { Field: 'first_name', Operator: 'contains', Value: kw },
            { Field: 'EMP_ID', Operator: 'contains', Value: kw },
            { Field: 'code', Operator: 'contains', Value: kw },
          ],
          Groups: [],
        },
      ],
    };
    const { items } = await queryForVbenPaged({
      TableName: 'v_t_base_employee',
      Page: 1,
      PageSize: 30,
      SortBy: 'EMP_ID',
      SortOrder: 'asc',
      Where: where,
    });
    const mapped = (items || [])
      .map((r: Record<string, any>) => {
        const id = pickRuntimeField(r, 'id', 'ID');
        const empId = pickRuntimeField(r, 'EMP_ID', 'emp_id', 'code');
        const name = pickRuntimeField(r, 'name', 'NAME', 'first_name');
        if (!id || (!empId && !name)) return null;
        return {
          id,
          empId,
          name: name || empId,
          deptName: pickRuntimeField(r, 'longdeptname', 'Longdeptname', 'deptName', 'dept_name'),
          dutyName: pickRuntimeField(r, 'dutyName', 'DutyName', 'positionName', 'postName'),
          label: `${name || '未命名'}（${empId || id}）`,
        } as RuntimeStarterOption;
      })
      .filter((x): x is RuntimeStarterOption => !!x);
    runtimeStarterOptions.value = mapped;
    for (const item of mapped) {
      runtimeStarterCache.value[item.id] = item;
    }
  } catch (e) {
    runtimeStarterOptions.value = [];
    message.error(`查询模拟发起人失败：${(e as Error).message}`);
  } finally {
    runtimeStarterLoading.value = false;
  }
}

function confirmRuntimeStarter() {
  const selectedId = String(runtimeStarterValue.value || '').trim();
  if (!selectedId) {
    message.warning('请选择模拟发起人');
    return;
  }
  const first = runtimeStarterCache.value[selectedId];
  if (!first) {
    message.warning('未找到已选择的发起人，请重新搜索并选择');
    return;
  }
  runtimeStarterLastPicked.value = first;
  runtimeStarterPickerOpen.value = false;
  const query: Record<string, string> = {};
  if (basicForm.code.trim()) query.processCode = basicForm.code.trim();
  if (currentProcessDefId.value) query.processDefId = currentProcessDefId.value;
  if (runtimeUseDraftDefinition.value) {
    const definition = workflowDesignerRef.value?.getWorkflowDraftSnapshot?.() ?? null;
    if (definition) {
      const draftKey = `${WF_RUNTIME_DRAFT_STORAGE_PREFIX}${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      try {
        localStorage.setItem(
          draftKey,
          JSON.stringify({
            processCode: basicForm.code.trim(),
            processName: basicForm.name.trim(),
            definition,
            createdAt: new Date().toISOString(),
          }),
        );
        query.runtimeDraftKey = draftKey;
      } catch (e) {
        message.warning(`写入运行台草稿失败，将仅使用已发布版本：${(e as Error).message}`);
      }
    }
  }
  query.mockStarterUserId = (first.empId || first.id || '').trim();
  query.mockStarterName = (first.name || '').trim();
  if (first.deptName?.trim()) query.mockStarterDeptName = first.deptName.trim();
  if (first.dutyName?.trim()) query.mockStarterPositionName = first.dutyName.trim();
  const href = router.resolve({
    path: '/workflow/runtime-embed',
    query,
  }).href;
  window.open(href, '_blank', 'noopener,noreferrer,width=1320,height=920');
}

watch(
  () => runtimeStarterPickerOpen.value,
  (v) => {
    if (!v) return;
    runtimeStarterValue.value = runtimeStarterLastPicked.value?.id || undefined;
    if (runtimeStarterLastPicked.value) {
      const p = runtimeStarterLastPicked.value;
      runtimeStarterOptions.value = [p];
      runtimeStarterCache.value[p.id] = p;
      runtimeStarterKeyword.value = p.empId || p.name;
    } else {
      runtimeStarterOptions.value = [];
      runtimeStarterKeyword.value = '';
    }
    runtimeUseDraftDefinition.value = true;
  },
);

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
  if (!k) return '\u672a\u9009\u62e9';
  return findTitleByKey(treeData.value, k) ?? k;
});

/** 传给设计器的基础元数据草稿，用于展示标题/编码/版本号。 */
const designerMetaDraft = computed(() => ({
  processName: basicForm.name,
  processCode: basicForm.code,
  processVersion: basicForm.version,
}));

const activeTab = ref('basic');
/** 流转信息子页签。 */
const activeFlowSubTab = ref('graph');

const uiText = {
  treeTitle: '\u6d41\u7a0b\u76ee\u5f55\uff08\u6570\u636e\u5e93\uff09',
  refreshDir: '\u5237\u65b0\u76ee\u5f55',
  seedDemo: '\u521d\u59cb\u5316\u6f14\u793a\u76ee\u5f55',
  newCategory: '\u65b0\u5efa\u76ee\u5f55',
  newProcess: '\u65b0\u5efa\u6d41\u7a0b',
  edit: '\u7f16\u8f91',
  remove: '\u5220\u9664',
  resizeAria: '\u8c03\u6574\u76ee\u5f55\u9762\u677f\u5bbd\u5ea6',
  resizeTitle: '\u62d6\u62fd\u8c03\u6574\u5bbd\u5ea6',
  currentPrefix: '\u5f53\u524d\uff1a',
  saveDb: '\u4fdd\u5b58\u5230\u6570\u636e\u5e93',
  publish: '\u53d1\u5e03\u5f53\u524d\u7248\u672c',
  preview: '\u9884\u89c8',
  mobilePreview: '\u79fb\u52a8\u7aef\u9884\u89c8',
  runtime: '\u8fd0\u884c\u53f0',
  basicTab: '\u57fa\u7840\u4fe1\u606f',
  flowTab: '\u6d41\u8f6c\u4fe1\u606f',
  code: '\u7f16\u7801',
  name: '\u540d\u79f0',
  version: '\u7248\u672c',
  initiatorScope: '\u53d1\u8d77\u4eba\u8303\u56f4',
  remark: '\u5907\u6ce8',
  isValid: '\u662f\u5426\u6709\u6548',
  phCode: '\u5982\uff1aWF_LEAVE_DEMO',
  phName: '\u5982\uff1a\u52a0\u73ed\u6d41\u7a0b',
  phVersion: '\u5982\uff1a1.0',
  phScope: '\u7528\u4e8e\u63cf\u8ff0\u8be5\u6d41\u7a0b\u53ef\u7531\u54ea\u4e9b\u4eba\u5458/\u7ec4\u7ec7\u53d1\u8d77',
  phRemark: '\u6d41\u7a0b\u7528\u9014\u4e0e\u5907\u6ce8\u8bf4\u660e',
  /** \u4fdd\u5b58\u5230\u6570\u636e\u5e93\u76f8\u5173\u63d0\u793a */
  saveWarnSelectProcess:
    '\u8bf7\u5148\u9009\u62e9\u5de6\u4fa7\u53ef\u7f16\u8f91\u7684\u6d41\u7a0b',
  saveWarnNoDraft:
    '\u65e0\u6cd5\u8bfb\u53d6\u6d41\u7a0b\u8bbe\u8ba1\u6570\u636e\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u6216\u5207\u6362\u5230\u300c\u6d41\u8f6c\u4fe1\u606f\u300d\u9875\u7b7e',
  saveSuccess: '\u5df2\u4fdd\u5b58\u5230\u6570\u636e\u5e93\uff0c\u5f53\u524d\u7248\u672c ',
  errSavePrefix: '\u4fdd\u5b58\u5931\u8d25\uff1a',
  publishWarnNoVer:
    '\u8bf7\u5148\u52a0\u8f7d\u6d41\u7a0b\u5e76\u4fdd\u5b58\u7248\u672c\u540e\u518d\u53d1\u5e03',
  publishSuccess: '\u5df2\u53d1\u5e03\u7248\u672c ',
  errPublishPrefix: '\u53d1\u5e03\u5931\u8d25\uff1a',
} as const;

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
  /** 出口顺序，对应设计器里的 priority。 */
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
  openNodeSettingsFromDblClick?: (nodeId: string) => void;
  openEdgeRuleFromDblClick?: (edgeId: string) => void;
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

watch(
  () => workflowDesignerRef.value,
  () => {
    if (workflowDesignerRef.value && pendingApplyDefinition.value) {
      void nextTick(() => flushPendingDefinitionToDesigner());
    }
  },
);

const nodeInfoRows = ref<NodeInfoTableRow[]>([]);
const exitInfoRows = ref<ExitInfoTableRow[]>([]);

const flowSubSegmentedOptions = [
  { label: '\u56fe\u5f62\u7f16\u8f91\u5668', value: 'graph' },
  { label: '\u8282\u70b9\u4fe1\u606f', value: 'nodes' },
  { label: '\u51fa\u53e3\u6761\u4ef6', value: 'exits' },
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
    label: `${r.nodeName}（${r.nodeType}）`,
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
    message.success(binding ? '节点表单已更新' : '节点表单绑定已清空');
    void nextTick(() => {
      const rows = workflowDesignerRef.value?.getMgmtNodeTableRows?.();
      if (rows) nodeInfoRows.value = rows;
    });
  } else {
    message.error('无法将节点表单变更同步回设计器');
  }
}

function onNodeFormBindingSyncToNodes(payload: {
  nodeIds: string[];
  binding: WfNodeFormBinding;
}) {
  const ids = Array.from(new Set(payload.nodeIds.filter(Boolean)));
  if (!ids.length) {
    message.warning('请选择要同步的节点');
    return;
  }
  let okCount = 0;
  for (const id of ids) {
    const ok = workflowDesignerRef.value?.applyNodeFormBinding?.(id, payload.binding);
    if (ok) okCount += 1;
  }
  if (okCount === ids.length) {
    message.success(`已同步 ${okCount} 个节点`);
  } else {
    message.warning(`仅 ${okCount}/${ids.length} 个节点同步成功，请检查其余节点状态`);
  }
  void nextTick(() => {
    const rows = workflowDesignerRef.value?.getMgmtNodeTableRows?.();
    if (rows) nodeInfoRows.value = rows;
  });
}

function openNodeOperatorSettings(record: NodeInfoTableRow) {
  if (!record?.key) return;
  workflowDesignerRef.value?.openNodeSettingsFromDblClick?.(record.key);
}

const nodeInfoColumns = computed<TableColumnType<NodeInfoTableRow>[]>(() => [
  {
    title: '\u8282\u70b9\u540d\u79f0',
    dataIndex: 'nodeName',
    key: 'nodeName',
    ellipsis: true,
  },
  {
    title: '\u8282\u70b9\u7c7b\u578b',
    dataIndex: 'nodeType',
    key: 'nodeType',
    width: 108,
  },
  {
    title: '\u64cd\u4f5c\u8005',
    dataIndex: 'operator',
    key: 'operator',
    ellipsis: true,
    customRender: ({ record }) =>
      h(
        Button,
        {
          type: 'link',
          size: 'small',
          class: '!h-auto px-0 py-0',
          title: '单击可配置节点办理人',
          onClick: () => openNodeOperatorSettings(record),
        },
        () => record.operator || '未配置',
      ),
  },
  {
    title: '\u8868\u5355\u5185\u5bb9',
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
        () => record.formContent || '\u672a\u7ed1\u5b9a',
      ),
  },
]);

function onDesignerGraphNodeRows(rows: NodeInfoTableRow[]) {
  nodeInfoRows.value = rows;
}

function onDesignerGraphExitRows(rows: ExitInfoTableRow[]) {
  exitInfoRows.value = rows;
}

function openExitConditionSettings(record: ExitInfoTableRow) {
  const edgeId = String(record?.key || '').trim();
  if (!edgeId || edgeId.startsWith('e-')) {
    message.warning('当前出口 ID 无效，无法打开条件配置');
    return;
  }
  workflowDesignerRef.value?.openEdgeRuleFromDblClick?.(edgeId);
}

function onExitPriorityChange(record: ExitInfoTableRow, value: number | null) {
  const edgeId = String(record?.key || '').trim();
  if (!edgeId || edgeId.startsWith('e-')) {
    message.warning('当前出口 ID 无效，无法修改优先级');
    return;
  }
  const next = value == null ? 100 : Math.trunc(value);
  const ok = workflowDesignerRef.value?.applyEdgePriority?.(edgeId, next);
  if (ok) {
    message.success('出口优先级已更新');
    const rows = workflowDesignerRef.value?.getMgmtExitTableRows?.();
    if (rows) exitInfoRows.value = rows;
  } else {
    message.error('未能将出口优先级同步到设计器');
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

  // 重新按顺序分配 priority，步长设为 10，便于后续插入。
  const base = 10;
  for (let i = 0; i < rows.length; i++) {
    const edgeId = String(rows[i]?.key || '').trim();
    if (!edgeId || edgeId.startsWith('e-')) {
      message.warning('存在无效出口 ID，无法重排优先级');
      return;
    }
    const ok = workflowDesignerRef.value?.applyEdgePriority?.(edgeId, (i + 1) * base);
    if (!ok) {
      message.error('未能将重排结果同步到设计器');
      return;
    }
  }
  const latest = workflowDesignerRef.value?.getMgmtExitTableRows?.();
  if (latest) exitInfoRows.value = latest;
  message.success('出口顺序已重排');
}

const exitInfoColumns: TableColumnType<ExitInfoTableRow>[] = [
  {
    title: '\u9009\u4e2d',
    key: 'selected',
    width: 56,
    align: 'center',
    customRender: ({ record }) =>
      h(Checkbox, { checked: record.selected, disabled: true }),
  },
  {
    title: '\u8282\u70b9\u540d\u79f0',
    dataIndex: 'sourceNodeName',
    key: 'sourceNodeName',
    ellipsis: true,
    width: 120,
  },
  {
    title: '\u987a\u5e8f',
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
    title: '\u79fb\u52a8',
    key: 'move',
    width: 92,
    align: 'center',
    customRender: ({ record, index }) =>
      h(Space, { size: 4 }, () => [
        h(
          Button,
          {
            size: 'small',
            type: 'text',
            disabled: (index ?? 0) <= 0,
            title: '\u4e0a\u79fb',
            onClick: () => void moveExitPriority(record, -1),
          },
          () => '\u2191',
        ),
        h(
          Button,
          {
            size: 'small',
            type: 'text',
            disabled: (index ?? 0) >= exitInfoRows.value.length - 1,
            title: '\u4e0b\u79fb',
            onClick: () => void moveExitPriority(record, 1),
          },
          () => '\u2193',
        ),
      ]),
  },
  {
    title: '\u662f\u5426\u9000\u56de',
    key: 'isReturn',
    width: 88,
    align: 'center',
    customRender: ({ record }) =>
      h(Checkbox, { checked: record.isReturn, disabled: true }),
  },
  {
    title: '\u6761\u4ef6',
    key: 'hasCondition',
    width: 100,
    align: 'center',
    customRender: ({ record }) =>
      h(
        Button,
        {
          type: 'link',
          size: 'small',
          class: '!h-auto px-0 py-0',
          onClick: () => openExitConditionSettings(record),
        },
        () => (record.hasCondition ? '\u5df2\u914d\u7f6e' : '\u672a\u914d\u7f6e'),
      ),
  },
  {
    title: '\u9644\u52a0\u89c4\u5219',
    dataIndex: 'extraRulesLabel',
    key: 'extraRulesLabel',
    width: 88,
    align: 'center',
  },
  {
    title: '\u751f\u6210\u7f16\u53f7',
    key: 'generateNumber',
    width: 88,
    align: 'center',
    customRender: ({ record }) =>
      h(Checkbox, { checked: record.generateNumber, disabled: true }),
  },
  {
    title: '\u51fa\u53e3\u540d\u79f0',
    dataIndex: 'exitName',
    key: 'exitName',
    ellipsis: true,
    width: 120,
  },
  {
    title: '\u76ee\u6807\u8282\u70b9',
    dataIndex: 'targetNodeName',
    key: 'targetNodeName',
    ellipsis: true,
    width: 120,
  },
  {
    title: '\u51fa\u53e3\u63d0\u793a\u4fe1\u606f',
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

/** 切换到流转信息页签后，再触发一次设计器自适应。 */
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

function categoryIdContextForNewFolder(): string | undefined {
  const k = selectedKeys.value[0];
  if (!k || typeof k !== 'string') return undefined;
  if (k.startsWith('c-')) return k.slice(2);
  if (k.startsWith('p-')) {
    const pid = k.slice(2);
    const proc = lastTreeSnapshot.value.processes.find((x) => x.id === pid);
    return proc?.categoryId ?? undefined;
  }
  return undefined;
}

function openAddCategoryModal() {
  treeCrudMode.value = 'addCat';
  /** 新建目录时默认置空父目录，由用户主动选择挂载位置。 */
  treeForm.newCategoryParentId = '';
  treeForm.categoryName = '';
  treeForm.folderCode = '';
  treeForm.sortNo = 0;
  treeForm.editingCategoryId = '';
  treeCrudModalOpen.value = true;
}

function openAddProcessModal() {
  treeCrudMode.value = 'addProc';
  treeForm.processCode = '';
  treeForm.processName = '';
  treeForm.processCategoryId = categoryIdContextForNewFolder();
  treeForm.editingProcessId = '';
  treeCrudModalOpen.value = true;
}

function openEditTreeSelection() {
  const k = selectedKeys.value[0];
  if (!k || typeof k !== 'string') {
    message.warning('请先选择要编辑的目录或流程');
    return;
  }
  if (k.startsWith('c-')) {
    const id = k.slice(2);
    const c = lastTreeSnapshot.value.categories.find((x) => x.id === id);
    if (!c) {
      message.error('未找到对应目录信息');
      return;
    }
    treeCrudMode.value = 'editCat';
    treeForm.editingCategoryId = id;
    treeForm.categoryName = c.name;
    treeForm.folderCode = String(c.folderCode ?? '');
    treeForm.sortNo = c.sortNo;
    treeCrudModalOpen.value = true;
    return;
  }
  if (k.startsWith('p-')) {
    const id = k.slice(2);
    const p = lastTreeSnapshot.value.processes.find((x) => x.id === id);
    if (!p) {
      message.error('未找到对应流程信息');
      return;
    }
    treeCrudMode.value = 'editProc';
    treeForm.editingProcessId = id;
    treeForm.processName = p.processName;
    treeForm.processCategoryId = p.categoryId ?? undefined;
    treeForm.processCode = p.processCode;
    treeCrudModalOpen.value = true;
    return;
  }
  message.warning('请选择要编辑的节点');
}

function confirmDeleteTreeSelection() {
  const k = selectedKeys.value[0];
  if (!k || typeof k !== 'string') {
    message.warning('请先选择要删除的目录或流程');
    return;
  }
  const label = findTitleByKey(treeData.value, k) ?? k;
  if (k.startsWith('c-')) {
    Modal.confirm({
      title: `确认删除目录“${label}”吗？`,
      content: '删除后将无法恢复，请确认该目录下已无子目录或流程。',
      okType: 'danger',
      onOk: async () => {
        await wfEngineDeleteCategory({ categoryId: k.slice(2) });
        message.success('目录已删除');
        await loadTree(true);
      },
    });
    return;
  }
  if (k.startsWith('p-')) {
    Modal.confirm({
      title: `确认删除流程“${label}”吗？`,
      content: '删除后将无法恢复，且会影响该流程的历史版本与实例查看。',
      okType: 'danger',
      onOk: async () => {
        await wfEngineDeleteProcess({ processDefId: k.slice(2) });
        message.success('流程已删除');
        await loadTree(true);
      },
    });
  }
}

async function submitTreeCrudModal() {
  treeCrudSubmitting.value = true;
  try {
    if (treeCrudMode.value === 'addCat') {
      const parentIdRaw = String(treeForm.newCategoryParentId ?? '').trim();
      const name = treeForm.categoryName.trim();
      if (!name) {
        message.warning('请输入目录名称');
        throw new Error('validation');
      }
      await wfEngineCreateCategory({
        parentId: parentIdRaw ? parentIdRaw : undefined,
        name,
        folderCode: treeForm.folderCode.trim() || undefined,
        sortNo: treeForm.sortNo,
      });
      message.success('目录已创建');
      treeCrudModalOpen.value = false;
      await loadTree(false);
      return;
    }
    if (treeCrudMode.value === 'addProc') {
      const code = treeForm.processCode.trim();
      const name = treeForm.processName.trim();
      if (!code || !name) {
        message.warning('请输入流程编码和流程名称');
        throw new Error('validation');
      }
      const res = await wfEngineCreateProcess({
        processCode: code,
        processName: name,
        categoryId: treeForm.processCategoryId ?? undefined,
      });
      message.success('流程已创建');
      treeCrudModalOpen.value = false;
      await loadTree(false);
      if (res?.processDefId) selectedKeys.value = [`p-${res.processDefId}`];
      return;
    }
    if (treeCrudMode.value === 'editCat') {
      const name = treeForm.categoryName.trim();
      if (!name) {
        message.warning('请输入目录名称');
        throw new Error('validation');
      }
      await wfEngineUpdateCategory({
        categoryId: treeForm.editingCategoryId,
        name,
        folderCode: treeForm.folderCode.trim() || undefined,
        sortNo: treeForm.sortNo,
      });
      message.success('目录已更新');
      treeCrudModalOpen.value = false;
      await loadTree(false);
      return;
    }
    if (treeCrudMode.value === 'editProc') {
      const name = treeForm.processName.trim();
      if (!name) {
        message.warning('请输入流程名称');
        throw new Error('validation');
      }
      await wfEngineUpdateProcessMeta({
        processDefId: treeForm.editingProcessId,
        processName: name,
        categoryId: treeForm.processCategoryId ?? null,
      });
      message.success('流程已更新');
      treeCrudModalOpen.value = false;
      await loadTree(false);
      if (currentProcessDefId.value === treeForm.editingProcessId) {
        const leafKey = `p-${treeForm.editingProcessId}`;
        selectedKeys.value = [leafKey];
        await loadProcessFromApi(leafKey);
      }
      return;
    }
  } catch (e) {
    if ((e as Error)?.message !== 'validation') {
      message.error(`保存失败：${(e as Error).message}`);
    }
    throw e;
  } finally {
    treeCrudSubmitting.value = false;
  }
}

function onTreeSelect(keys: (number | string)[]) {
  const k = keys[0];
  if (k === undefined || k === null) return;
  const keyStr = String(k);
  const prev = selectedKeys.value[0];
  pushDebugEvent(`tree.select from=${prev || '?'} to=${keyStr}`);
  selectedKeys.value = [keyStr];
  /** 再次点击已选流程时 key 不变，watch 不触发，需手动拉取并灌入画布 */
  if (isProcessLeafKey(keyStr) && keyStr === prev) {
    pendingApplyRetryCount = 0;
    void (async () => {
      await loadProcessFromApi(keyStr);
      scheduleFlushAfterProcessLoad();
    })();
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
        <Card class="wf-mgmt-tree-card" size="small" :title="uiText.treeTitle">
          <Space class="mb-2" direction="vertical" style="width: 100%">
            <Button
              block
              :loading="treeLoading"
              size="small"
              type="default"
              @click="loadTree(false)"
            >
              {{ uiText.refreshDir }}
            </Button>
            <Button block size="small" type="dashed" @click="seedDemoTree">
              {{ uiText.seedDemo }}
            </Button>
            <Space wrap style="width: 100%">
              <Button size="small" type="default" @click="openAddCategoryModal">{{ uiText.newCategory }}</Button>
              <Button size="small" type="default" @click="openAddProcessModal">{{ uiText.newProcess }}</Button>
              <Button
                size="small"
                type="default"
                :disabled="!canEditTreeSelection"
                @click="openEditTreeSelection"
              >
                {{ uiText.edit }}
              </Button>
              <Button
                size="small"
                danger
                type="default"
                :disabled="!canEditTreeSelection"
                @click="confirmDeleteTreeSelection"
              >
                {{ uiText.remove }}
              </Button>
            </Space>
          </Space>
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
        :aria-label="uiText.resizeAria"
        :title="uiText.resizeTitle"
        @mousedown="onSplitterDown"
      />
      <Card class="wf-mgmt-main-card" size="small" :title="`${uiText.currentPrefix}${currentProcessTitle}`">
        <template #extra>
          <Space :size="8" wrap>
            <Button
              size="small"
              type="primary"
              :disabled="!canPersistCurrentProcess"
              @click="saveCurrentToDatabase"
            >
              {{ uiText.saveDb }}
            </Button>
            <Button
              size="small"
              type="default"
              :disabled="
                !canPersistCurrentProcess ||
                  lastLoadedVersionNo == null ||
                  lastLoadedVersionNo < 1
              "
              @click="publishCurrentVersion"
            >
              {{ uiText.publish }}
            </Button>
            <Button
              size="small"
              type="default"
              :disabled="!canPersistCurrentProcess"
              @click="() => openProcessPreviewWindow()"
            >
              {{ uiText.preview }}
            </Button>
            <Button
              size="small"
              type="default"
              :disabled="!canPersistCurrentProcess"
              @click="openProcessPreviewWindow('mobile')"
            >
              {{ uiText.mobilePreview }}
            </Button>
            <Button
              size="small"
              type="default"
              :disabled="!canPersistCurrentProcess"
              @click="openRuntimeWorkbench"
            >
              {{ uiText.runtime }}
            </Button>
          </Space>
        </template>
        <div v-if="showDebugPanel" class="wf-mgmt-debug-panel">
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
          <Tabs.TabPane key="basic" :tab="uiText.basicTab">
            <div class="wf-mgmt-tab-scroll">
              <Form
                :label-col="basicFormLabelCol"
                :model="basicForm"
                :wrapper-col="basicFormWrapperCol"
                class="wf-mgmt-basic-form"
                label-align="right"
                layout="horizontal"
              >
                <Form.Item :label="uiText.code" name="code">
                  <Input
                    v-model:value="basicForm.code"
                    allow-clear
                    :placeholder="uiText.phCode"
                  />
                </Form.Item>
                <Form.Item :label="uiText.name" name="name">
                  <Input
                    v-model:value="basicForm.name"
                    allow-clear
                    :placeholder="uiText.phName"
                  />
                </Form.Item>
                <Form.Item :label="uiText.version" name="version">
                  <Input
                    v-model:value="basicForm.version"
                    allow-clear
                    :placeholder="uiText.phVersion"
                  />
                </Form.Item>
                <Form.Item
                  class="wf-mgmt-form-item-multiline"
                  :label="uiText.initiatorScope"
                  name="initiatorScope"
                >
                  <TextArea
                    v-model:value="basicForm.initiatorScope"
                    :auto-size="{ minRows: 2, maxRows: 6 }"
                    allow-clear
                    :placeholder="uiText.phScope"
                  />
                </Form.Item>
                <Form.Item
                  class="wf-mgmt-form-item-multiline"
                  :label="uiText.remark"
                  name="remark"
                >
                  <TextArea
                    v-model:value="basicForm.remark"
                    :auto-size="{ minRows: 3, maxRows: 8 }"
                    allow-clear
                    :placeholder="uiText.phRemark"
                  />
                </Form.Item>
                <Form.Item :label="uiText.isValid" name="isValid">
                  <Switch v-model:checked="basicForm.isValid" />
                </Form.Item>
              </Form>
            </div>
          </Tabs.TabPane>
          <Tabs.TabPane key="flow" :tab="uiText.flowTab" :force-render="true">
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
                      v-if="canPersistCurrentProcess"
                      ref="workflowDesignerRef"
                      embedded
                      :meta-draft="designerMetaDraft"
                      @canvas-ready="onWorkflowDesignerCanvasReady"
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
                        showTotal: (t: number) => `共 ${t} 条`,
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
                        showTotal: (t: number) => `共 ${t} 条`,
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
        </Tabs>
      </Card>
    </div>
    <Modal
      v-model:open="treeCrudModalOpen"
      :title="treeCrudModalTitle"
      :confirm-loading="treeCrudSubmitting"
      destroy-on-close
      width="520px"
      @ok="submitTreeCrudModal"
    >
      <div v-if="treeCrudMode === 'addCat' || treeCrudMode === 'editCat'" class="flex flex-col gap-3">
        <Form layout="vertical">
          <Form.Item
            v-if="treeCrudMode === 'addCat'"
            label="上级目录"
            extra="不选择则创建为顶级目录，可在后续再调整层级。"
          >
            <Select
              v-model:value="treeForm.newCategoryParentId"
              show-search
              :options="parentCategoryOptionsForNewFolder"
              option-filter-prop="label"
              class="w-full"
            />
          </Form.Item>
          <Form.Item label="目录名称" required>
            <Input v-model:value="treeForm.categoryName" placeholder="请输入目录名称" />
          </Form.Item>
          <Form.Item
            label="目录编码（folder_code）"
            extra="可选，用于与外部系统或初始化脚本做稳定映射。"
          >
            <Input v-model:value="treeForm.folderCode" placeholder="例如 CAT_HR" />
          </Form.Item>
          <Form.Item label="排序号">
            <InputNumber v-model:value="treeForm.sortNo" class="w-full" :min="0" />
          </Form.Item>
        </Form>
      </div>
      <div v-else-if="treeCrudMode === 'addProc'" class="flex flex-col gap-3">
        <Form layout="vertical">
          <Form.Item label="流程编码" required>
            <Input v-model:value="treeForm.processCode" placeholder="请输入流程编码，例如 HR_LEAVE" />
          </Form.Item>
          <Form.Item label="流程名称" required>
            <Input v-model:value="treeForm.processName" placeholder="请输入流程名称" />
          </Form.Item>
          <Form.Item label="所属目录" extra="可选，不选择时会显示在未分类列表。">
            <Select
              v-model:value="treeForm.processCategoryId"
              allow-clear
              show-search
              :options="categorySelectOptions"
              placeholder="请选择目录"
              option-filter-prop="label"
              class="w-full"
            />
          </Form.Item>
        </Form>
      </div>
      <div v-else-if="treeCrudMode === 'editProc'" class="flex flex-col gap-3">
        <Form layout="vertical">
          <Form.Item label="流程编码">
            <Input v-model:value="treeForm.processCode" disabled />
          </Form.Item>
          <Form.Item label="流程名称" required>
            <Input v-model:value="treeForm.processName" />
          </Form.Item>
          <Form.Item label="所属目录" extra="可选，不选择时会显示在未分类列表。">
            <Select
              v-model:value="treeForm.processCategoryId"
              allow-clear
              show-search
              :options="categorySelectOptions"
              placeholder="请选择新的所属目录"
              option-filter-prop="label"
              class="w-full"
            />
          </Form.Item>
        </Form>
      </div>
    </Modal>
    <NodeFormBindingModal
      v-model:open="nodeFormBindingOpen"
      :node-id="nodeFormBindingNodeId"
      :node-name="nodeFormBindingNodeName"
      :initial-binding="nodeFormBindingInitial"
      :node-options="nodeBindingSyncOptions"
      @saved="onNodeFormBindingSaved"
      @sync-to-nodes="onNodeFormBindingSyncToNodes"
    />
    <Modal
      v-model:open="runtimeStarterPickerOpen"
      :title="'\u9009\u62e9\u6a21\u62df\u53d1\u8d77\u4eba'"
      :confirm-loading="runtimeStarterLoading"
      width="520px"
      @ok="confirmRuntimeStarter"
    >
      <Form layout="vertical">
        <Form.Item :label="'\u6a21\u62df\u53d1\u8d77\u4eba'" required>
          <Select
            v-model:value="runtimeStarterValue"
            show-search
            :filter-option="false"
            :options="runtimeStarterSelectOptions"
            :loading="runtimeStarterLoading"
            :not-found-content="runtimeStarterKeyword ? '\u672a\u627e\u5230\u5339\u914d\u4eba\u5458' : '\u8bf7\u8f93\u5165\u5173\u952e\u5b57\u641c\u7d22'"
            :placeholder="'\u8bf7\u8f93\u5165\u5de5\u53f7/\u59d3\u540d\u641c\u7d22\uff0c\u5982 A8425'"
            @search="loadRuntimeStarterOptions"
          />
        </Form.Item>
        <Form.Item>
          <Checkbox v-model:checked="runtimeUseDraftDefinition">
            同时携带当前编辑中的草稿定义进入运行台
          </Checkbox>
        </Form.Item>
      </Form>
    </Modal>
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
