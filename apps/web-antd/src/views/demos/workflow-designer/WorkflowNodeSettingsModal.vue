<script setup lang="ts">
import type {
  WfApprovalHeaderConditionFieldType,
  WfApprovalHeaderConditionRule,
  WfApprovalOperatorRow,
  WfApprovalRoutingMode,
  WfApprovalWeaverUiState,
  WfApproverResolveMode,
  WfAssigneeStrategy,
  WfInitiatorGrant,
  WfInitiatorPermission,
  WfNodeProperties,
  WfRejectPolicy,
  WfSequentialApprover,
  WfTimeoutPolicy,
  WfWeaverObjectTypeCategory,
} from './workflow-definition.schema';

/**
 * 双击节点：开始节点（发起人权限）/ 审批节点（审批人、策略、抄送、驳回、超时）
 */
import type {
  OrgDeptItem,
  OrgPersonnelItem,
  OrgRoleItem,
} from '#/components/org-picker/types';

import { computed, reactive, ref, watch } from 'vue';

import { IconifyIcon } from '@vben/icons';

import {
  Button,
  Divider,
  Input,
  InputNumber,
  message,
  Modal,
  Radio,
  RadioGroup,
  Select,
  Space,
  Table,
  Tag,
  Tooltip,
} from 'ant-design-vue';

import SelectDepartmentModal from '#/components/org-picker/SelectDepartmentModal.vue';
import SelectPersonnelModal from '#/components/org-picker/SelectPersonnelModal.vue';
import SelectRoleModal from '#/components/org-picker/SelectRoleModal.vue';

import { WF_SCHEMA_VERSION } from './workflow-definition.schema';

const props = defineProps<{
  /** 画布节点列表（可带 isPrior 供「节点操作者」限定前序节点） */
  allNodes?: { id: string; isPrior?: boolean; label: string }[];
  bizType: 'approve' | 'start';
  /** 节点显示名称（与 text） */
  initialNodeName: string;
  /** 从 LogicFlow nodeModel.properties 读入 */
  initialProperties: Record<string, unknown>;
  nodeId: string;
  open: boolean;
}>();

const emit = defineEmits<{
  save: [
    payload: {
      nodeId: string;
      nodeName: string;
      properties: Record<string, unknown> & WfNodeProperties;
    },
  ];
  'update:open': [boolean];
}>();

const modalTitle = computed(() =>
  props.bizType === 'start' ? '发起人设置' : '审批节点设置',
);

// —— 通用 ——
const localName = ref('');

// —— 审批节点 ——
const approverMode = ref<WfApproverResolveMode>('direct_leader');
const formFieldKey = ref('');
const specifiedUsers = ref<OrgPersonnelItem[]>([]);

const routingMode = ref<WfApprovalRoutingMode>('all');

/** 表头：条件 / 批次（与旧系统「批次/条件」区对应） */
const headerCondition = ref('');
const headerBatchNote = ref('');
const conditionOpen = ref(false);
const conditionRules = ref<WfApprovalHeaderConditionRule[]>([]);
const conditionPickRuleId = ref('');

const conditionJoinOptions = [
  { label: '且 (AND)', value: 'and' },
  { label: '或 (OR)', value: 'or' },
] as const;
const conditionOpOptions = [
  { label: '==', value: '==' },
  { label: '!=', value: '!=' },
  { label: '>', value: '>' },
  { label: '>=', value: '>=' },
  { label: '<', value: '<' },
  { label: '<=', value: '<=' },
] as const;
const conditionBetweenOpOptions = [
  { label: '区间 (between)', value: 'between' },
  { label: '不在区间 (not_between)', value: 'not_between' },
] as const;
const conditionTypeOptions = [
  { label: '表单字段比较', value: 'form_compare' },
  { label: '人员安全级别', value: 'actor_security' },
  { label: '审批人等于某人', value: 'actor_user' },
] as const;
const conditionFieldTypeOptions: Array<{
  label: string;
  value: WfApprovalHeaderConditionFieldType;
}> = [
  { label: '文本', value: 'string' },
  { label: '数字', value: 'number' },
  { label: '日期', value: 'date' },
  { label: '布尔', value: 'boolean' },
];
const conditionBooleanValueOptions = [
  { label: '是 (true)', value: 'true' },
  { label: '否 (false)', value: 'false' },
];
const conditionActorSourceOptions = [
  { label: '创建人', value: 'initiator' },
  { label: '前序节点操作者', value: 'node' },
] as const;

/** 审批节点：上方表头折叠面板默认展开 */
function defaultWeaverUi(): WfApprovalWeaverUiState {
  return {
    objectTypeCategory: 'general',
    objectSource: 'hr',
    deptKeyword: '',
    deptSecMin: 0,
    deptSecMax: 100,
    weaverDeptPicks: [],
    roleKeyword: '',
    roleLevel: '部门',
    weaverRolePicks: [],
    hrKeyword: '',
    everyoneSecMin: 0,
    everyoneSecMax: 100,
    nodeOperatorNodeId: '',
    nodeOperatorNodeLabel: '',
    nodeOperatorPickMode: 'self',
    autoSkipWhenSameActor: true,
  };
}

const weaverUi = reactive<WfApprovalWeaverUiState>(defaultWeaverUi());

const weaverObjectTypeOptions: {
  label: string;
  value: WfWeaverObjectTypeCategory;
}[] = [
  { label: '一般', value: 'general' },
  { label: '表单 人力资源字段', value: 'hr_field' },
  { label: '创建人', value: 'creator' },
  { label: '节点操作者', value: 'node_operator' },
];

const weaverRoleLevelOptions = [{ label: '部门', value: '部门' }];
const creatorApproverModeOptions: Array<{
  label: string;
  value: Extract<
    WfApproverResolveMode,
    'dept_head' | 'direct_leader' | 'indirect_leader' | 'initiator_self'
  >;
}> = [
  { label: '本人', value: 'initiator_self' },
  { label: '直接上级', value: 'direct_leader' },
  { label: '间接上级', value: 'indirect_leader' },
  { label: '部门主管', value: 'dept_head' },
];

type OperatorTableRow = WfApprovalOperatorRow & { id: string };

const operatorRows = ref<OperatorTableRow[]>([]);
const selectedOperatorKeys = ref<string[]>([]);

/** 明细表「类型」列：与表头「对象类型」同一套选项 */
const operatorKindOptions = weaverObjectTypeOptions.map((o) => ({
  label: o.label,
  value: o.label,
}));

/** 明细表「会签属性」列下拉（与泛微一致） */
const operatorCountersignAttrOptions = [
  { label: '会签', value: '会签' },
  { label: '或签', value: '或签' },
  { label: '依次', value: '依次' },
  { label: '抄送', value: '抄送' },
];

function normalizeCountersignCell(
  v: unknown,
  fallback: string,
): '会签' | '依次' | '或签' | '抄送' {
  const s = String(v || '').trim();
  if (s === '会签' || s === '或签' || s === '依次' || s === '抄送') return s;
  const f = String(fallback || '').trim();
  if (f === '会签' || f === '或签' || f === '依次' || f === '抄送') return f;
  return '会签';
}

/** 当前表头「对象类型」→ 写入明细「类型」列的文案 */
function objectTypeKindLabel(): string {
  const hit = weaverObjectTypeOptions.find(
    (o) => o.value === weaverUi.objectTypeCategory,
  );
  return hit?.label ?? '一般';
}

/** 当前表头「对象」区 → 写入明细「名称」列的摘要（与泛微表头/明细对应关系一致） */
function objectSourceDisplayName(): string {
  if (weaverUi.objectTypeCategory === 'hr_field') {
    const k = formFieldKey.value.trim();
    return k || '表单字段（未填）';
  }
  if (weaverUi.objectTypeCategory === 'creator') {
    if (approverMode.value === 'initiator_self') return '本人';
    if (approverMode.value === 'indirect_leader') return '间接上级';
    if (approverMode.value === 'dept_head') return '部门主管';
    return '直接上级';
  }
  if (weaverUi.objectTypeCategory === 'node_operator') {
    const base = weaverUi.nodeOperatorNodeLabel?.trim() || '前序节点（未选）';
    const pick = weaverUi.nodeOperatorPickMode === 'manager' ? '经理' : '本人';
    return `${base}-${pick}`;
  }
  let core = '';
  switch (weaverUi.objectSource) {
    case 'dept': {
      const kw = weaverUi.deptKeyword.trim();
      core = `部门${kw ? `：${kw}` : '（未指定）'} 安全级别 ${weaverUi.deptSecMin}-${weaverUi.deptSecMax}`;
      break;
    }
    case 'everyone': {
      core = `所有人 安全级别 ${weaverUi.everyoneSecMin}-${weaverUi.everyoneSecMax}`;
      break;
    }
    case 'hr': {
      const kw = weaverUi.hrKeyword.trim();
      if (kw) {
        core = `人力资源：${kw}`;
      } else if (specifiedUsers.value.length > 0) {
        core = `人力资源：${specifiedUsers.value
          .map((u) => String(u.name || u.empId).trim())
          .filter(Boolean)
          .join('、')}`;
      } else {
        core = '人力资源（未指定）';
      }
      break;
    }
    case 'role': {
      const kw = weaverUi.roleKeyword.trim();
      core = `角色${kw ? `：${kw}` : '（未指定）'} 级别：${weaverUi.roleLevel || '部门'}`;
      break;
    }
    // No default
  }
  return core.trim();
}

/** 历史明细里「类型」曾用 人力资源/动态 等，读入时映射到当前「对象类型」四选一 */
function normalizeSavedOperatorKind(kind: unknown): string {
  const s = String(kind || '').trim();
  const allowed = new Set(weaverObjectTypeOptions.map((o) => o.label));
  if (allowed.has(s)) return s;
  if (s === '人力资源' || s === '人力资源字段') return '表单 人力资源字段';
  if (s === '动态' || s === '角色' || s === '部门') return '一般';
  return '一般';
}

function newOperatorId(): string {
  return `op_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
}

function newConditionRule(
  partial?: Partial<WfApprovalHeaderConditionRule>,
): WfApprovalHeaderConditionRule {
  return {
    id: `cond_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    joinWithPrev: 'and',
    type: 'form_compare',
    formFieldType: 'string',
    actorSource: 'initiator',
    op: '==',
    ...partial,
  };
}

function conditionRuleSummary(r: WfApprovalHeaderConditionRule): string {
  if (r.type === 'form_compare') {
    const k = String(r.formFieldKey || '').trim() || '表单字段';
    const t = r.formFieldType || 'string';
    if (r.op === 'between' || r.op === 'not_between') {
      return `${k}[${t}] ${r.op} ${String(r.value ?? '')} ~ ${String(r.valueTo ?? '')}`;
    }
    return `${k}[${t}] ${r.op || '=='} ${String(r.value ?? '')}`;
  }
  const actor =
    r.actorSource === 'node'
      ? `${r.actorNodeLabel || '前序节点'}操作者`
      : '创建人';
  if (r.type === 'actor_security') {
    return `${actor}.安全级别 ${r.op || '>='} ${String(r.value ?? '')}`;
  }
  const user = String(r.userName || r.userId || '').trim() || '（未选人员）';
  return `${actor} == ${user}`;
}

function summarizeConditionRules(
  rules: WfApprovalHeaderConditionRule[],
): string {
  if (rules.length === 0) return '';
  return rules
    .map((r, i) =>
      i === 0
        ? conditionRuleSummary(r)
        : `${r.joinWithPrev === 'or' ? 'OR' : 'AND'} ${conditionRuleSummary(r)}`,
    )
    .join(' ');
}

function addConditionRule() {
  conditionRules.value.push(newConditionRule());
}

function removeConditionRule(ruleId: string) {
  conditionRules.value = conditionRules.value.filter((r) => r.id !== ruleId);
}

function openConditionBuilder() {
  if (conditionRules.value.length === 0) addConditionRule();
  conditionOpen.value = true;
}

function clearConditionRules() {
  conditionRules.value = [];
  headerCondition.value = '';
}

function onConditionTypeChange(rule: WfApprovalHeaderConditionRule) {
  if (rule.type === 'form_compare') {
    rule.formFieldType = rule.formFieldType || 'string';
    rule.actorSource = 'initiator';
    rule.actorNodeId = undefined;
    rule.actorNodeLabel = undefined;
    rule.userId = undefined;
    rule.userName = undefined;
    onConditionFieldTypeChange(rule);
    return;
  }
  if (rule.type === 'actor_security') {
    rule.op = '>=';
    rule.userId = undefined;
    rule.userName = undefined;
    return;
  }
  rule.op = '==';
}

function getConditionOpOptions(rule: WfApprovalHeaderConditionRule) {
  if (rule.type !== 'form_compare') return conditionOpOptions;
  const t = rule.formFieldType || 'string';
  if (t === 'boolean') {
    return conditionOpOptions.filter((o) => o.value === '==' || o.value === '!=');
  }
  if (t === 'string') {
    return conditionOpOptions.filter((o) => o.value === '==' || o.value === '!=');
  }
  return [...conditionOpOptions, ...conditionBetweenOpOptions];
}

function onConditionFieldTypeChange(rule: WfApprovalHeaderConditionRule) {
  const t = rule.formFieldType || 'string';
  const options = getConditionOpOptions(rule);
  if (!options.some((o) => o.value === rule.op)) {
    rule.op = options[0]?.value || '==';
  }
  if (rule.op !== 'between' && rule.op !== 'not_between') {
    rule.valueTo = undefined;
  }
  if (t === 'boolean') {
    if (rule.value !== 'true' && rule.value !== 'false') {
      rule.value = 'true';
    }
    return;
  }
  if (t === 'number') {
    if (rule.value === '' || rule.value === undefined || rule.value === null) return;
    const n = Number(rule.value);
    if (Number.isFinite(n)) rule.value = n;
    return;
  }
  if (typeof rule.value === 'boolean') {
    rule.value = rule.value ? 'true' : 'false';
  }
}

function normalizeConditionRuleValue(rule: WfApprovalHeaderConditionRule): boolean {
  if (rule.type === 'form_compare') {
    const t = rule.formFieldType || 'string';
    const isRangeOp = rule.op === 'between' || rule.op === 'not_between';
    if (t === 'number') {
      const n = Number(rule.value);
      if (!Number.isFinite(n)) {
        message.warning(`字段「${rule.formFieldKey || '未命名'}」请输入有效数字`);
        return false;
      }
      rule.value = n;
      if (isRangeOp) {
        const m = Number(rule.valueTo);
        if (!Number.isFinite(m)) {
          message.warning(`字段「${rule.formFieldKey || '未命名'}」请输入有效区间上限`);
          return false;
        }
        rule.valueTo = m;
      } else {
        rule.valueTo = undefined;
      }
      return true;
    }
    if (t === 'boolean') {
      rule.valueTo = undefined;
      if (rule.value === true || rule.value === false) return true;
      if (rule.value === 'true' || rule.value === 'false') {
        rule.value = rule.value === 'true';
        return true;
      }
      message.warning(`字段「${rule.formFieldKey || '未命名'}」布尔值只能是 true/false`);
      return false;
    }
    if (t === 'date') {
      const from = String(rule.value ?? '').trim();
      if (!from) {
        message.warning(`字段「${rule.formFieldKey || '未命名'}」请输入日期值`);
        return false;
      }
      rule.value = from;
      if (isRangeOp) {
        const to = String(rule.valueTo ?? '').trim();
        if (!to) {
          message.warning(`字段「${rule.formFieldKey || '未命名'}」请输入区间结束日期`);
          return false;
        }
        rule.valueTo = to;
      } else {
        rule.valueTo = undefined;
      }
      return true;
    }
    rule.value = String(rule.value ?? '').trim();
    rule.valueTo = undefined;
    return true;
  }
  if (rule.type === 'actor_security') {
    const n = Number(rule.value);
    if (!Number.isFinite(n)) {
      message.warning('人员安全级别请输入有效数字');
      return false;
    }
    rule.value = n;
    return true;
  }
  return true;
}

function onConditionActorSourceChange(rule: WfApprovalHeaderConditionRule) {
  if (rule.actorSource !== 'node') {
    rule.actorNodeId = undefined;
    rule.actorNodeLabel = undefined;
  }
}

function onConditionOk() {
  for (const r of conditionRules.value) {
    if (!normalizeConditionRuleValue(r)) return;
    if (r.actorSource === 'node') {
      const hit = priorNodeOptions.value.find((o) => o.value === r.actorNodeId);
      r.actorNodeLabel = hit ? String(hit.label) : '';
    } else {
      r.actorNodeId = undefined;
      r.actorNodeLabel = undefined;
    }
  }
  headerCondition.value = summarizeConditionRules(conditionRules.value);
  conditionOpen.value = false;
}

function countersignAttrFromRouting(): string {
  if (routingMode.value === 'all') return '会签';
  if (routingMode.value === 'any') return '或签';
  if (routingMode.value === 'cc') return '抄送';
  return '依次';
}

function syncDetailFromHeader() {
  const mode = approverMode.value;
  const cond = headerCondition.value.trim();
  const typeCol = objectTypeKindLabel();
  const routingLabel = countersignAttrFromRouting();
  if (mode === 'specified_users') {
    operatorRows.value = specifiedUsers.value.map((u, i) => ({
      id: newOperatorId(),
      kind: typeCol,
      name: String(u.name || u.empId || '').trim() || String(u.empId),
      refValue: String(u.empId || '').trim(),
      level: '',
      countersignAttr: routingLabel,
      batchCondition: cond,
      batch: i,
    }));
    return;
  }
  let dynName = `表单字段：${formFieldKey.value.trim() || '未填'}`;
  switch (mode) {
    case 'dept_head': {
      dynName = '部门主管（运行时解析）';

      break;
    }
    case 'direct_leader': {
      dynName = '直接领导（运行时解析）';

      break;
    }
    case 'indirect_leader': {
      dynName = '间接领导（运行时解析）';

      break;
    }
    // No default
  }
  const fromObject = objectSourceDisplayName().trim();
  const nameCol = fromObject || dynName;
  operatorRows.value = [
    {
      id: newOperatorId(),
      kind: typeCol,
      name: nameCol,
      refValue: '',
      level: '',
      countersignAttr: routingLabel,
      batchCondition: cond,
      batch: 0,
    },
  ];
}

function loadOperatorRowsFromProps(
  p: Record<string, unknown> & WfNodeProperties,
) {
  headerCondition.value = String(p.approvalHeaderCondition || '');
  const cr = p.approvalHeaderConditionRules as
    | undefined
    | WfApprovalHeaderConditionRule[];
  conditionRules.value = Array.isArray(cr)
    ? cr.map((x) =>
        newConditionRule({ ...x, id: String(x.id || newConditionRule().id) }),
      )
    : [];
  headerBatchNote.value = String(p.approvalHeaderBatch || '');
  const saved = p.approvalOperatorRows as undefined | WfApprovalOperatorRow[];
  if (Array.isArray(saved) && saved.length > 0) {
    operatorRows.value = saved.map((r) => ({
      id: String(r.id || newOperatorId()),
      kind: normalizeSavedOperatorKind(r.kind),
      name: r.name || '',
      refValue: r.refValue,
      level: r.level || '',
      countersignAttr: normalizeCountersignCell(
        r.countersignAttr,
        countersignAttrFromRouting(),
      ),
      batchCondition: r.batchCondition || '',
      batch: Number(r.batch) || 0,
    }));
    if (approverMode.value === 'specified_users') {
      specifiedUsers.value = operatorRows.value
        .filter((row) => row.refValue?.trim())
        .map(
          (row) =>
            ({
              empId: row.refValue!.trim(),
              name: row.name || row.refValue,
            }) as OrgPersonnelItem,
        );
    }
    return;
  }
  const legacySeq = p.sequentialApprovers as undefined | WfSequentialApprover[];
  if (
    approverMode.value === 'specified_users' &&
    Array.isArray(legacySeq) &&
    legacySeq.length > 0
  ) {
    operatorRows.value = legacySeq.map((s, i) => ({
      id: newOperatorId(),
      kind: objectTypeKindLabel(),
      name: String(s.label || s.userId || '').trim() || String(s.userId),
      refValue: String(s.userId || '').trim(),
      level: '',
      countersignAttr: countersignAttrFromRouting(),
      batchCondition: headerCondition.value.trim(),
      batch: i,
    }));
    specifiedUsers.value = legacySeq.map(
      (s) =>
        ({
          empId: String(s.userId || '').trim(),
          name: String(s.label || s.userId || '').trim(),
        }) as OrgPersonnelItem,
    );
    return;
  }
  syncDetailFromHeader();
}

function onOperatorSelectionChange(keys: (number | string)[]) {
  selectedOperatorKeys.value = keys.map(String);
}

function nextOperatorBatchValue(): number {
  const headerBatchRaw = headerBatchNote.value.trim();
  if (headerBatchRaw !== '' && !Number.isNaN(Number(headerBatchRaw))) {
    return Number(headerBatchRaw);
  }
  if (operatorRows.value.length === 0) return 0;
  return Math.max(...operatorRows.value.map((r) => Number(r.batch) || 0)) + 1;
}

/** 绿色加号：按当前表头「对象类型 / 对象 / 批次·条件 / 审批策略」追加一行明细 */
function addOperatorRowFromHeader() {
  operatorRows.value.push({
    id: newOperatorId(),
    kind: objectTypeKindLabel(),
    name: objectSourceDisplayName(),
    refValue: '',
    level: '',
    countersignAttr: countersignAttrFromRouting(),
    batchCondition: headerCondition.value.trim(),
    batch: nextOperatorBatchValue(),
  });
}

function addBlankOperatorRow() {
  operatorRows.value.push({
    id: newOperatorId(),
    kind: objectTypeKindLabel(),
    name: '',
    refValue: '',
    level: '',
    countersignAttr: countersignAttrFromRouting(),
    batchCondition: headerCondition.value.trim(),
    batch: nextOperatorBatchValue(),
  });
}

function removeSelectedOperatorRows() {
  if (selectedOperatorKeys.value.length === 0) return;
  const drop = new Set(selectedOperatorKeys.value);
  operatorRows.value = operatorRows.value.filter((r) => !drop.has(r.id));
  selectedOperatorKeys.value = [];
}

const ccEnabled = ref(false);
const ccStrategies = ref<WfAssigneeStrategy[]>([]);

const rejectEnabled = ref(true);
const rejectTarget = ref<WfRejectPolicy['target']>('initiator');
const rejectSpecifiedNodeId = ref<string | undefined>();
const rejectResubmit = ref(true);

const timeoutEnabled = ref(false);
const timeoutHours = ref(48);
const timeoutAction = ref<'auto_pass' | 'transfer'>('auto_pass');
const timeoutTransferUserIds = ref('');
const timeoutTransferLabel = ref('');

// —— 开始节点 ——
const initiatorUsers = ref<OrgPersonnelItem[]>([]);
const initiatorDepts = ref<OrgDeptItem[]>([]);
const initiatorRoles = ref<OrgRoleItem[]>([]);
const initiatorPositionText = ref('');
const minSecurityLevel = ref<null | number>(null);

const personOpen = ref(false);
const personTarget = ref<'condition_user' | 'initiator' | 'specified'>(
  'specified',
);
const deptOpen = ref(false);
const roleOpen = ref(false);
/** 部门/角色弹窗：发起人节点 vs 审批「对象」区 */
const deptPickerTarget = ref<'initiator' | 'weaver'>('initiator');
const rolePickerTarget = ref<'initiator' | 'weaver'>('initiator');

function emptyGrants(): WfInitiatorGrant[] {
  return [];
}

function grantsToInitiatorPermission(): WfInitiatorPermission {
  const grants: WfInitiatorGrant[] = [...emptyGrants()];
  for (const p of initiatorUsers.value) {
    const id = String(p.empId || '').trim();
    if (!id) continue;
    grants.push({
      kind: 'user',
      value: id,
      label: String(p.name || '').trim() || id,
    });
  }
  for (const d of initiatorDepts.value) {
    grants.push({
      kind: 'dept',
      value: String(d.id || '').trim(),
      label: String(d.name || '').trim(),
    });
  }
  for (const r of initiatorRoles.value) {
    grants.push({
      kind: 'role',
      value: String(r.id || '').trim(),
      label: String(r.name || '').trim(),
    });
  }
  const pos = initiatorPositionText.value.trim();
  if (pos) {
    grants.push({ kind: 'position', value: pos, label: pos });
  }
  return {
    grants,
    minSecurityLevel:
      minSecurityLevel.value !== null && minSecurityLevel.value !== undefined
        ? Number(minSecurityLevel.value)
        : null,
  };
}

function readInitiatorFromProps(ip: undefined | WfInitiatorPermission) {
  initiatorUsers.value = [];
  initiatorDepts.value = [];
  initiatorRoles.value = [];
  initiatorPositionText.value = '';
  minSecurityLevel.value = null;
  if (!ip?.grants?.length) return;
  for (const g of ip.grants) {
    if (g.kind === 'user' && g.value) {
      initiatorUsers.value.push({
        empId: g.value,
        name: g.label || g.value,
      } as OrgPersonnelItem);
    }
    if (g.kind === 'dept' && g.value) {
      initiatorDepts.value.push({
        id: g.value,
        name: g.label || g.value,
      } as OrgDeptItem);
    }
    if (g.kind === 'role' && g.value) {
      initiatorRoles.value.push({
        id: g.value,
        name: g.label || g.value,
      } as OrgRoleItem);
    }
    if (g.kind === 'position' && g.value) {
      initiatorPositionText.value = g.value;
    }
  }
  if (ip.minSecurityLevel !== undefined && ip.minSecurityLevel !== null) {
    minSecurityLevel.value = Number(ip.minSecurityLevel);
  }
}

function syncWeaverFromApproverMode() {
  if (approverMode.value === 'form_field') {
    weaverUi.objectTypeCategory = 'hr_field';
    weaverUi.objectSource = 'hr';
    return;
  }
  if (approverMode.value === 'specified_users') {
    weaverUi.objectSource = 'hr';
  } else if (approverMode.value === 'dept_head') {
    weaverUi.objectSource = 'dept';
  } else {
    weaverUi.objectSource = 'everyone';
  }
}

function applyWeaverToApproverMode() {
  if (weaverUi.objectTypeCategory === 'hr_field') {
    approverMode.value = 'form_field';
    return;
  }
  if (weaverUi.objectTypeCategory === 'creator') {
    if (
      approverMode.value !== 'initiator_self' &&
      approverMode.value !== 'dept_head' &&
      approverMode.value !== 'direct_leader' &&
      approverMode.value !== 'indirect_leader'
    ) {
      approverMode.value = 'direct_leader';
    }
    return;
  }
  if (weaverUi.objectTypeCategory === 'node_operator') {
    // 先落到一个稳定模式，真实「节点操作者」语义由 approvalWeaverUi 持久化供后续引擎解析
    approverMode.value = 'direct_leader';
    return;
  }
  switch (weaverUi.objectSource) {
    case 'dept': {
      approverMode.value = 'dept_head';
      break;
    }
    case 'hr': {
      approverMode.value = 'specified_users';
      break;
    }
    default: {
      approverMode.value = 'direct_leader';
    }
  }
}

function readApproveFromProps(p: Record<string, unknown> & WfNodeProperties) {
  const ar = p.approverResolve as
    | undefined
    | { formFieldKey?: string; mode?: WfApproverResolveMode };
  const strategies = p.assigneeStrategies as undefined | WfAssigneeStrategy[];
  if (ar?.mode) {
    approverMode.value = ar.mode;
    formFieldKey.value = ar.formFieldKey || '';
  } else {
    const expr = strategies?.find((s) => s.kind === 'expression')?.value;
    switch (expr) {
      case '$resolve.deptHead': {
        approverMode.value = 'dept_head';
        break;
      }
      case '$resolve.directLeader': {
        approverMode.value = 'direct_leader';
        break;
      }
      case '$resolve.indirectLeader': {
        approverMode.value = 'indirect_leader';
        break;
      }
      case '$resolve.initiatorSelf': {
        approverMode.value = 'initiator_self';
        break;
      }
      default: {
        if (strategies?.some((s) => s.kind === 'form_field')) {
          approverMode.value = 'form_field';
          formFieldKey.value =
            strategies.find((s) => s.kind === 'form_field')?.value || '';
        } else if (strategies?.some((s) => s.kind === 'user' && s.value)) {
          approverMode.value = 'specified_users';
        } else {
          approverMode.value = 'direct_leader';
        }
      }
    }
    if (approverMode.value !== 'form_field') formFieldKey.value = '';
  }

  routingMode.value = (p.approvalRoutingMode as WfApprovalRoutingMode) || 'all';

  const cp = p.countersignPolicy;
  if (!p.approvalRoutingMode && cp?.mode === 'any') routingMode.value = 'any';
  if (!p.approvalRoutingMode && p.behaviors?.sequentialApproval)
    routingMode.value = 'sequential';
  if (
    !p.approvalRoutingMode &&
    p.behaviors?.cc &&
    !p.behaviors?.countersign &&
    !p.behaviors?.sequentialApproval
  ) {
    routingMode.value = 'cc';
  }

  const b = p.behaviors || {};
  ccEnabled.value = !!b.cc;
  ccStrategies.value = Array.isArray(p.ccStrategies)
    ? (p.ccStrategies as WfAssigneeStrategy[]).map((s) => ({ ...s }))
    : [];

  const rp = p.rejectPolicy as undefined | WfRejectPolicy;
  rejectEnabled.value = rp?.enabled !== false;
  rejectTarget.value = rp?.target || 'initiator';
  rejectSpecifiedNodeId.value = rp?.specifiedNodeId;
  rejectResubmit.value = rp?.allowResubmitAfterModify !== false;

  const tp = p.timeoutPolicy as undefined | WfTimeoutPolicy;
  timeoutEnabled.value = !!tp?.enabled;
  timeoutHours.value = tp?.hours === undefined ? 48 : Number(tp.hours);
  timeoutAction.value = tp?.action === 'transfer' ? 'transfer' : 'auto_pass';
  timeoutTransferUserIds.value = tp?.transferUserIds || '';
  timeoutTransferLabel.value = '';

  // 指定人员：从 assigneeStrategies 还原
  const str = p.assigneeStrategies as undefined | WfAssigneeStrategy[];
  specifiedUsers.value = [];
  if (approverMode.value === 'specified_users' && str?.length) {
    const row = str.find((s) => s.kind === 'user' && s.value);
    if (row?.value) {
      const ids = String(row.value)
        .split(',')
        .map((x) => x.trim())
        .filter(Boolean);
      const labels = String(row.label || '').split('、');
      specifiedUsers.value = ids.map((id, i) => ({
        empId: id,
        name: labels[i]?.split('/')?.[1] || labels[i] || id,
      })) as OrgPersonnelItem[];
    }
  }
  const wu = p.approvalWeaverUi as Partial<WfApprovalWeaverUiState> | undefined;
  Object.assign(weaverUi, defaultWeaverUi(), wu || {});
  const legacyRemovedCategories = new Set([
    'asset',
    'customer',
    'doc',
    'matrix',
    'project',
  ]);
  if (legacyRemovedCategories.has(String(weaverUi.objectTypeCategory))) {
    weaverUi.objectTypeCategory =
      approverMode.value === 'form_field' ? 'hr_field' : 'general';
  }
  if (String(weaverUi.objectSource) === 'branch') {
    weaverUi.objectSource = 'dept';
  }
  if (!wu?.objectSource) {
    syncWeaverFromApproverMode();
  }
  if (!Array.isArray(weaverUi.weaverDeptPicks)) weaverUi.weaverDeptPicks = [];
  if (!Array.isArray(weaverUi.weaverRolePicks)) weaverUi.weaverRolePicks = [];
  weaverUi.autoSkipWhenSameActor =
    typeof wu?.autoSkipWhenSameActor === 'boolean'
      ? wu.autoSkipWhenSameActor
      : typeof wu?.nodeOperatorAutoSkip === 'boolean'
        ? wu.nodeOperatorAutoSkip
        : true;
  loadOperatorRowsFromProps(p);
}

function syncOpen() {
  if (!props.open) return;
  localName.value = props.initialNodeName || '';
  const p = props.initialProperties as Record<string, unknown> &
    WfNodeProperties;
  if (props.bizType === 'start') {
    readInitiatorFromProps(
      p.initiatorPermission as undefined | WfInitiatorPermission,
    );
  } else {
    readApproveFromProps(p);
  }
}

watch(
  () => [props.open, props.nodeId, props.bizType] as const,
  () => syncOpen(),
  { immediate: true },
);

const priorNodeOptions = computed(() =>
  (props.allNodes || [])
    .filter((n) => n.isPrior)
    .map((n) => ({ label: n.label || n.id, value: n.id })),
);

watch(
  () => [weaverUi.objectTypeCategory, priorNodeOptions.value] as const,
  () => {
    if (weaverUi.objectTypeCategory !== 'node_operator') return;
    const options = priorNodeOptions.value;
    if (options.length === 0) {
      weaverUi.nodeOperatorNodeId = '';
      weaverUi.nodeOperatorNodeLabel = '';
      return;
    }
    if (
      !weaverUi.nodeOperatorNodeId ||
      !options.some((o) => o.value === weaverUi.nodeOperatorNodeId)
    ) {
      weaverUi.nodeOperatorNodeId = String(options[0].value);
      weaverUi.nodeOperatorNodeLabel = String(options[0].label);
    }
  },
  { immediate: true },
);

watch(
  () => weaverUi.nodeOperatorNodeId,
  (v) => {
    const hit = priorNodeOptions.value.find((o) => o.value === v);
    weaverUi.nodeOperatorNodeLabel = hit ? String(hit.label) : '';
  },
);

watch(
  () => weaverUi.objectTypeCategory,
  (v) => {
    if (v !== 'creator') return;
    if (
      approverMode.value !== 'initiator_self' &&
      approverMode.value !== 'dept_head' &&
      approverMode.value !== 'direct_leader' &&
      approverMode.value !== 'indirect_leader'
    ) {
      approverMode.value = 'direct_leader';
    }
  },
);

/** 「表单 人力资源字段」时，明细「名称」与对象区「表单字段」输入一致（如 aaa） */
watch(
  () => [formFieldKey.value, weaverUi.objectTypeCategory] as const,
  () => {
    if (weaverUi.objectTypeCategory !== 'hr_field') return;
    const kind = objectTypeKindLabel();
    const nm = formFieldKey.value.trim() || '表单字段（未填）';
    for (const r of operatorRows.value) {
      if (r.kind === kind) r.name = nm;
    }
  },
);

const operatorColumns = [
  { title: '类型', dataIndex: 'kind', width: 112, ellipsis: true },
  { title: '名称', dataIndex: 'name', width: 128, ellipsis: true },
  { title: '级别', dataIndex: 'level', width: 88 },
  { title: '会签属性', dataIndex: 'countersignAttr', width: 100 },
  { title: '批次/协办条件', dataIndex: 'batchCondition', width: 148 },
  { title: '批次', dataIndex: 'batch', width: 80 },
];

const operatorRowSelection = computed(() => ({
  selectedRowKeys: selectedOperatorKeys.value,
  onChange: (keys: (number | string)[]) => onOperatorSelectionChange(keys),
}));

const approverSummary = computed(() => {
  if (props.bizType !== 'approve') return '';
  switch (approverMode.value) {
    case 'dept_head': {
      return '部门主管';
    }
    case 'direct_leader': {
      return '直接领导';
    }
    case 'form_field': {
      return `表单字段：${formFieldKey.value.trim() || '（未填）'}`;
    }
    case 'indirect_leader': {
      return '间接领导';
    }
    case 'initiator_self': {
      return '本人';
    }
    case 'specified_users': {
      return (
        specifiedUsers.value
          .map((u) => String(u.name || u.empId).trim())
          .filter(Boolean)
          .join('、') || '（未选人员）'
      );
    }
    default: {
      return '';
    }
  }
});

function openSpecifiedPersonPicker() {
  personTarget.value = 'specified';
  personOpen.value = true;
}

function openInitiatorPersonPicker() {
  personTarget.value = 'initiator';
  personOpen.value = true;
}

function openDeptPicker() {
  deptPickerTarget.value = 'initiator';
  deptOpen.value = true;
}

function openWeaverDeptPicker() {
  weaverUi.objectSource = 'dept';
  deptPickerTarget.value = 'weaver';
  deptOpen.value = true;
}

function openRolePicker() {
  rolePickerTarget.value = 'initiator';
  roleOpen.value = true;
}

function openWeaverRolePicker() {
  weaverUi.objectSource = 'role';
  rolePickerTarget.value = 'weaver';
  roleOpen.value = true;
}

function openConditionUserPicker(ruleId: string) {
  conditionPickRuleId.value = ruleId;
  personTarget.value = 'condition_user';
  personOpen.value = true;
}

function onPersonConfirm(items: OrgPersonnelItem[]) {
  if (personTarget.value === 'specified') {
    specifiedUsers.value = items;
    // 勿在选人后整表 sync：会覆盖已用「+」按快照追加的多行明细
    if (operatorRows.value.length === 0) {
      syncDetailFromHeader();
    }
    return;
  }
  if (personTarget.value === 'initiator') {
    initiatorUsers.value = items;
    return;
  }
  if (personTarget.value === 'condition_user') {
    const one = items[0];
    const hit = conditionRules.value.find(
      (r) => r.id === conditionPickRuleId.value,
    );
    if (hit) {
      hit.userId = String(one?.empId || '').trim();
      hit.userName = String(one?.name || one?.empId || '').trim();
    }
  }
}

function onDeptConfirm(items: OrgDeptItem[]) {
  if (deptPickerTarget.value === 'weaver') {
    weaverUi.weaverDeptPicks = items.map((d) => ({
      id: String(d.id || '').trim(),
      name: String(d.name || d.id || '').trim() || String(d.id),
    }));
    weaverUi.deptKeyword = weaverUi.weaverDeptPicks
      .map((p) => p.name)
      .join('、');
    return;
  }
  initiatorDepts.value = items;
}

function onRoleConfirm(items: OrgRoleItem[]) {
  if (rolePickerTarget.value === 'weaver') {
    weaverUi.weaverRolePicks = items.map((r) => ({
      id: String(r.id || '').trim(),
      name: String(r.name || r.id || '').trim() || String(r.id),
    }));
    weaverUi.roleKeyword = weaverUi.weaverRolePicks
      .map((p) => p.name)
      .join('、');
    return;
  }
  initiatorRoles.value = items;
}

function sortedOperatorUserRows(): OperatorTableRow[] {
  return [...operatorRows.value]
    .filter((r) => r.refValue?.trim())
    .toSorted((a, b) => (Number(a.batch) || 0) - (Number(b.batch) || 0));
}

function sequentialApproversFromRows(): WfSequentialApprover[] {
  return sortedOperatorUserRows().map((r) => ({
    userId: r.refValue!.trim(),
    label: r.name,
  }));
}

function buildApproveProperties(): Record<string, unknown> & WfNodeProperties {
  applyWeaverToApproverMode();
  const mode = approverMode.value;
  const ar = {
    mode,
    formFieldKey: mode === 'form_field' ? formFieldKey.value.trim() : undefined,
  };

  let assigneeStrategies: WfAssigneeStrategy[] = [];
  if (mode === 'specified_users') {
    const sortedRef = sortedOperatorUserRows();
    if (sortedRef.length > 0) {
      const ids = sortedRef.map((r) => r.refValue!.trim());
      const label = sortedRef
        .map((r) => [r.refValue, r.name].filter(Boolean).join('/'))
        .join('、');
      assigneeStrategies = [{ kind: 'user', value: ids.join(','), label }];
    } else {
      const ids = specifiedUsers.value
        .map((x) => String(x.empId || '').trim())
        .filter(Boolean);
      const label = specifiedUsers.value
        .map((x) => {
          const id = String(x.empId || '').trim();
          const name = String(x.name || '').trim();
          return [id, name].filter(Boolean).join('/');
        })
        .filter(Boolean)
        .join('、');
      if (ids.length > 0) {
        assigneeStrategies = [{ kind: 'user', value: ids.join(','), label }];
      }
    }
  } else if (mode === 'form_field' && formFieldKey.value.trim()) {
    assigneeStrategies = [
      {
        kind: 'form_field',
        value: formFieldKey.value.trim(),
        label: '表单字段审批人',
      },
    ];
  } else {
    let leaderExpr: { label: string; value: string };
    switch (mode) {
      case 'dept_head': {
        leaderExpr = { label: '部门主管', value: '$resolve.deptHead' };

        break;
      }
      case 'indirect_leader': {
        leaderExpr = { label: '间接领导', value: '$resolve.indirectLeader' };

        break;
      }
      case 'initiator_self': {
        leaderExpr = { label: '本人', value: '$resolve.initiatorSelf' };

        break;
      }
      default: {
        leaderExpr = { label: '直接领导', value: '$resolve.directLeader' };
      }
    }
    assigneeStrategies = [
      {
        kind: 'expression',
        value: leaderExpr.value,
        label: leaderExpr.label,
      },
    ];
  }

  const routing = routingMode.value;
  const rowsPayload: WfApprovalOperatorRow[] = operatorRows.value.map((r) => ({
    id: r.id,
    kind: r.kind,
    name: r.name,
    refValue: r.refValue,
    level: r.level,
    countersignAttr: r.countersignAttr,
    batchCondition: r.batchCondition,
    batch: Number(r.batch) || 0,
  }));
  const seqApprovers =
    routing === 'sequential' ? sequentialApproversFromRows() : [];

  const prevBehaviors =
    (props.initialProperties as WfNodeProperties).behaviors || {};
  const behaviors = {
    ...prevBehaviors,
    cc: routing === 'cc' || ccEnabled.value,
    countersign: routing === 'all' || routing === 'any',
    sequentialApproval: routing === 'sequential',
  };

  let countersignPolicy = (props.initialProperties as WfNodeProperties)
    .countersignPolicy;
  if (routing === 'all') {
    countersignPolicy = { mode: 'all' };
  } else if (routing === 'any') {
    countersignPolicy = { mode: 'any' };
  } else {
    countersignPolicy = undefined;
  }

  const rejectPolicy: WfRejectPolicy = {
    enabled: rejectEnabled.value,
    target: rejectTarget.value,
    specifiedNodeId:
      rejectTarget.value === 'specified'
        ? rejectSpecifiedNodeId.value
        : undefined,
    allowResubmitAfterModify: rejectResubmit.value,
  };

  const timeoutPolicy: WfTimeoutPolicy = {
    enabled: timeoutEnabled.value,
    hours: Math.max(1, Number(timeoutHours.value) || 48),
    action: timeoutAction.value,
    transferUserIds:
      timeoutAction.value === 'transfer'
        ? timeoutTransferUserIds.value.trim()
        : undefined,
  };

  const assigneeDisplay =
    approverSummary.value ||
    (props.initialProperties as WfNodeProperties).assignee ||
    '待设置';

  const prev = props.initialProperties as WfNodeProperties;
  return {
    ...(props.initialProperties as object),
    approverResolve: ar,
    assigneeStrategies,
    approvalRoutingMode: routing,
    sequentialApprovers: seqApprovers,
    approvalHeaderCondition: headerCondition.value.trim() || undefined,
    approvalHeaderConditionRules:
      conditionRules.value.length > 0
        ? conditionRules.value.map((r) => ({ ...r }))
        : undefined,
    approvalHeaderBatch: headerBatchNote.value.trim() || undefined,
    approvalOperatorRows: rowsPayload,
    approvalWeaverUi: { ...weaverUi },
    behaviors,
    countersignPolicy,
    ccStrategies: ccEnabled.value
      ? ccStrategies.value.filter(
          (s) => s.kind && (s.value?.trim() || s.kind === 'dept_manager'),
        )
      : [],
    rejectPolicy,
    timeoutPolicy,
    assignee: assigneeDisplay,
    signPolicy: prev.signPolicy,
    wfSchemaVersion: WF_SCHEMA_VERSION,
  };
}

function buildStartProperties(): Record<string, unknown> & WfNodeProperties {
  const ip = grantsToInitiatorPermission();
  const summaryParts: string[] = [];
  if (ip.grants.length > 0) summaryParts.push(`${ip.grants.length} 条权限规则`);
  if (ip.minSecurityLevel !== null && ip.minSecurityLevel !== undefined) {
    summaryParts.push(`安全系数≥${ip.minSecurityLevel}`);
  }
  return {
    ...(props.initialProperties as object),
    initiatorPermission: ip,
    assignee:
      summaryParts.length > 0 ? `发起人：${summaryParts.join('；')}` : '发起人',
    wfSchemaVersion: WF_SCHEMA_VERSION,
  };
}

function handleToolbarSave() {
  handleOk();
}

function handleToolbarDelete() {
  Modal.confirm({
    title: '删除操作组',
    content: '确定删除当前操作组配置？（将清空明细与已选人员，仅本节点）',
    okText: '删除',
    okType: 'danger',
    cancelText: '取消',
    onOk() {
      operatorRows.value = [];
      specifiedUsers.value = [];
      selectedOperatorKeys.value = [];
      Object.assign(weaverUi, defaultWeaverUi());
      syncDetailFromHeader();
      message.success('已清空');
    },
  });
}

function handleOk() {
  const name = localName.value.trim();
  if (!name) {
    message.warning('请填写节点名称');
    return;
  }
  if (props.bizType === 'approve') {
    applyWeaverToApproverMode();
    if (approverMode.value === 'form_field' && !formFieldKey.value.trim()) {
      message.warning('请填写用于解析审批人的表单字段名');
      return;
    }
    const refRows = operatorRows.value.filter((r) => r.refValue?.trim());
    if (
      approverMode.value === 'specified_users' &&
      refRows.length === 0 &&
      specifiedUsers.value.length === 0
    ) {
      message.warning('请选择审批人或在明细表中录入带工号/ID 的行');
      return;
    }
    if (routingMode.value === 'sequential' && refRows.length < 2) {
      message.warning(
        '依次审批：请在明细表中至少维护 2 条带工号/ID 的行，并用「批次」列排序',
      );
      return;
    }
  }
  const properties =
    props.bizType === 'start'
      ? buildStartProperties()
      : buildApproveProperties();
  emit('save', { nodeId: props.nodeId, nodeName: name, properties });
  emit('update:open', false);
}

function handleCancel() {
  emit('update:open', false);
}
</script>

<template>
  <Modal
    :open="open"
    :title="bizType === 'approve' ? '添加操作组' : modalTitle"
    :width="bizType === 'approve' ? 928 : 640"
    :wrap-class-name="bizType === 'approve' ? 'og-weaver-replica' : ''"
    :footer="bizType === 'approve' ? null : undefined"
    :destroy-on-close="false"
    ok-text="保存"
    cancel-text="取消"
    @ok="handleOk"
    @cancel="handleCancel"
  >
    <div
      :class="
        bizType === 'approve'
          ? 'og-replica-body flex max-h-[72vh] flex-col gap-0'
          : 'max-h-[70vh] overflow-y-auto pr-1'
      "
    >
      <div v-if="bizType === 'start'" class="mb-4">
        <div class="mb-1 text-sm font-medium text-foreground">节点名称</div>
        <Input v-model:value="localName" placeholder="如：部门审批" />
      </div>

      <template v-if="bizType === 'start'">
        <Divider orientation="left">发起人权限（并集）</Divider>
        <p class="mb-3 text-xs text-muted-foreground">
          满足任一规则即可发起；部门规则包含后续新入职员工。
        </p>
        <div class="flex flex-col gap-3">
          <div>
            <div class="mb-1 text-sm font-medium">指定人员</div>
            <Space wrap>
              <Button size="small" @click="openInitiatorPersonPicker">
                选择人员
              </Button>
              <Tag
                v-for="(p, i) in initiatorUsers"
                :key="`u-${i}`"
                closable
                @close="initiatorUsers.splice(i, 1)"
              >
                {{ p.name || p.empId }}
              </Tag>
            </Space>
          </div>
          <div>
            <div class="mb-1 text-sm font-medium">指定部门</div>
            <Space wrap>
              <Button size="small" @click="openDeptPicker">选择部门</Button>
              <Tag
                v-for="(d, i) in initiatorDepts"
                :key="`d-${i}`"
                closable
                @close="initiatorDepts.splice(i, 1)"
              >
                {{ d.name }}
              </Tag>
            </Space>
          </div>
          <div>
            <div class="mb-1 text-sm font-medium">指定角色</div>
            <Space wrap>
              <Button size="small" @click="openRolePicker">选择角色</Button>
              <Tag
                v-for="(r, i) in initiatorRoles"
                :key="`r-${i}`"
                closable
                @close="initiatorRoles.splice(i, 1)"
              >
                {{ r.name }}
              </Tag>
            </Space>
          </div>
          <div>
            <div class="mb-1 text-sm font-medium">指定岗位</div>
            <Input
              v-model:value="initiatorPositionText"
              placeholder="岗位名称关键字，多个可用逗号分隔"
            />
          </div>
          <div>
            <div class="mb-1 text-sm font-medium">组织架构安全系数 ≥</div>
            <InputNumber
              v-model:value="minSecurityLevel"
              :min="0"
              :max="999"
              class="w-full"
              placeholder="不填表示不按安全系数限制"
            />
          </div>
        </div>
      </template>

      <template v-else>
        <div class="og-replica-scroll min-h-0 flex-1 overflow-y-auto pr-0">
          <div class="og-toolbar">
            <span class="og-toolbar-mark" aria-hidden="true">
              <IconifyIcon icon="mdi:vector-combine" class="og-toolbar-svg" />
            </span>
            <span class="og-toolbar-title">操作组</span>
            <span class="og-toolbar-spacer"></span>
            <Button
              type="primary"
              size="small"
              class="og-btn-save"
              @click="handleToolbarSave"
            >
              保存
            </Button>
            <Button
              size="small"
              class="og-btn-del"
              @click="handleToolbarDelete"
            >
              删除
            </Button>
            <Button
              type="text"
              size="small"
              class="og-btn-list"
              aria-label="更多"
            >
              <IconifyIcon icon="mdi:format-list-bulleted" class="text-base" />
            </Button>
          </div>

          <div class="og-section">
            <div class="og-section-head">
              <span class="og-burger" aria-hidden="true"></span>
              <span>基本信息</span>
            </div>
            <table class="og-form-table" cellpadding="0" cellspacing="0">
              <tbody>
                <tr>
                  <td class="og-td-label">操作组名称</td>
                  <td class="og-td-value" colspan="3">
                    <Input
                      v-model:value="localName"
                      class="og-field-input"
                      placeholder=""
                    />
                  </td>
                </tr>
                <tr>
                  <td class="og-td-label">对象类型</td>
                  <td class="og-td-value og-td-radio" colspan="3">
                    <RadioGroup
                      v-model:value="weaverUi.objectTypeCategory"
                      class="og-type-radio-group"
                    >
                      <Radio
                        v-for="opt in weaverObjectTypeOptions"
                        :key="opt.value"
                        :value="opt.value"
                        class="og-type-radio"
                      >
                        {{ opt.label }}
                      </Radio>
                    </RadioGroup>
                  </td>
                </tr>
                <tr>
                  <td class="og-td-label og-td-label-with-hint">
                    自动跳过
                    <Tooltip
                      title="当解析出的办理人与前序节点为同一人时，是否跳过本节点待办。若本节点有表单必填项等，请选「否」。"
                    >
                      <IconifyIcon
                        icon="mdi:help-circle-outline"
                        class="og-hint-icon"
                      />
                    </Tooltip>
                  </td>
                  <td class="og-td-value" colspan="3">
                    <RadioGroup v-model:value="weaverUi.autoSkipWhenSameActor">
                      <Radio :value="true">是</Radio>
                      <Radio :value="false">否</Radio>
                    </RadioGroup>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="og-section">
            <div class="og-section-head">
              <span class="og-burger" aria-hidden="true"></span>
              <span>对象</span>
            </div>
            <div class="og-object-wrap">
              <div
                v-if="weaverUi.objectTypeCategory === 'hr_field'"
                class="og-obj-field-row"
              >
                <span class="og-obj-label">表单字段</span>
                <Input
                  v-model:value="formFieldKey"
                  class="og-obj-search og-obj-search-wide"
                  placeholder="字段名"
                />
              </div>
              <RadioGroup
                v-else-if="weaverUi.objectTypeCategory === 'creator'"
                v-model:value="approverMode"
                class="og-object-group"
              >
                <div class="og-obj-row">
                  <span class="og-obj-label">创建人</span>
                  <Radio
                    v-for="opt in creatorApproverModeOptions"
                    :key="opt.value"
                    :value="opt.value"
                    class="og-type-radio"
                  >
                    {{ opt.label }}
                  </Radio>
                </div>
              </RadioGroup>
              <div
                v-else-if="weaverUi.objectTypeCategory === 'node_operator'"
                class="og-object-group"
              >
                <div class="og-obj-row">
                  <span class="og-obj-label">节点</span>
                  <Select
                    v-model:value="weaverUi.nodeOperatorNodeId"
                    :options="priorNodeOptions"
                    class="og-obj-search og-obj-search-wide"
                    size="small"
                    :placeholder="
                      priorNodeOptions.length > 0
                        ? '请选择前序节点'
                        : '无可选前序节点'
                    "
                    :disabled="priorNodeOptions.length === 0"
                  />
                </div>
                <div class="og-obj-row">
                  <span class="og-obj-label">取值</span>
                  <RadioGroup v-model:value="weaverUi.nodeOperatorPickMode">
                    <Radio value="self">本人</Radio>
                    <Radio value="manager">经理</Radio>
                  </RadioGroup>
                </div>
              </div>
              <RadioGroup
                v-else
                v-model:value="weaverUi.objectSource"
                class="og-object-group"
              >
                <div class="og-obj-row">
                  <Radio value="dept" />
                  <span class="og-obj-label">部门</span>
                  <Input
                    readonly
                    class="og-obj-search"
                    :value="weaverUi.deptKeyword"
                    placeholder="请选择部门"
                    @click="openWeaverDeptPicker"
                  >
                    <template #suffix>
                      <IconifyIcon
                        icon="mdi:magnify"
                        class="og-suffix-ico og-suffix-ico-click"
                        @click.stop="openWeaverDeptPicker"
                      />
                    </template>
                  </Input>
                  <span class="og-obj-sec">安全级别</span>
                  <InputNumber
                    v-model:value="weaverUi.deptSecMin"
                    :min="0"
                    :max="100"
                    class="og-sec-num"
                    size="small"
                  />
                  <span class="og-obj-dash">-</span>
                  <InputNumber
                    v-model:value="weaverUi.deptSecMax"
                    :min="0"
                    :max="100"
                    class="og-sec-num"
                    size="small"
                  />
                </div>
                <div class="og-obj-row">
                  <Radio value="role" />
                  <span class="og-obj-label">角色</span>
                  <Input
                    readonly
                    class="og-obj-search"
                    :value="weaverUi.roleKeyword"
                    placeholder="请选择角色"
                    @click="openWeaverRolePicker"
                  >
                    <template #suffix>
                      <IconifyIcon
                        icon="mdi:magnify"
                        class="og-suffix-ico og-suffix-ico-click"
                        @click.stop="openWeaverRolePicker"
                      />
                    </template>
                  </Input>
                  <span class="og-obj-sec">级别</span>
                  <Select
                    v-model:value="weaverUi.roleLevel"
                    :options="weaverRoleLevelOptions"
                    class="og-role-level"
                    size="small"
                  />
                </div>
                <div class="og-obj-row">
                  <Radio value="hr" />
                  <span class="og-obj-label">人力资源</span>
                  <Input
                    class="og-obj-search og-obj-search-wide"
                    readonly
                    :value="
                      specifiedUsers[0]?.name ||
                      specifiedUsers[0]?.empId ||
                      weaverUi.hrKeyword ||
                      ''
                    "
                    placeholder=""
                    @click="openSpecifiedPersonPicker"
                  >
                    <template #suffix>
                      <IconifyIcon
                        icon="mdi:magnify"
                        class="og-suffix-ico og-suffix-ico-click"
                        @click.stop="openSpecifiedPersonPicker"
                      />
                    </template>
                  </Input>
                </div>
                <div class="og-obj-row">
                  <Radio value="everyone" />
                  <span class="og-obj-label">所有人</span>
                  <span class="og-obj-sec og-obj-sec-only">安全级别</span>
                  <InputNumber
                    v-model:value="weaverUi.everyoneSecMin"
                    :min="0"
                    :max="100"
                    class="og-sec-num"
                    size="small"
                  />
                  <span class="og-obj-dash">-</span>
                  <InputNumber
                    v-model:value="weaverUi.everyoneSecMax"
                    :min="0"
                    :max="100"
                    class="og-sec-num"
                    size="small"
                  />
                </div>
              </RadioGroup>
            </div>
          </div>

          <div class="og-section">
            <div class="og-section-head">
              <span class="og-burger" aria-hidden="true"></span>
              <span>批次/条件</span>
            </div>
            <div class="og-batch-row">
              <span class="og-batch-lbl">条件</span>
              <Input
                v-model:value="headerCondition"
                class="og-batch-cond"
                placeholder="点击设置条件"
                readonly
                @click="openConditionBuilder"
              >
                <template #suffix>
                  <IconifyIcon
                    icon="mdi:magnify"
                    class="og-suffix-ico og-suffix-ico-click"
                    @click.stop="openConditionBuilder"
                  />
                </template>
              </Input>
              <span class="og-batch-lbl">批次</span>
              <Input
                v-model:value="headerBatchNote"
                class="og-batch-small"
                placeholder=""
              />
            </div>
          </div>

          <div class="og-section og-section-operator">
            <div class="og-subbar og-subbar-above-operator">
              <span class="og-subbar-lbl">审批策略</span>
              <RadioGroup v-model:value="routingMode" class="og-subbar-rg">
                <Radio value="all">会签</Radio>
                <Radio value="any">或签</Radio>
                <Radio value="sequential">依次</Radio>
                <Radio value="cc">抄送</Radio>
              </RadioGroup>
              <span class="og-subbar-spacer"></span>
              <Button size="small" type="primary" @click="syncDetailFromHeader">
                同步明细
              </Button>
              <Button size="small" @click="addBlankOperatorRow">空行</Button>
            </div>
            <div class="og-section-head og-section-head-row">
              <div class="og-section-head-left">
                <span class="og-burger" aria-hidden="true"></span>
                <span>操作者</span>
              </div>
              <div class="og-operator-tools">
                <button
                  type="button"
                  class="og-tool-plus"
                  aria-label="添加明细行"
                  @click="addOperatorRowFromHeader"
                >
                  +
                </button>
                <button
                  type="button"
                  class="og-tool-minus"
                  aria-label="删除所选"
                  :disabled="selectedOperatorKeys.length === 0"
                  @click="removeSelectedOperatorRows"
                >
                  −
                </button>
              </div>
            </div>
            <Table
              :columns="operatorColumns"
              :data-source="operatorRows"
              :pagination="false"
              size="small"
              bordered
              row-key="id"
              :scroll="{ x: 880, y: 220 }"
              :row-selection="operatorRowSelection"
              class="og-operator-table"
            >
              <template #bodyCell="{ column, record }">
                <template v-if="column.dataIndex === 'kind'">
                  <Select
                    v-model:value="record.kind"
                    :options="operatorKindOptions"
                    class="w-full min-w-[96px]"
                    size="small"
                  />
                </template>
                <template v-else-if="column.dataIndex === 'name'">
                  <Input
                    v-model:value="record.name"
                    size="small"
                    placeholder=""
                  />
                </template>
                <template v-else-if="column.dataIndex === 'level'">
                  <Input
                    v-model:value="record.level"
                    size="small"
                    placeholder=""
                  />
                </template>
                <template v-else-if="column.dataIndex === 'countersignAttr'">
                  <Select
                    v-model:value="record.countersignAttr"
                    :options="operatorCountersignAttrOptions"
                    class="w-full min-w-[88px]"
                    size="small"
                  />
                </template>
                <template v-else-if="column.dataIndex === 'batchCondition'">
                  <Input
                    v-model:value="record.batchCondition"
                    size="small"
                    placeholder=""
                  />
                </template>
                <template v-else-if="column.dataIndex === 'batch'">
                  <InputNumber
                    v-model:value="record.batch"
                    :min="0"
                    :max="9999"
                    :precision="2"
                    :step="0.01"
                    size="small"
                    class="w-full min-w-[72px]"
                  />
                </template>
              </template>
            </Table>
          </div>
        </div>

        <div class="og-footer-close-wrap">
          <button type="button" class="og-footer-close" @click="handleCancel">
            关闭
          </button>
        </div>
      </template>
    </div>

    <Modal
      v-model:open="conditionOpen"
      title="规则条件设置"
      width="980px"
      :mask-closable="false"
      :footer="null"
      class="og-condition-designer"
      @ok="onConditionOk"
    >
      <div class="og-cond-toolbar">
        <Button type="primary" size="small" @click="onConditionOk">保存</Button>
        <Button size="small" @click="clearConditionRules">清空</Button>
      </div>
      <div class="og-cond-header-row">
        <Button size="small" type="dashed" @click="addConditionRule">
          + 添加规则
        </Button>
      </div>
      <div class="og-cond-list">
        <div
          v-for="(rule, idx) in conditionRules"
          :key="rule.id"
          class="og-cond-item"
        >
          <div class="og-cond-join">
            <Select
              v-if="idx > 0"
              v-model:value="rule.joinWithPrev"
              :options="conditionJoinOptions"
              class="og-cond-join-select"
              size="small"
            />
            <span v-else class="og-cond-first">首条</span>
          </div>
          <div class="og-cond-row">
            <Select
              v-model:value="rule.type"
              :options="conditionTypeOptions"
              class="og-cond-col-type"
              size="small"
              @change="onConditionTypeChange(rule)"
            />
            <template v-if="rule.type === 'form_compare'">
              <Input
                v-model:value="rule.formFieldKey"
                class="og-cond-col-field"
                size="small"
                placeholder="字段名"
              />
              <Select
                v-model:value="rule.formFieldType"
                :options="conditionFieldTypeOptions"
                class="og-cond-col-op"
                size="small"
                @change="onConditionFieldTypeChange(rule)"
              />
              <Select
                v-model:value="rule.op"
                :options="getConditionOpOptions(rule)"
                class="og-cond-col-op"
                size="small"
              />
              <InputNumber
                v-if="rule.formFieldType === 'number'"
                v-model:value="rule.value"
                class="og-cond-col-val"
                size="small"
                placeholder="数字值"
              />
              <InputNumber
                v-if="
                  rule.formFieldType === 'number' &&
                  (rule.op === 'between' || rule.op === 'not_between')
                "
                v-model:value="rule.valueTo"
                class="og-cond-col-val"
                size="small"
                placeholder="数字上限"
              />
              <Select
                v-else-if="rule.formFieldType === 'boolean'"
                v-model:value="rule.value"
                :options="conditionBooleanValueOptions"
                class="og-cond-col-val"
                size="small"
              />
              <Input
                v-else-if="rule.formFieldType !== 'date'"
                v-model:value="rule.value"
                class="og-cond-col-val"
                size="small"
                :placeholder="
                  rule.formFieldType === 'date' ? '日期值，如 2026-04-13' : '输入值'
                "
              />
              <Input
                v-else
                v-model:value="rule.value"
                class="og-cond-col-val"
                size="small"
                placeholder="开始日期，如 2026-04-13"
              />
              <Input
                v-if="
                  rule.formFieldType === 'date' &&
                  (rule.op === 'between' || rule.op === 'not_between')
                "
                v-model:value="rule.valueTo"
                class="og-cond-col-val"
                size="small"
                placeholder="结束日期，如 2026-04-30"
              />
            </template>
            <template v-else>
              <Select
                v-model:value="rule.actorSource"
                :options="conditionActorSourceOptions"
                class="og-cond-col-actor"
                size="small"
                @change="onConditionActorSourceChange(rule)"
              />
              <Select
                v-if="rule.actorSource === 'node'"
                v-model:value="rule.actorNodeId"
                :options="priorNodeOptions"
                class="og-cond-col-node"
                size="small"
                placeholder="前序节点"
              />
              <template v-if="rule.type === 'actor_security'">
                <Select
                  v-model:value="rule.op"
                  :options="conditionOpOptions"
                  class="og-cond-col-op"
                  size="small"
                />
                <Input
                  v-model:value="rule.value"
                  class="og-cond-col-val"
                  size="small"
                  placeholder="安全级别值"
                />
              </template>
              <template v-else>
                <Input
                  :value="rule.userName || rule.userId || ''"
                  class="og-cond-col-user"
                  size="small"
                  placeholder="请选择人员"
                  readonly
                />
                <Button size="small" @click="openConditionUserPicker(rule.id)">
                  选人
                </Button>
              </template>
            </template>
            <Button
              size="small"
              danger
              type="text"
              @click="removeConditionRule(rule.id)"
            >
              ×
            </Button>
          </div>
        </div>
        <div v-if="conditionRules.length === 0" class="og-cond-empty">
          暂无条件，点击「添加规则」
        </div>
      </div>
    </Modal>

    <SelectPersonnelModal
      :open="personOpen"
      :default-selected="
        personTarget === 'specified'
          ? specifiedUsers
          : personTarget === 'initiator'
            ? initiatorUsers
            : []
      "
      @update:open="(v: boolean) => (personOpen = v)"
      @confirm="onPersonConfirm"
    />
    <SelectDepartmentModal
      :open="deptOpen"
      :default-checked-ids="
        deptPickerTarget === 'weaver'
          ? (weaverUi.weaverDeptPicks ?? []).map((p) => String(p.id))
          : initiatorDepts.map((d) => String(d.id))
      "
      @update:open="(v: boolean) => (deptOpen = v)"
      @confirm="onDeptConfirm"
    />
    <SelectRoleModal
      :open="roleOpen"
      :default-selected-ids="
        rolePickerTarget === 'weaver'
          ? (weaverUi.weaverRolePicks ?? []).map((p) => String(p.id))
          : initiatorRoles.map((r) => String(r.id))
      "
      @update:open="(v: boolean) => (roleOpen = v)"
      @confirm="onRoleConfirm"
    />
  </Modal>
</template>

<style>
/* 泛微「添加操作组」弹窗外观（Teleport 到 body，需非 scoped） */
.og-weaver-replica .ant-modal-header {
  padding: 8px 14px;
  margin: 0;
  background: linear-gradient(180deg, #2f73d8 0%, #1e5bb8 100%);
  border-bottom: 1px solid #154a9c;
  border-radius: 0;
}

.og-weaver-replica .ant-modal-title {
  color: #fff !important;
  font-size: 14px;
  font-weight: 600;
}

.og-weaver-replica .ant-modal-close {
  color: rgba(255, 255, 255, 0.92) !important;
}

.og-weaver-replica .ant-modal-close:hover {
  color: #fff !important;
}

.og-weaver-replica .ant-modal-body {
  padding: 0 !important;
  background: #f0f2f5;
}

.og-weaver-replica .ant-modal-content {
  padding: 0;
  border-radius: 2px;
  overflow: hidden;
}

.og-replica-body {
  background: #f0f2f5;
}

.og-replica-scroll {
  background: #fff;
  border: 1px solid #d9d9d9;
  margin: 8px;
}

.og-toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 10px;
  background: linear-gradient(180deg, #fafdff 0%, #e8f0fc 100%);
  border-bottom: 1px solid #c5d6eb;
}

.og-toolbar-mark {
  display: inline-flex;
  width: 28px;
  height: 28px;
  align-items: center;
  justify-content: center;
  background: #6b4fbb;
  border-radius: 2px;
}

.og-toolbar-svg {
  font-size: 18px;
  color: #fff;
}

.og-toolbar-title {
  font-size: 13px;
  font-weight: 600;
  color: #1a3a5c;
}

.og-toolbar-spacer {
  flex: 1;
}

.og-btn-save.ant-btn-primary {
  height: 24px;
  padding: 0 14px;
  font-size: 12px;
  border-radius: 2px;
}

.og-btn-del {
  height: 24px;
  padding: 0 12px;
  font-size: 12px;
  color: #0d8fbf !important;
  border-color: #7ec8e0 !important;
  border-radius: 2px;
}

.og-btn-list {
  min-width: 28px;
  color: #4a6fa5 !important;
}

.og-section {
  margin: 0;
  border-bottom: 1px solid #d9d9d9;
  background: #fff;
}

.og-section-head {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 10px;
  font-size: 13px;
  font-weight: 600;
  color: #1a1a1a;
  background: linear-gradient(180deg, #f7f9fc 0%, #e9eef5 100%);
  border-bottom: 1px solid #d0d8e4;
}

.og-section-head-row {
  justify-content: space-between;
}

.og-section-head-left {
  display: flex;
  align-items: center;
  gap: 8px;
}

.og-burger::before {
  display: inline-block;
  width: 12px;
  font-size: 11px;
  line-height: 1;
  color: #5c6b82;
  text-align: center;
  content: '≡';
}

.og-form-table {
  width: 100%;
  font-size: 12px;
  border-collapse: collapse;
}

.og-td-label {
  width: 108px;
  padding: 6px 10px;
  color: #333;
  vertical-align: middle;
  background: #f5f7fa;
  border: 1px solid #d9d9d9;
}

.og-td-label-with-hint {
  white-space: nowrap;
}

.og-td-value {
  padding: 4px 8px;
  vertical-align: middle;
  background: #fff;
  border: 1px solid #d9d9d9;
}

.og-td-radio {
  padding: 6px 8px;
}

.og-field-input {
  height: 26px;
  font-size: 12px;
  border-radius: 2px !important;
}

.og-type-radio-group {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 14px;
  line-height: 1.6;
}

.og-type-radio {
  margin: 0 !important;
  font-size: 12px;
}

.og-object-wrap {
  padding: 4px 8px 8px;
}

.og-obj-field-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px 8px;
  padding: 4px 4px 8px 2px;
  font-size: 12px;
}

.og-object-group {
  display: flex;
  width: 100%;
  flex-direction: column;
  gap: 4px;
}

.og-obj-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px 8px;
  padding: 4px 4px 4px 2px;
  font-size: 12px;
}

.og-obj-label {
  min-width: 52px;
  color: #333;
}

.og-hint-icon {
  margin-left: 4px;
  color: #8c8c8c;
  font-size: 14px;
  vertical-align: -2px;
  cursor: help;
}

.og-obj-search {
  flex: 1;
  min-width: 160px;
  max-width: 360px;
  height: 26px;
  font-size: 12px;
}

.og-obj-search-wide {
  max-width: 520px;
}

.og-obj-sec {
  margin-left: 4px;
  color: #555;
}

.og-obj-sec-only {
  margin-left: 28px;
}

.og-obj-dash {
  color: #888;
}

.og-sec-num {
  width: 64px !important;
}

.og-suffix-ico {
  font-size: 16px;
  color: #888;
  cursor: pointer;
}

.og-suffix-ico-click {
  padding: 2px;
}

.og-role-level {
  width: 120px !important;
  height: 26px !important;
}

.og-condition-designer .ant-modal-header {
  background: linear-gradient(180deg, #2f73d8 0%, #1e5bb8 100%);
  border-bottom: 1px solid #154a9c;
}

.og-condition-designer .ant-modal-title {
  color: #fff !important;
}

.og-condition-designer .ant-modal-close {
  color: rgba(255, 255, 255, 0.9) !important;
}

.og-cond-toolbar {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-bottom: 8px;
}

.og-cond-header-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}

.og-cond-list {
  max-height: 440px;
  padding-right: 4px;
  overflow: auto;
}

.og-cond-item {
  display: grid;
  grid-template-columns: 64px 1fr;
  gap: 8px;
  align-items: center;
  padding: 6px 0;
  border-top: 1px solid #edf2f7;
}

.og-cond-join {
  display: flex;
  justify-content: center;
}

.og-cond-join-select {
  width: 62px;
}

.og-cond-first {
  font-size: 12px;
  color: #64748b;
}

.og-cond-row {
  display: flex;
  gap: 8px;
  align-items: center;
}

.og-cond-col-type {
  width: 150px;
}

.og-cond-col-field {
  width: 180px;
}

.og-cond-col-op {
  width: 86px;
}

.og-cond-col-val {
  width: 180px;
}

.og-cond-col-actor {
  width: 130px;
}

.og-cond-col-node {
  width: 170px;
}

.og-cond-col-user {
  width: 200px;
}

.og-cond-empty {
  padding: 18px 0;
  color: #94a3b8;
  text-align: center;
}

.og-batch-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 12px;
  padding: 8px 10px 10px;
  font-size: 12px;
  background: #fff;
}

.og-batch-lbl {
  color: #333;
}

.og-batch-cond {
  flex: 1;
  min-width: 200px;
  max-width: 520px;
  height: 26px;
}

.og-batch-small {
  width: 120px;
  height: 26px;
}

.og-operator-tools {
  display: flex;
  gap: 4px;
}

.og-tool-plus,
.og-tool-minus {
  display: inline-flex;
  width: 22px;
  height: 22px;
  align-items: center;
  justify-content: center;
  padding: 0;
  font-size: 16px;
  font-weight: 700;
  line-height: 1;
  cursor: pointer;
  border: 1px solid #b7eb8f;
  border-radius: 2px;
}

.og-tool-plus {
  color: #389e0d;
  background: #f6ffed;
}

.og-tool-minus {
  color: #cf1322;
  background: #fff1f0;
  border-color: #ffa39e;
}

.og-tool-minus:disabled {
  cursor: not-allowed;
  opacity: 0.45;
}

.og-operator-table .ant-table {
  font-size: 12px;
}

.og-operator-table .ant-table-thead > tr > th {
  padding: 6px 8px !important;
  font-size: 12px !important;
  background: #e8eef5 !important;
}

.og-operator-table .ant-table-tbody > tr > td {
  padding: 4px 6px !important;
}

.og-subbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding: 6px 8px 8px;
  font-size: 12px;
  background: #fafafa;
  border-top: 1px solid #e8e8e8;
}

.og-subbar-above-operator {
  margin: 0;
  border-top: none;
  border-bottom: 1px solid #e8e8e8;
}

.og-subbar-lbl {
  font-weight: 600;
  color: #444;
}

.og-subbar-spacer {
  flex: 1;
}

.og-subbar-rg {
  display: inline-flex;
  flex-wrap: wrap;
  gap: 8px 12px;
  font-size: 12px;
}

.og-footer-close-wrap {
  padding: 10px 0 12px;
  text-align: center;
  background: #f0f2f5;
}

.og-footer-close {
  padding: 0;
  font-size: 13px;
  color: #1677ff;
  text-decoration: underline;
  cursor: pointer;
  background: none;
  border: none;
}

.og-footer-close:hover {
  color: #0958d9;
}
</style>
