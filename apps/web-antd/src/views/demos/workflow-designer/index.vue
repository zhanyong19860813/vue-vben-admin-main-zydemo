<script setup lang="ts">
import type {
  WfAssigneeStrategy,
  WfEdgeConditionRule,
  WfNodeProperties,
} from './workflow-definition.schema';

import type {
  OrgDeptManagerItem,
  OrgPersonnelItem,
  OrgRoleItem,
} from '#/components/org-picker/types';

import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';

import { IconifyIcon } from '@vben/icons';

import LogicFlow from '@logicflow/core';
import { useFullscreen } from '@vueuse/core';
import {
  Button,
  Card,
  Checkbox,
  Collapse,
  Input,
  InputNumber,
  message,
  Modal,
  Select,
  Space,
  Tag,
  Tooltip,
} from 'ant-design-vue';

import {
  publishWorkflowDefinition,
  saveWorkflowDefinition,
} from '#/api/workflow';
import SelectDeptManagerModal from '#/components/org-picker/SelectDeptManagerModal.vue';
import SelectPersonnelModal from '#/components/org-picker/SelectPersonnelModal.vue';
import SelectRoleModal from '#/components/org-picker/SelectRoleModal.vue';

import {
  buildEdgeConditionProperties,
  createDefaultWfDefinitionMeta,
  summarizeEdgeRules,
  summarizeRuleGroups,
  WF_SCHEMA_VERSION,
} from './workflow-definition.schema';
import WorkflowNodeSettingsModal from './WorkflowNodeSettingsModal.vue';

import '@logicflow/core/es/style/index.css';

const processName = ref('请假审批流程（LogicFlow）');
const processCode = ref('WF_LEAVE_DEMO');
const processVersion = ref(1);
const storageKey = computed(
  () => `workflow-designer-layout:${processCode.value || 'default'}`,
);
const jsonText = ref('');
const canvasRef = ref<HTMLElement | null>(null);
/** 全屏目标：整块设计区（顶栏 + 工具条 + 三栏） */
const studioRef = ref<HTMLElement | null>(null);
const { isFullscreen, toggle: toggleStudioFullscreen } =
  useFullscreen(studioRef);

const selectedNodeId = ref('');
const selectedEdgeId = ref('');
const selectedNodeType = ref('rect');
const selectedNodeName = ref('');
const selectedAssignee = ref('');
const selectedDesc = ref('');
const selectedEdgeCondition = ref('');
const selectedEdgePriority = ref(0);
/** 多个条件组之间为 OR，组内 rules 为 AND */
const edgeGroups = ref<{ rules: WfEdgeConditionRule[] }[]>([
  { rules: [{ scope: 'form', key: '', op: '==', value: '' as any }] },
]);

const assigneeStrategyKindOptions = [
  { label: '指定用户', value: 'user' },
  { label: '角色', value: 'role' },
  { label: '部门主管', value: 'dept_manager' },
  { label: '岗位', value: 'position' },
  { label: '表单字段(用户ID)', value: 'form_field' },
  { label: '表达式(预留)', value: 'expression' },
];

const assigneeStrategies = ref<WfAssigneeStrategy[]>([]);
const behaviorCc = ref(false);
const behaviorCountersign = ref(false);
const behaviorSign = ref(false);

const ccStrategies = ref<WfAssigneeStrategy[]>([]);
const personPickerOpen = ref(false);
const personPickerDefaults = ref<OrgPersonnelItem[]>([]);
const personPickerTarget = ref<null | {
  index: number;
  list: 'assignee' | 'cc';
}>(null);
const rolePickerOpen = ref(false);
const rolePickerTarget = ref<null | { index: number; list: 'assignee' | 'cc' }>(
  null,
);
const deptManagerPickerOpen = ref(false);
const deptManagerPickerTarget = ref<null | {
  index: number;
  list: 'assignee' | 'cc';
}>(null);
const countersignMode = ref<'all' | 'any' | 'percent'>('all');
const countersignPercent = ref<number>(100);
const signKind = ref<'any' | 'electronic' | 'handwriting'>('electronic');

/** 双击开始/审批节点：弹窗编辑 */
const nodeSettingsOpen = ref(false);
const nodeSettingsBizType = ref<'approve' | 'start'>('approve');
const nodeSettingsNodeId = ref('');
const nodeSettingsInitialProps = ref<Record<string, unknown>>({});
const nodeSettingsInitialName = ref('');
const nodeSettingsAllNodes = ref<
  { id: string; isPrior?: boolean; label: string }[]
>([]);

const countersignModeOptions = [
  { label: '全员通过(all)', value: 'all' },
  { label: '任一人(any)', value: 'any' },
  { label: '按比例(percent)', value: 'percent' },
];

const signKindOptions = [
  { label: '电子签', value: 'electronic' },
  { label: '手写签', value: 'handwriting' },
  { label: '任意', value: 'any' },
];

const conditionScopeOptions = [
  { label: '表单字段', value: 'form' },
  { label: '发起人上下文', value: 'initiator' },
];

const conditionOpOptions = [
  { label: '==', value: '==' },
  { label: '!=', value: '!=' },
  { label: '>', value: '>' },
  { label: '>=', value: '>=' },
  { label: '<', value: '<' },
  { label: '<=', value: '<=' },
  { label: '包含', value: 'contains' },
  { label: '前缀', value: 'startsWith' },
  { label: '后缀', value: 'endsWith' },
  { label: '在列表中', value: 'in' },
  { label: '不在列表中', value: 'notIn' },
  { label: '列表任命中(角色/岗位)', value: 'containsAny' },
];

let lf: any = null;

/** 适应画布内边距（LogicFlow fitView：上下、左右） */
const FIT_VIEW_PADDING_V = 40;
const FIT_VIEW_PADDING_H = 48;

const zoomPercent = ref(100);
const graphStats = ref({ nodeCount: 0, edgeCount: 0 });

function refreshTransformUi() {
  if (!lf) return;
  const t = lf.getTransform?.() ?? { SCALE_X: 1 };
  zoomPercent.value = Math.round((t.SCALE_X || 1) * 100);
}

/** 将整图缩放到可视区域（进入页、导入、加载后需等布局完成再算尺寸） */
function scheduleFitGraphToView() {
  void nextTick(() => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        if (!lf) return;
        lf.fitView?.(FIT_VIEW_PADDING_V, FIT_VIEW_PADDING_H);
        refreshTransformUi();
      });
    });
  });
}

function updateGraphStats() {
  if (!lf) return;
  try {
    const d = lf.getGraphData?.() ?? { nodes: [], edges: [] };
    graphStats.value = {
      nodeCount: Array.isArray(d.nodes) ? d.nodes.length : 0,
      edgeCount: Array.isArray(d.edges) ? d.edges.length : 0,
    };
  } catch {
    graphStats.value = { nodeCount: 0, edgeCount: 0 };
  }
}

function zoomIn() {
  if (!lf) return;
  lf.zoom(true);
  refreshTransformUi();
}

function zoomOut() {
  if (!lf) return;
  lf.zoom(false);
  refreshTransformUi();
}

function fitCanvas() {
  if (!lf) return;
  lf.fitView?.(FIT_VIEW_PADDING_V, FIT_VIEW_PADDING_H);
  refreshTransformUi();
}

function undoGraph() {
  lf?.undo?.();
  updateGraphStats();
}

function redoGraph() {
  lf?.redo?.();
  updateGraphStats();
}

function clearCanvas() {
  Modal.confirm({
    title: '清空画布',
    content: '将删除画布上全部节点与连线，是否继续？',
    okText: '清空',
    okType: 'danger',
    cancelText: '取消',
    onOk() {
      lf?.clearData?.();
      selectedNodeId.value = '';
      selectedEdgeId.value = '';
      updateGraphStats();
      refreshTransformUi();
      message.success('已清空画布');
    },
  });
}

function ruleValueToString(v: unknown): string {
  if (v === undefined || v === null) return '';
  if (Array.isArray(v)) return JSON.stringify(v);
  return String(v);
}

const nodeTypeOptions = [
  { label: '开始节点', value: 'start' },
  { label: '审批节点', value: 'approve' },
  { label: '条件分支', value: 'condition' },
  { label: '抄送节点', value: 'cc' },
  { label: '结束节点', value: 'end' },
];

function mapToLfType(type: string) {
  if (type === 'condition') return 'diamond';
  if (type === 'start' || type === 'end') return 'circle';
  return 'rect';
}

function mapFromLfType(type: string) {
  if (type === 'diamond') return 'condition';
  if (type === 'circle') return 'approve';
  return 'approve';
}

/** LogicFlow 支持在 properties.style 上覆盖节点描边/填充（见 Rect/Circle/DiamondNodeModel#getNodeStyle） */
function nodeStyleFor(
  bizType: string,
  lfType: string,
): Record<string, number | string> {
  if (lfType === 'circle') {
    if (bizType === 'end') {
      return { fill: '#fff1f2', stroke: '#f43f5e', strokeWidth: 2 };
    }
    return { fill: '#ecfdf5', stroke: '#22c55e', strokeWidth: 2 };
  }
  if (lfType === 'diamond') {
    return { fill: '#fff7ed', stroke: '#f97316', strokeWidth: 2 };
  }
  if (bizType === 'cc') {
    return { fill: '#f5f3ff', stroke: '#8b5cf6', strokeWidth: 1.5, radius: 10 };
  }
  return { fill: '#eff6ff', stroke: '#3b82f6', strokeWidth: 1.5, radius: 10 };
}

/** 为旧数据或缺少 style 的节点补全样式，避免与左侧节点库视觉不一致 */
function ensureGraphNodeStyles(graphData: { nodes?: any[] }) {
  if (!graphData?.nodes?.length) return;
  for (const n of graphData.nodes) {
    let biz = n.properties?.bizType;
    if (!biz) {
      switch (n.type) {
        case 'circle': {
          const tv = String(n.text?.value ?? n.text ?? '');
          biz = /结束|完成/.test(tv) ? 'end' : 'start';

          break;
        }
        case 'diamond': {
          biz = 'condition';
          break;
        }
        case 'rect': {
          biz = 'approve';
          break;
        }
        default: {
          biz = 'approve';
        }
      }
    }
    const preset = nodeStyleFor(biz, n.type);
    n.properties = {
      ...n.properties,
      bizType: biz,
      style: { ...preset, ...n.properties?.style },
    };
  }
}

function getDefaultGraphData() {
  return {
    nodes: [
      {
        id: 'N1',
        type: 'circle',
        x: 120,
        y: 220,
        text: '发起申请',
        properties: {
          bizType: 'start',
          assignee: '发起人',
          style: nodeStyleFor('start', 'circle'),
        },
      },
      {
        id: 'N2',
        type: 'rect',
        x: 320,
        y: 220,
        text: '部门审批',
        properties: {
          bizType: 'approve',
          assignee: '部门负责人',
          style: nodeStyleFor('approve', 'rect'),
        },
      },
      {
        id: 'N3',
        type: 'diamond',
        x: 520,
        y: 220,
        text: '金额条件',
        properties: {
          bizType: 'condition',
          assignee: '系统',
          style: nodeStyleFor('condition', 'diamond'),
        },
      },
      {
        id: 'N4',
        type: 'rect',
        x: 720,
        y: 220,
        text: '总经理审批',
        properties: {
          bizType: 'approve',
          assignee: '总经理',
          style: nodeStyleFor('approve', 'rect'),
        },
      },
      {
        id: 'N5',
        type: 'circle',
        x: 900,
        y: 220,
        text: '流程结束',
        properties: {
          bizType: 'end',
          assignee: '系统',
          style: nodeStyleFor('end', 'circle'),
        },
      },
    ],
    edges: [
      { id: 'E1', type: 'polyline', sourceNodeId: 'N1', targetNodeId: 'N2' },
      { id: 'E2', type: 'polyline', sourceNodeId: 'N2', targetNodeId: 'N3' },
      { id: 'E3', type: 'polyline', sourceNodeId: 'N3', targetNodeId: 'N4' },
      { id: 'E4', type: 'polyline', sourceNodeId: 'N4', targetNodeId: 'N5' },
    ],
  };
}

function openNodeSettingsFromDblClick(nodeId: string) {
  if (!lf) return;
  const node = lf.getNodeModelById(nodeId);
  if (!node) return;
  const biz = (node.properties?.bizType as string) || mapFromLfType(node.type);
  if (biz !== 'start' && biz !== 'approve') return;
  nodeSettingsBizType.value = biz as 'approve' | 'start';
  nodeSettingsNodeId.value = node.id;
  nodeSettingsInitialName.value = node.text?.value || '';
  nodeSettingsInitialProps.value = { ...node.properties };
  try {
    const gd = lf.getGraphData?.() ?? { edges: [], nodes: [] };
    const reverse = new Map<string, string[]>();
    for (const e of gd.edges || []) {
      const s = String(e.sourceNodeId || '').trim();
      const t = String(e.targetNodeId || '').trim();
      if (!s || !t) continue;
      if (!reverse.has(t)) reverse.set(t, []);
      reverse.get(t)!.push(s);
    }
    const priorIds = new Set<string>();
    const stack = [node.id];
    while (stack.length > 0) {
      const cur = stack.pop()!;
      const prev = reverse.get(cur) || [];
      for (const p of prev) {
        if (priorIds.has(p)) continue;
        priorIds.add(p);
        stack.push(p);
      }
    }
    nodeSettingsAllNodes.value = (gd.nodes || []).map(
      (n: { id: string; text?: { value?: string } }) => ({
        id: n.id,
        isPrior: priorIds.has(n.id) && n.id !== node.id,
        label: n.text?.value || n.id,
      }),
    );
  } catch {
    nodeSettingsAllNodes.value = [];
  }
  nodeSettingsOpen.value = true;
}

function onNodeSettingsSave(payload: {
  nodeId: string;
  nodeName: string;
  properties: Record<string, unknown> & WfNodeProperties;
}) {
  if (!lf) return;
  lf.updateText(payload.nodeId, payload.nodeName);
  const nm = lf.getNodeModelById(payload.nodeId);
  const lfShape = nm?.type ? String(nm.type) : 'rect';
  const biz = String(
    payload.properties.bizType ?? nm?.properties?.bizType ?? 'approve',
  );
  lf.setProperties(payload.nodeId, {
    ...payload.properties,
    style: nodeStyleFor(biz, lfShape),
  });
  refreshSelectedNodePanel(payload.nodeId);
  message.success('已保存节点设置');
}

function refreshSelectedNodePanel(nodeId: string) {
  if (!lf || !nodeId) return;
  const node = lf.getNodeModelById(nodeId);
  if (!node) return;
  selectedNodeId.value = node.id;
  selectedNodeType.value = node.properties?.bizType || mapFromLfType(node.type);
  selectedNodeName.value = node.text?.value || '';
  selectedAssignee.value = node.properties?.assignee || '';
  selectedDesc.value = node.properties?.desc || '';
  const strategies = node.properties?.assigneeStrategies;
  assigneeStrategies.value = Array.isArray(strategies)
    ? strategies.map((s: WfAssigneeStrategy) => ({ ...s }))
    : [];
  const b = node.properties?.behaviors || {};
  behaviorCc.value = !!b.cc;
  behaviorCountersign.value = !!b.countersign;
  behaviorSign.value = !!b.signRequired;
  const ccList = node.properties?.ccStrategies;
  ccStrategies.value = Array.isArray(ccList)
    ? ccList.map((s: WfAssigneeStrategy) => ({ ...s }))
    : [];
  const cp = node.properties?.countersignPolicy;
  countersignMode.value = (cp?.mode as 'all' | 'any' | 'percent') || 'all';
  countersignPercent.value =
    cp?.percent !== undefined && cp?.percent !== null
      ? Number(cp.percent)
      : 100;
  const sp = node.properties?.signPolicy;
  signKind.value =
    (sp?.kind as 'any' | 'electronic' | 'handwriting') || 'electronic';

  selectedEdgeId.value = '';
  selectedEdgeCondition.value = '';
  edgeGroups.value = [
    { rules: [{ scope: 'form', key: '', op: '==', value: '' as any }] },
  ];
  selectedEdgePriority.value = 0;
}

function refreshSelectedEdgePanel(edgeId: string) {
  if (!lf || !edgeId) return;
  const edge = lf.getEdgeModelById(edgeId);
  if (!edge) return;
  selectedEdgeId.value = edge.id;
  selectedEdgeCondition.value =
    edge.properties?.condition || edge.text?.value || '';
  selectedEdgePriority.value = Number(edge.properties?.priority ?? 0);
  const rg = edge.properties?.ruleGroups as
    | undefined
    | { anyOf?: { allOf: WfEdgeConditionRule[] }[] };
  if (rg?.anyOf?.length) {
    edgeGroups.value = rg.anyOf.map((g) => ({
      rules: (g.allOf || []).map((r: WfEdgeConditionRule) => ({
        scope: r.scope || 'form',
        key: r.key || '',
        op: r.op || '==',
        value: ruleValueToString(r.value) as any,
      })),
    }));
    if (edgeGroups.value.length === 0) {
      edgeGroups.value = [
        { rules: [{ scope: 'form', key: '', op: '==', value: '' as any }] },
      ];
    }
  } else {
    const rawRules = edge.properties?.rules;
    edgeGroups.value =
      Array.isArray(rawRules) && rawRules.length > 0
        ? [
            {
              rules: rawRules.map((r: WfEdgeConditionRule) => ({
                scope: r.scope || 'form',
                key: r.key || '',
                op: r.op || '==',
                value: ruleValueToString(r.value) as any,
              })),
            },
          ]
        : [{ rules: [{ scope: 'form', key: '', op: '==', value: '' as any }] }];
  }
  selectedNodeId.value = '';
}

function initLogicFlow(data?: any) {
  if (!canvasRef.value) return;
  lf = new LogicFlow({
    container: canvasRef.value,
    grid: {
      size: 20,
      type: 'dot',
      visible: true,
      config: {
        color: '#c7d2e0',
        thickness: 1.2,
      },
    },
    keyboard: { enabled: true },
    stopScrollGraph: false,
    stopZoomGraph: false,
    edgeTextDraggable: true,
    style: {
      baseNode: {
        fill: '#ffffff',
        stroke: '#94a3b8',
        strokeWidth: 1,
      },
      baseEdge: {
        stroke: '#64748b',
        strokeWidth: 1.5,
      },
      rect: {
        radius: 10,
      },
      circle: {},
      diamond: {},
      nodeText: {
        color: '#0f172a',
        fontSize: 13,
        fontWeight: 500,
      },
      edgeText: {
        fontSize: 12,
        color: '#334155',
        background: {
          fill: '#ffffff',
          stroke: '#e2e8f0',
        },
      },
    },
  });

  const raw = data || getDefaultGraphData();
  if (raw?.nodes) ensureGraphNodeStyles(raw);
  lf.render(raw);
  scheduleFitGraphToView();

  lf.on('node:click', ({ data: nodeData }: any) => {
    refreshSelectedNodePanel(nodeData.id);
  });
  lf.on('edge:click', ({ data: edgeData }: any) => {
    refreshSelectedEdgePanel(edgeData.id);
  });
  lf.on('node:dbclick', ({ data: nodeData }: any) => {
    openNodeSettingsFromDblClick(nodeData.id);
  });
  ['node:add', 'node:delete', 'edge:add', 'edge:delete'].forEach((ev) => {
    lf.on(ev, () => updateGraphStats());
  });
  lf.on('graph:transform', () => refreshTransformUi());
  refreshTransformUi();
  updateGraphStats();
}

function addNode(type: string) {
  if (!lf) return;
  const lfType = mapToLfType(type);
  const id = `N${Date.now()}`;
  lf.addNode({
    id,
    type: lfType,
    x: 220 + Math.floor(Math.random() * 400),
    y: 120 + Math.floor(Math.random() * 220),
    text: nodeTypeOptions.find((n) => n.value === type)?.label || '新节点',
    properties: {
      bizType: type,
      assignee: (() => {
        if (type === 'start') return '发起人';
        if (type === 'end') return '系统';
        return '待设置';
      })(),
      desc: '',
      style: nodeStyleFor(type, lfType),
    },
  });
}

function removeSelectedNode() {
  if (!lf || !selectedNodeId.value) return;
  lf.deleteNode(selectedNodeId.value);
  selectedNodeId.value = '';
}

function applyNodeProperty() {
  if (!lf || !selectedNodeId.value) return;
  lf.updateText(selectedNodeId.value, selectedNodeName.value || '未命名节点');
  const baseProps: Record<string, unknown> = {
    bizType: selectedNodeType.value,
    assignee: selectedAssignee.value,
    desc: selectedDesc.value,
    assigneeStrategies: assigneeStrategies.value.filter(
      (s) => s.kind && (s.value?.trim() || s.kind === 'dept_manager'),
    ),
    behaviors: {
      cc: behaviorCc.value,
      countersign: behaviorCountersign.value,
      signRequired: behaviorSign.value,
    },
    wfSchemaVersion: WF_SCHEMA_VERSION,
    ccStrategies: behaviorCc.value
      ? ccStrategies.value.filter(
          (s) => s.kind && (s.value?.trim() || s.kind === 'dept_manager'),
        )
      : [],
    countersignPolicy: behaviorCountersign.value
      ? {
          mode: countersignMode.value,
          percent:
            countersignMode.value === 'percent'
              ? countersignPercent.value
              : undefined,
        }
      : undefined,
    signPolicy: behaviorSign.value
      ? {
          required: true,
          kind: signKind.value,
        }
      : { required: false, kind: signKind.value },
  };
  const nm = lf.getNodeModelById(selectedNodeId.value);
  const lfShape = nm?.type ? String(nm.type) : 'rect';
  lf.setProperties(selectedNodeId.value, {
    ...baseProps,
    style: nodeStyleFor(String(selectedNodeType.value), lfShape),
  });
  message.success('已更新节点属性');
}

function parseRuleValue(
  raw: string,
): boolean | number | number[] | string | string[] {
  const t = raw.trim();
  if (t === 'true') return true;
  if (t === 'false') return false;
  if (/^-?\d+(?:\.\d+)?$/.test(t)) return Number(t);
  if (t.startsWith('[') || t.startsWith('{')) {
    try {
      return JSON.parse(t) as string[];
    } catch {
      return raw;
    }
  }
  return raw;
}

function applyEdgeCondition() {
  if (!lf || !selectedEdgeId.value) return;
  const groupsPayload = edgeGroups.value.map((g) =>
    g.rules
      .filter((r) => r.key.trim())
      .map((r) => ({
        scope: r.scope,
        key: r.key.trim(),
        op: r.op,
        value:
          typeof r.value === 'string'
            ? parseRuleValue(r.value)
            : (r.value as boolean | number | number[] | string | string[]),
      })),
  );
  const edgePart = buildEdgeConditionProperties({
    priority: selectedEdgePriority.value,
    groups: groupsPayload,
    conditionFallback: selectedEdgeCondition.value,
  });
  const summary =
    summarizeRuleGroups(edgePart.ruleGroups) ||
    summarizeEdgeRules(edgePart.rules?.length ? edgePart.rules : undefined) ||
    selectedEdgeCondition.value.trim();
  lf.setProperties(selectedEdgeId.value, {
    ...edgePart,
  });
  lf.updateText(selectedEdgeId.value, summary);
  message.success('已更新连线条件');
}

function addAssigneeRow() {
  assigneeStrategies.value.push({ kind: 'user', value: '', label: '' });
}

function removeAssigneeRow(i: number) {
  assigneeStrategies.value.splice(i, 1);
}

function addCcRow() {
  ccStrategies.value.push({ kind: 'user', value: '', label: '' });
}

function removeCcRow(i: number) {
  ccStrategies.value.splice(i, 1);
}

function onStrategyKindChange(row: WfAssigneeStrategy) {
  if (row.kind === 'dept_manager') {
    row.value = row.value || '';
    row.label = row.label || '部门主管';
    return;
  }
  if (row.kind === 'user' || row.kind === 'role') {
    row.value = row.value || '';
    return;
  }
  if (row.label === '部门主管') {
    row.value = '';
    row.label = '';
  }
}

function openPersonPicker(target: { index: number; list: 'assignee' | 'cc' }) {
  personPickerTarget.value = target;
  personPickerDefaults.value = [];
  personPickerOpen.value = true;
}

function applyPickedPeople(items: OrgPersonnelItem[]) {
  const target = personPickerTarget.value;
  if (!target) return;
  const list =
    target.list === 'assignee' ? assigneeStrategies.value : ccStrategies.value;
  const row = list[target.index];
  if (!row) return;
  row.kind = 'user';
  row.value = items
    .map((x) => String(x.empId || '').trim())
    .filter(Boolean)
    .join(',');
  row.label = items
    .map((x) => {
      const empId = String(x.empId || '').trim();
      const name = String(x.name || '').trim();
      return [empId, name].filter(Boolean).join('/');
    })
    .filter(Boolean)
    .join('、');
}

function openRolePicker(target: { index: number; list: 'assignee' | 'cc' }) {
  rolePickerTarget.value = target;
  rolePickerOpen.value = true;
}

function applyPickedRoles(items: OrgRoleItem[]) {
  const target = rolePickerTarget.value;
  if (!target) return;
  const list =
    target.list === 'assignee' ? assigneeStrategies.value : ccStrategies.value;
  const row = list[target.index];
  if (!row) return;
  row.kind = 'role';
  row.value = items
    .map((x) => String(x.id || '').trim())
    .filter(Boolean)
    .join(',');
  row.label = items
    .map((x) => String(x.name || '').trim())
    .filter(Boolean)
    .join('、');
}

function openDeptManagerPicker(target: {
  index: number;
  list: 'assignee' | 'cc';
}) {
  deptManagerPickerTarget.value = target;
  deptManagerPickerOpen.value = true;
}

function applyPickedDeptManagers(items: OrgDeptManagerItem[]) {
  const target = deptManagerPickerTarget.value;
  if (!target) return;
  const list =
    target.list === 'assignee' ? assigneeStrategies.value : ccStrategies.value;
  const row = list[target.index];
  if (!row) return;
  const empIds = [
    ...new Set(
      items.flatMap((x) =>
        (x.managerEmpIds ?? []).map((v) => String(v).trim()).filter(Boolean),
      ),
    ),
  ];
  const mgrNames = [
    ...new Set(
      items.flatMap((x) =>
        (x.managerNames ?? []).map((v) => String(v).trim()).filter(Boolean),
      ),
    ),
  ];
  row.kind = 'dept_manager';
  row.value = empIds.join(',');
  row.label =
    items.length > 0
      ? `部门主管：${mgrNames.length > 0 ? mgrNames.join('、') : '未维护'}`
      : '部门主管';
  if (empIds.length === 0) {
    message.warning(
      '所选部门未维护主管工号（manager），已仅保存标签，请先维护部门主管后再用。',
    );
  }
}

function addEdgeRuleRow(groupIndex: number) {
  const g = edgeGroups.value[groupIndex];
  if (!g) return;
  g.rules.push({ scope: 'form', key: '', op: '==', value: '' as any });
}

function removeEdgeRuleRow(groupIndex: number, ruleIndex: number) {
  const g = edgeGroups.value[groupIndex];
  if (!g) return;
  g.rules.splice(ruleIndex, 1);
  if (g.rules.length === 0)
    g.rules.push({ scope: 'form', key: '', op: '==', value: '' as any });
}

function addEdgeGroup() {
  edgeGroups.value.push({
    rules: [{ scope: 'form', key: '', op: '==', value: '' as any }],
  });
}

function removeEdgeGroup(groupIndex: number) {
  if (edgeGroups.value.length <= 1) return;
  edgeGroups.value.splice(groupIndex, 1);
}

function buildDefinitionPayload(extra: Record<string, unknown> = {}) {
  return {
    processName: processName.value,
    processCode: processCode.value,
    processVersion: processVersion.value,
    wfMeta: createDefaultWfDefinitionMeta(),
    graphData: lf?.getGraphData?.() ?? { nodes: [], edges: [] },
    ...extra,
  };
}

function exportCurrentJson() {
  if (!lf) return;
  const payload = buildDefinitionPayload({
    exportedAt: new Date().toISOString(),
  });
  jsonText.value = JSON.stringify(payload, null, 2);
  message.success('已导出 LogicFlow JSON');
}

function saveLayout() {
  if (!lf) return;
  try {
    const payload = buildDefinitionPayload({
      savedAt: new Date().toISOString(),
    });
    jsonText.value = JSON.stringify(payload, null, 2);
    localStorage.setItem(storageKey.value, jsonText.value);
    message.success('已保存布局到 localStorage');
  } catch (error) {
    message.error(`保存失败：${(error as Error).message}`);
  }
}

async function saveToServer() {
  if (!lf) return;
  const definitionJson = JSON.stringify(buildDefinitionPayload(), null, 2);
  const resp = await saveWorkflowDefinition({
    processCode: processCode.value,
    processName: processName.value,
    definitionJson,
  });
  processVersion.value = Number(resp?.version ?? processVersion.value);
  message.success('已保存到后端草稿版本');
}

function loadSavedLayout() {
  const raw = localStorage.getItem(storageKey.value);
  if (!raw) return;
  try {
    const parsed = JSON.parse(raw);
    processName.value = parsed.processName ?? processName.value;
    processVersion.value = Number(
      parsed.processVersion ?? processVersion.value,
    );
    if (parsed?.graphData?.nodes) {
      ensureGraphNodeStyles(parsed.graphData);
      lf?.render(parsed.graphData);
      scheduleFitGraphToView();
      updateGraphStats();
    }
    jsonText.value = JSON.stringify(parsed, null, 2);
    message.success('已加载已保存布局');
  } catch (error) {
    message.error(`加载失败：${(error as Error).message}`);
  }
}

function importJsonLayout() {
  if (!jsonText.value.trim()) {
    message.warning('请先粘贴 JSON');
    return;
  }
  try {
    const parsed = JSON.parse(jsonText.value);
    if (!parsed?.graphData?.nodes)
      throw new Error('JSON 中缺少 graphData.nodes');
    processName.value = parsed.processName ?? processName.value;
    processCode.value = parsed.processCode ?? processCode.value;
    processVersion.value = Number(
      parsed.processVersion ?? processVersion.value,
    );
    ensureGraphNodeStyles(parsed.graphData);
    lf?.render(parsed.graphData);
    scheduleFitGraphToView();
    updateGraphStats();
    localStorage.setItem(storageKey.value, JSON.stringify(parsed, null, 2));
    message.success('导入成功并已保存');
  } catch (error) {
    message.error(`导入失败：${(error as Error).message}`);
  }
}

async function publishFlow() {
  const resp = await publishWorkflowDefinition({
    processCode: processCode.value,
    version: processVersion.value,
  });
  processVersion.value = Number(resp?.version ?? processVersion.value);
  message.success('流程已发布');
}

watch(isFullscreen, () => {
  void nextTick(() => {
    requestAnimationFrame(() => {
      if (!lf) return;
      lf.resize?.();
      refreshTransformUi();
    });
  });
});

onMounted(() => {
  initLogicFlow();
  loadSavedLayout();
});

onBeforeUnmount(() => {
  lf?.destroy();
  lf = null;
});
</script>

<template>
  <div class="wf-designer-root">
    <div ref="studioRef" class="wf-studio">
      <!-- 顶栏：流程标识 + 主要操作 -->
      <header class="wf-topbar">
        <div class="wf-topbar-left">
          <span class="wf-pipe"></span>
          <div class="wf-title-block">
            <span class="wf-title-label">流程名称</span>
            <Input
              v-model:value="processName"
              class="wf-title-input"
              placeholder="如：请假审批流程"
            />
          </div>
          <div class="wf-meta-block">
            <span class="wf-meta-label">编码</span>
            <Input
              v-model:value="processCode"
              class="wf-meta-input"
              placeholder="processCode"
            />
            <span class="wf-meta-label">版本</span>
            <InputNumber
              v-model:value="processVersion"
              :min="1"
              :precision="0"
              class="wf-ver-input"
            />
          </div>
        </div>
        <Space wrap class="wf-topbar-right" :size="8">
          <Button type="primary" @click="saveToServer">保存到后端</Button>
          <Button @click="publishFlow">发布流程</Button>
          <Button type="primary" ghost @click="exportCurrentJson">
            导出 JSON
          </Button>
        </Space>
      </header>

      <!-- 工具条：撤销 / 缩放 / 统计 / 清空 -->
      <div class="wf-toolbar">
        <Space :size="4" wrap>
          <Tooltip title="撤销 (Ctrl+Z)">
            <Button size="small" @click="undoGraph">撤销</Button>
          </Tooltip>
          <Tooltip title="重做 (Ctrl+Shift+Z)">
            <Button size="small" @click="redoGraph">重做</Button>
          </Tooltip>
          <span class="wf-toolbar-divider"></span>
          <Tooltip title="缩小">
            <Button size="small" @click="zoomOut">−</Button>
          </Tooltip>
          <span class="wf-zoom-label">{{ zoomPercent }}%</span>
          <Tooltip title="放大">
            <Button size="small" @click="zoomIn">+</Button>
          </Tooltip>
          <Tooltip title="重置缩放并居中">
            <Button size="small" @click="fitCanvas">适应画布</Button>
          </Tooltip>
          <span class="wf-toolbar-divider"></span>
          <span class="wf-stat-pill">
            {{ graphStats.nodeCount }} 节点 · {{ graphStats.edgeCount }} 连线
          </span>
          <Button size="small" danger ghost @click="clearCanvas">清空</Button>
          <Button
            size="small"
            :disabled="!selectedNodeId"
            @click="removeSelectedNode"
          >
            删除选中节点
          </Button>
          <span class="wf-toolbar-divider"></span>
          <Tooltip :title="isFullscreen ? '退出全屏 (Esc)' : '全屏'">
            <Button
              type="text"
              size="small"
              class="wf-toolbar-fullscreen"
              :aria-label="isFullscreen ? '退出全屏' : '全屏'"
              @click="toggleStudioFullscreen"
            >
              <template #icon>
                <IconifyIcon
                  class="text-lg leading-none"
                  :icon="
                    isFullscreen ? 'mdi:fullscreen-exit' : 'mdi:fullscreen'
                  "
                />
              </template>
            </Button>
          </Tooltip>
        </Space>
      </div>

      <div class="wf-main">
        <!-- 左侧节点库 -->
        <aside class="wf-palette">
          <div class="wf-palette-title">节点库</div>
          <div class="wf-palette-group">
            <div class="wf-palette-h">事件</div>
            <button
              type="button"
              class="wf-palette-item"
              @click="addNode('start')"
            >
              <span class="wf-palette-ico wf-ico-start"></span>
              <span class="wf-palette-text">
                <span class="wf-palette-name">开始</span>
                <span class="wf-palette-desc">流程起始节点</span>
              </span>
            </button>
            <button
              type="button"
              class="wf-palette-item"
              @click="addNode('end')"
            >
              <span class="wf-palette-ico wf-ico-end"></span>
              <span class="wf-palette-text">
                <span class="wf-palette-name">结束</span>
                <span class="wf-palette-desc">流程结束节点</span>
              </span>
            </button>
          </div>
          <div class="wf-palette-group">
            <div class="wf-palette-h">任务</div>
            <button
              type="button"
              class="wf-palette-item"
              @click="addNode('approve')"
            >
              <span class="wf-palette-ico wf-ico-task"></span>
              <span class="wf-palette-text">
                <span class="wf-palette-name">审批节点</span>
                <span class="wf-palette-desc">人工审批任务</span>
              </span>
            </button>
            <button
              type="button"
              class="wf-palette-item"
              @click="addNode('cc')"
            >
              <span class="wf-palette-ico wf-ico-cc"></span>
              <span class="wf-palette-text">
                <span class="wf-palette-name">抄送节点</span>
                <span class="wf-palette-desc">知会、不阻塞</span>
              </span>
            </button>
          </div>
          <div class="wf-palette-group">
            <div class="wf-palette-h">网关</div>
            <button
              type="button"
              class="wf-palette-item"
              @click="addNode('condition')"
            >
              <span class="wf-palette-ico wf-ico-gateway"></span>
              <span class="wf-palette-text">
                <span class="wf-palette-name">条件分支</span>
                <span class="wf-palette-desc">菱形判断 · 出口配连线规则</span>
              </span>
            </button>
          </div>
          <p class="wf-palette-hint">
            在画布上拖拽节点移动；滚轮缩放；点击锚点连线。双击「开始」或「审批」节点可打开详细设置。
          </p>
        </aside>

        <!-- 中间画布 -->
        <main class="wf-canvas-panel">
          <div ref="canvasRef" class="lf-canvas"></div>
        </main>

        <!-- 右侧属性 -->
        <aside class="wf-inspector">
          <div class="wf-inspector-head">
            <span class="wf-inspector-bar"></span>
            <span class="wf-inspector-title">属性配置</span>
          </div>
          <div class="wf-inspector-body">
            <Card size="small" class="wf-prop-card" title="节点属性">
              <template v-if="selectedNodeId">
                <div class="mb-2">
                  <Tag color="blue">节点 ID: {{ selectedNodeId }}</Tag>
                </div>
                <div class="flex flex-col gap-3">
                  <div>
                    <div class="mb-1 text-xs text-muted-foreground">
                      节点名称
                    </div>
                    <Input v-model:value="selectedNodeName" />
                  </div>
                  <div>
                    <div class="mb-1 text-xs text-muted-foreground">
                      节点业务类型
                    </div>
                    <Select
                      v-model:value="selectedNodeType"
                      :options="nodeTypeOptions"
                    />
                  </div>
                  <div>
                    <div class="mb-1 text-xs text-muted-foreground">
                      处理人（展示摘要）
                    </div>
                    <Input
                      v-model:value="selectedAssignee"
                      placeholder="写入任务上的可读说明"
                    />
                  </div>
                  <div>
                    <div class="mb-1 text-xs text-muted-foreground">
                      处理人解析（按顺序命中）
                    </div>
                    <p class="mb-2 text-xs text-muted-foreground">
                      自上而下依次尝试；如「部门主管」仅需选类型可不填值。运行时需引擎解析（当前任务仍写
                      assignee 摘要）。
                    </p>
                    <div
                      v-for="(row, idx) in assigneeStrategies"
                      :key="idx"
                      class="mb-2 flex flex-col gap-1 rounded border border-border p-2"
                    >
                      <div class="flex flex-wrap gap-1">
                        <Select
                          v-model:value="row.kind"
                          :options="assigneeStrategyKindOptions"
                          class="min-w-[140px]"
                          @change="() => onStrategyKindChange(row)"
                        />
                        <Button
                          size="small"
                          type="link"
                          danger
                          @click="removeAssigneeRow(idx)"
                        >
                          删除
                        </Button>
                      </div>
                      <div class="flex gap-2">
                        <Input
                          v-if="
                            row.kind === 'user' ||
                            row.kind === 'role' ||
                            row.kind === 'dept_manager'
                          "
                          :value="row.label || row.value || ''"
                          readonly
                          :placeholder="
                            row.kind === 'user'
                              ? '点击右侧选人（保存 EMP_ID，多人逗号分隔）'
                              : row.kind === 'role'
                                ? '点击右侧选角色（保存 role id，多个逗号分隔）'
                                : row.kind === 'dept_manager'
                                  ? '点击右侧选择部门范围（为空则表示发起人所在部门）'
                                  : '用户/角色/岗位 ID，多个逗号分隔；表单字段填字段名'
                          "
                        />
                        <Input
                          v-else
                          v-model:value="row.value"
                          placeholder="用户/角色/岗位 ID，多个逗号分隔；表单字段填字段名"
                        />
                        <Button
                          v-if="row.kind === 'user'"
                          @click="
                            openPersonPicker({ list: 'assignee', index: idx })
                          "
                        >
                          选人
                        </Button>
                        <Button
                          v-if="row.kind === 'role'"
                          @click="
                            openRolePicker({ list: 'assignee', index: idx })
                          "
                        >
                          选角色
                        </Button>
                        <Button
                          v-if="row.kind === 'dept_manager'"
                          @click="
                            openDeptManagerPicker({
                              list: 'assignee',
                              index: idx,
                            })
                          "
                        >
                          选部门主管
                        </Button>
                      </div>
                    </div>
                    <Button
                      block
                      size="small"
                      type="dashed"
                      @click="addAssigneeRow"
                    >
                      + 添加策略
                    </Button>
                  </div>
                  <div>
                    <div class="mb-1 text-xs text-muted-foreground">
                      节点行为（写入 behaviors + 扩展字段）
                    </div>
                    <Space direction="vertical">
                      <Checkbox v-model:checked="behaviorCc">
                        抄送（通知，不阻塞）
                      </Checkbox>
                      <Checkbox v-model:checked="behaviorCountersign">
                        会签（多实例聚合，策略见下）
                      </Checkbox>
                      <Checkbox v-model:checked="behaviorSign">需签名</Checkbox>
                    </Space>
                  </div>
                  <div v-if="behaviorCc">
                    <div class="mb-1 text-xs text-muted-foreground">
                      抄送对象解析（ccStrategies，顺序命中）
                    </div>
                    <div
                      v-for="(row, idx) in ccStrategies"
                      :key="`cc-${idx}`"
                      class="mb-2 flex flex-col gap-1 rounded border border-border p-2"
                    >
                      <div class="flex flex-wrap gap-1">
                        <Select
                          v-model:value="row.kind"
                          :options="assigneeStrategyKindOptions"
                          class="min-w-[140px]"
                          @change="() => onStrategyKindChange(row)"
                        />
                        <Button
                          size="small"
                          type="link"
                          danger
                          @click="removeCcRow(idx)"
                        >
                          删除
                        </Button>
                      </div>
                      <div class="flex gap-2">
                        <Input
                          v-if="
                            row.kind === 'user' ||
                            row.kind === 'role' ||
                            row.kind === 'dept_manager'
                          "
                          :value="row.label || row.value || ''"
                          readonly
                          :placeholder="
                            row.kind === 'user'
                              ? '点击右侧选人（保存 EMP_ID，多人逗号分隔）'
                              : row.kind === 'role'
                                ? '点击右侧选角色（保存 role id，多个逗号分隔）'
                                : row.kind === 'dept_manager'
                                  ? '点击右侧选择部门范围（为空则表示发起人所在部门）'
                                  : '抄送目标：用户/角色/岗位等'
                          "
                        />
                        <Input
                          v-else
                          v-model:value="row.value"
                          placeholder="抄送目标：用户/角色/岗位等"
                        />
                        <Button
                          v-if="row.kind === 'user'"
                          @click="openPersonPicker({ list: 'cc', index: idx })"
                        >
                          选人
                        </Button>
                        <Button
                          v-if="row.kind === 'role'"
                          @click="openRolePicker({ list: 'cc', index: idx })"
                        >
                          选角色
                        </Button>
                        <Button
                          v-if="row.kind === 'dept_manager'"
                          @click="
                            openDeptManagerPicker({ list: 'cc', index: idx })
                          "
                        >
                          选部门主管
                        </Button>
                      </div>
                    </div>
                    <Button block size="small" type="dashed" @click="addCcRow">
                      + 抄送策略
                    </Button>
                  </div>
                  <div v-if="behaviorCountersign">
                    <div class="mb-1 text-xs text-muted-foreground">
                      会签策略（countersignPolicy）
                    </div>
                    <Select
                      v-model:value="countersignMode"
                      :options="countersignModeOptions"
                      class="mb-2 w-full"
                    />
                    <div v-if="countersignMode === 'percent'">
                      <div class="mb-1 text-xs text-muted-foreground">
                        通过比例 %
                      </div>
                      <InputNumber
                        v-model:value="countersignPercent"
                        :min="1"
                        :max="100"
                        class="w-full"
                      />
                    </div>
                  </div>
                  <div v-if="behaviorSign">
                    <div class="mb-1 text-xs text-muted-foreground">
                      签名类型（signPolicy.kind）
                    </div>
                    <Select
                      v-model:value="signKind"
                      :options="signKindOptions"
                      class="w-full"
                    />
                  </div>
                  <div>
                    <div class="mb-1 text-xs text-muted-foreground">说明</div>
                    <Input v-model:value="selectedDesc" />
                  </div>
                  <Button type="primary" @click="applyNodeProperty">
                    应用到节点
                  </Button>
                </div>
              </template>
              <div v-else class="text-sm text-muted-foreground">
                请先在画布中点击节点
              </div>
            </Card>

            <Card size="small" title="连线出口（A→B）">
              <template v-if="selectedEdgeId">
                <div class="mb-2">
                  <Tag color="orange">连线 ID: {{ selectedEdgeId }}</Tag>
                </div>
                <div class="mb-3">
                  <div class="mb-1 text-xs text-muted-foreground">
                    匹配优先级（数字越小越先尝试）
                  </div>
                  <InputNumber
                    v-model:value="selectedEdgePriority"
                    :min="0"
                    :max="999"
                    class="w-full"
                  />
                </div>
                <div class="mb-2 text-xs font-medium text-foreground">
                  结构化出口（ruleGroups）
                </div>
                <p class="mb-2 text-xs text-muted-foreground">
                  多个<strong>条件组</strong>之间为
                  <strong>OR</strong>；组内多条为
                  <strong>AND</strong>。保存时写入
                  <code class="rounded bg-muted px-1">
                    properties.ruleGroups
                  </code>
                  ；仅一组时同步
                  <code class="rounded bg-muted px-1">properties.rules</code>
                  便于旧引擎。发起人字段依赖
                  <code class="rounded bg-muted px-1">$initiator</code>（见
                  wfMeta.initiatorSource）。
                </p>
                <div
                  v-for="(grp, gi) in edgeGroups"
                  :key="`g-${gi}`"
                  class="mb-3 rounded border border-dashed border-primary/40 p-2"
                >
                  <div class="mb-2 flex items-center justify-between">
                    <span class="text-xs font-medium">
                      条件组 {{ gi + 1 }}（组内 AND）
                    </span>
                    <Button
                      v-if="edgeGroups.length > 1"
                      size="small"
                      type="link"
                      danger
                      @click="removeEdgeGroup(gi)"
                    >
                      删除本组
                    </Button>
                  </div>
                  <div
                    v-for="(row, ri) in grp.rules"
                    :key="`r-${gi}-${ri}`"
                    class="mb-2 flex flex-col gap-1 rounded border border-border p-2"
                  >
                    <div class="flex flex-wrap gap-1">
                      <Select
                        v-model:value="row.scope"
                        :options="conditionScopeOptions"
                        class="min-w-[120px]"
                      />
                      <Select
                        v-model:value="row.op"
                        :options="conditionOpOptions"
                        class="min-w-[100px]"
                      />
                      <Button
                        size="small"
                        type="link"
                        danger
                        @click="removeEdgeRuleRow(gi, ri)"
                      >
                        删除
                      </Button>
                    </div>
                    <Input
                      v-model:value="row.key"
                      placeholder="form: amount；initiator: departmentId"
                    />
                    <Input
                      v-model:value="row.value"
                      placeholder="标量或 JSON 数组"
                    />
                  </div>
                  <Button
                    block
                    size="small"
                    type="dashed"
                    @click="addEdgeRuleRow(gi)"
                  >
                    + 本组添加条件
                  </Button>
                </div>
                <Button
                  block
                  class="mb-3"
                  size="small"
                  type="dashed"
                  @click="addEdgeGroup"
                >
                  + 添加条件组（OR）
                </Button>
                <div class="mb-1 text-xs text-muted-foreground">
                  兼容：单行表达式（无结构化规则时）
                </div>
                <Input
                  v-model:value="selectedEdgeCondition"
                  placeholder="示例: amount >= 1000"
                />
                <p class="mt-2 text-xs text-muted-foreground">
                  无 ruleGroups/rules 时由引擎解析本表达式。
                </p>
                <Button class="mt-2" type="primary" @click="applyEdgeCondition">
                  应用到连线
                </Button>
              </template>
              <div v-else class="text-sm text-muted-foreground">
                请先在画布中点击一条连线
              </div>
            </Card>
          </div>
        </aside>
      </div>

      <Collapse :bordered="false" class="wf-json-collapse">
        <Collapse.Panel
          key="json"
          header="布局 JSON（导入 / 导出 / localStorage）"
        >
          <div class="mb-2 text-xs text-muted-foreground">
            存储键：{{ storageKey }}
          </div>
          <Input.TextArea
            v-model:value="jsonText"
            :rows="10"
            placeholder="导出后可复制；也可粘贴后导入"
          />
          <div class="mt-3 flex flex-wrap gap-2">
            <Button @click="exportCurrentJson">导出 JSON</Button>
            <Button type="primary" @click="importJsonLayout">导入 JSON</Button>
            <Button @click="saveLayout">保存到 localStorage</Button>
            <Button @click="loadSavedLayout">从 localStorage 加载</Button>
          </div>
        </Collapse.Panel>
      </Collapse>
    </div>
    <SelectPersonnelModal
      v-model:open="personPickerOpen"
      title="选择人员"
      :default-selected="personPickerDefaults"
      @confirm="applyPickedPeople"
    />
    <SelectRoleModal
      v-model:open="rolePickerOpen"
      title="选择角色"
      @confirm="applyPickedRoles"
    />
    <SelectDeptManagerModal
      v-model:open="deptManagerPickerOpen"
      title="选择部门主管范围"
      @confirm="applyPickedDeptManagers"
    />
    <WorkflowNodeSettingsModal
      v-model:open="nodeSettingsOpen"
      :biz-type="nodeSettingsBizType"
      :node-id="nodeSettingsNodeId"
      :initial-properties="nodeSettingsInitialProps"
      :initial-node-name="nodeSettingsInitialName"
      :all-nodes="nodeSettingsAllNodes"
      @save="onNodeSettingsSave"
    />
  </div>
</template>

<style scoped>
.wf-designer-root {
  height: 100%;
  min-height: 0;
}

.wf-studio {
  display: flex;
  flex-direction: column;
  min-height: calc(100vh - 120px);
  background: #eef2f7;
}

.wf-studio:fullscreen,
.wf-studio:-webkit-full-screen {
  min-height: 100%;
  box-sizing: border-box;
  overflow: auto;
}

.wf-toolbar-fullscreen {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 32px;
  color: #475569;
}

.wf-toolbar-fullscreen:hover {
  color: #2563eb;
}

.wf-topbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 16px;
  background: #fff;
  border-bottom: 1px solid #d8e0ea;
  box-shadow: 0 1px 0 rgb(255 255 255 / 80%) inset;
}

.wf-topbar-left {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px 20px;
}

.wf-pipe {
  width: 4px;
  height: 20px;
  border-radius: 2px;
  background: linear-gradient(180deg, #2563eb, #1d4ed8);
}

.wf-title-block {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.wf-title-label {
  font-size: 11px;
  color: #64748b;
}

.wf-title-input {
  width: min(320px, 42vw);
  font-weight: 600;
  font-size: 15px;
}

.wf-meta-block {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

.wf-meta-label {
  font-size: 12px;
  color: #64748b;
}

.wf-meta-input {
  width: 180px;
}

.wf-ver-input {
  width: 88px !important;
}

.wf-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  padding: 8px 16px;
  background: #f8fafc;
  border-bottom: 1px solid #e2e8f0;
}

.wf-toolbar-divider {
  width: 1px;
  height: 18px;
  margin: 0 6px;
  background: #cbd5e1;
}

.wf-zoom-label {
  min-width: 44px;
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  color: #475569;
  text-align: center;
}

.wf-stat-pill {
  padding: 2px 10px;
  font-size: 12px;
  color: #334155;
  background: #fff;
  border: 1px solid #e2e8f0;
  border-radius: 999px;
}

.wf-main {
  display: grid;
  flex: 1;
  grid-template-columns: 220px 1fr min(380px, 34vw);
  gap: 0;
  min-height: 0;
}

.wf-palette {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 12px;
  overflow: auto;
  background: #fff;
  border-right: 1px solid #e2e8f0;
}

.wf-palette-title {
  font-size: 13px;
  font-weight: 700;
  color: #1e3a5f;
}

.wf-palette-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.wf-palette-h {
  margin-top: 4px;
  font-size: 11px;
  font-weight: 600;
  color: #94a3b8;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.wf-palette-item {
  display: flex;
  gap: 10px;
  align-items: flex-start;
  width: 100%;
  padding: 8px 10px;
  text-align: left;
  cursor: pointer;
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
  transition:
    border-color 0.15s,
    box-shadow 0.15s;
}

.wf-palette-item:hover {
  background: #eff6ff;
  border-color: #93c5fd;
  box-shadow: 0 1px 2px rgb(37 99 235 / 12%);
}

.wf-palette-ico {
  flex-shrink: 0;
  width: 28px;
  height: 28px;
  border-radius: 4px;
}

.wf-ico-start {
  background: #ecfdf5;
  border: 2px solid #22c55e;
  border-radius: 50%;
  box-sizing: border-box;
}

.wf-ico-end {
  background: #fff1f2;
  border: 2px solid #f43f5e;
  border-radius: 50%;
  box-sizing: border-box;
}

/* 与画布节点 nodeStyleFor 一致：浅底 + 描边（空心感） */
.wf-ico-task {
  background: #eff6ff;
  border: 1.5px solid #3b82f6;
  border-radius: 10px;
  box-sizing: border-box;
}

.wf-ico-cc {
  background: #f5f3ff;
  border: 1.5px solid #8b5cf6;
  border-radius: 10px;
  box-sizing: border-box;
}

.wf-ico-gateway {
  background: #fff7ed;
  border: 2px solid #f97316;
  transform: rotate(45deg);
  border-radius: 2px;
  box-sizing: border-box;
}

.wf-palette-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.wf-palette-name {
  font-size: 13px;
  font-weight: 600;
  color: #0f172a;
}

.wf-palette-desc {
  font-size: 11px;
  line-height: 1.3;
  color: #64748b;
}

.wf-palette-hint {
  margin-top: auto;
  padding: 8px;
  font-size: 11px;
  line-height: 1.4;
  color: #94a3b8;
  background: #f1f5f9;
  border-radius: 4px;
}

.wf-canvas-panel {
  display: flex;
  min-width: 0;
  min-height: 0;
  padding: 8px;
  background: #e8edf4;
}

.lf-canvas {
  flex: 1;
  width: 100%;
  min-height: 520px;
  border: 1px solid #cbd5e1;
  border-radius: 4px;
  /* 与点阵网格搭配，接近 BPMN 白底画布 */
  background: #ffffff;
}

.wf-inspector {
  display: flex;
  flex-direction: column;
  min-width: 0;
  min-height: 0;
  background: #fff;
  border-left: 1px solid #e2e8f0;
}

.wf-inspector-head {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  border-bottom: 1px solid #e2e8f0;
  background: linear-gradient(180deg, #fff 0%, #f8fafc 100%);
}

.wf-inspector-bar {
  width: 3px;
  height: 14px;
  background: #2563eb;
  border-radius: 1px;
}

.wf-inspector-title {
  font-size: 13px;
  font-weight: 700;
  color: #1e3a5f;
}

.wf-inspector-body {
  flex: 1;
  min-height: 0;
  padding: 10px;
  overflow: auto;
}

.wf-prop-card {
  margin-bottom: 12px;
}

.wf-json-collapse {
  margin: 0 12px 12px;
  overflow: hidden;
  background: #fff;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
}

@media (max-width: 1280px) {
  .wf-main {
    grid-template-columns: 200px 1fr min(340px, 38vw);
  }
}

@media (max-width: 1024px) {
  .wf-main {
    grid-template-columns: 1fr;
  }

  .wf-palette {
    flex-direction: row;
    flex-wrap: wrap;
    border-right: none;
    border-bottom: 1px solid #e2e8f0;
  }

  .wf-inspector {
    border-left: none;
  }
}
</style>
