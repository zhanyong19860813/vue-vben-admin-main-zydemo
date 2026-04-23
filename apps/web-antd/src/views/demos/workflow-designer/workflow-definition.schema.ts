/**
 * 流程定义扩展 Schema（与 LogicFlow graphData 并存）
 *
 * 当前阶段：**仅设计器生成 schema**，运行时引擎（解析 assignee、任务表扩展、approve 聚合、服务端注入 $initiator）可后续按此契约实现。
 *
 * 出口条件语义：
 * - `ruleGroups.anyOf`：多个 **条件组 OR**；每组 `allOf` 为组内 **AND**。
 * - 兼容：`rules` 等价于 `ruleGroups.anyOf.length===1` 时的唯一组的 `allOf`（便于旧引擎只读 rules）。
 *
 * $initiator：生产环境建议 `wfMeta.initiatorSource === 'server'`，由 instance/start 根据登录用户写入表单上下文，勿信任前端单独提交。
 */

/** 节点业务类型（画布） */
export type WfBizNodeType = 'start' | 'approve' | 'condition' | 'cc' | 'end';

/** 处理人 / 抄送对象解析：数组顺序即尝试顺序，命中第一个可用目标即停止（会签多实例另由 countersignPolicy 描述） */
export type WfAssigneeStrategyKind =
  | 'user'
  | 'role'
  | 'dept_manager'
  | 'position'
  | 'form_field'
  | 'expression';

export interface WfAssigneeStrategy {
  kind: WfAssigneeStrategyKind;
  /** 多值逗号分隔或 JSON 数组字符串 */
  value?: string;
  label?: string;
}

/** 会签通过策略（引擎侧聚合 approve 时使用） */
export interface WfCountersignPolicy {
  mode: 'all' | 'any' | 'percent';
  /** mode=percent 时，通过比例 0–100 */
  percent?: number;
}

/** 签名要求（引擎侧校验） */
export interface WfSignPolicy {
  required: boolean;
  kind?: 'electronic' | 'handwriting' | 'any';
}

export interface WfNodeBehaviors {
  /** 是否启用抄送（不阻塞主流程） */
  cc?: boolean;
  /** 是否多实例会签 */
  countersign?: boolean;
  /** 依次审批（与 countersignPolicy / approvalRoutingMode 配合，运行时解析） */
  sequentialApproval?: boolean;
  /** 是否与 signPolicy.required 同步，便于快速展示 */
  signRequired?: boolean;
}

/** 审批人解析方式（人工节点）；与 assigneeStrategies 可并存，引擎优先读 approverResolve */
export type WfApproverResolveMode =
  | 'direct_leader'
  | 'indirect_leader'
  | 'dept_head'
  | 'initiator_self'
  | 'specified_users'
  | 'form_field';

export interface WfApproverResolve {
  mode: WfApproverResolveMode;
  /** mode=form_field 时：表单字段名（值为用户 ID 或工号，由引擎约定） */
  formFieldKey?: string;
}

/** 会签 / 或签 / 依次审批 / 抄送（互斥；抄送不阻塞主流程，见 behaviors.cc） */
export type WfApprovalRoutingMode = 'all' | 'any' | 'cc' | 'sequential';

export interface WfSequentialApprover {
  userId: string;
  label?: string;
}

/** 泛微式「添加操作组」界面状态（与引擎逻辑解耦，仅还原 UI） */
export type WfWeaverObjectTypeCategory =
  | 'general'
  | 'hr_field'
  | 'creator'
  | 'node_operator';

export type WfWeaverObjectSource = 'dept' | 'everyone' | 'hr' | 'role';

export interface WfApprovalWeaverUiState {
  objectTypeCategory: WfWeaverObjectTypeCategory;
  objectSource: WfWeaverObjectSource;
  deptKeyword: string;
  deptSecMin: number;
  deptSecMax: number;
  /** 对象区「部门」多选结果（与 deptKeyword 同步，用于还原弹窗勾选） */
  weaverDeptPicks?: { id: string; name: string }[];
  roleKeyword: string;
  roleLevel: string;
  /** 对象区「角色」多选结果（与 roleKeyword 同步） */
  weaverRolePicks?: { id: string; name: string }[];
  hrKeyword: string;
  everyoneSecMin: number;
  everyoneSecMax: number;
  /** 对象类型=节点操作者：选择哪个前序节点 */
  nodeOperatorNodeId?: string;
  nodeOperatorNodeLabel?: string;
  /** 对象类型=节点操作者：取该节点操作者中的本人/经理 */
  nodeOperatorPickMode?: 'manager' | 'self';
  /**
   * 当前审批节点：解析出的办理人与前序/本人重复时，是否允许自动跳过本节点（默认 true）。
   * 若本节点有表单必填项等，可设为 false。
   */
  autoSkipWhenSameActor?: boolean;
  /** @deprecated 请使用 autoSkipWhenSameActor；旧数据兼容 */
  nodeOperatorAutoSkip?: boolean;
}

/** 审批节点「操作者」明细表（与表头审批来源对应，供展示与引擎解析） */
export interface WfApprovalOperatorRow {
  /** 客户端行键，持久化时可写入 */
  id?: string;
  /** 类型：人力资源、角色、部门、动态 等 */
  kind: string;
  name: string;
  /** 工号/用户主键等 */
  refValue?: string;
  level?: string;
  countersignAttr?: string;
  batchCondition?: string;
  /** 依次审批时排序；同批次会签可相同序号 */
  batch: number;
}

export type WfApprovalHeaderConditionJoin = 'and' | 'or';
export type WfApprovalHeaderConditionOp =
  | '!='
  | '<'
  | '<='
  | '=='
  | '>'
  | '>='
  | 'between'
  | 'not_between';
export type WfApprovalHeaderConditionRuleType =
  | 'actor_security'
  | 'actor_user'
  | 'form_compare';
export type WfApprovalHeaderConditionActorSource = 'initiator' | 'node';
export type WfApprovalHeaderConditionFieldType =
  | 'boolean'
  | 'date'
  | 'number'
  | 'string';

export interface WfApprovalHeaderConditionRule {
  id: string;
  /** 与上一条关系；首条忽略 */
  joinWithPrev?: WfApprovalHeaderConditionJoin;
  type: WfApprovalHeaderConditionRuleType;
  /** type=form_compare */
  formFieldKey?: string;
  /** type=form_compare：字段值类型（决定比较与转换） */
  formFieldType?: WfApprovalHeaderConditionFieldType;
  /** type=actor_security/actor_user */
  actorSource?: WfApprovalHeaderConditionActorSource;
  /** actorSource=node 时必填 */
  actorNodeId?: string;
  actorNodeLabel?: string;
  op?: WfApprovalHeaderConditionOp;
  /** form_compare / actor_security 用 */
  value?: number | string;
  /** op=between/not_between 时的右边界 */
  valueTo?: number | string;
  /** actor_user 用 */
  userId?: string;
  userName?: string;
}

export type WfRejectTarget = 'initiator' | 'previous' | 'specified';

export interface WfRejectPolicy {
  enabled: boolean;
  target: WfRejectTarget;
  /** target=specified 时：画布节点 id */
  specifiedNodeId?: string;
  allowResubmitAfterModify: boolean;
}

export type WfTimeoutAction = 'auto_pass' | 'transfer';

export interface WfTimeoutPolicy {
  enabled: boolean;
  hours: number;
  action: WfTimeoutAction;
  /** action=transfer：人员 EMP_ID 逗号分隔 */
  transferUserIds?: string;
}

/** 发起人权限（并集）：指定人 / 部门 / 角色 / 岗位 + 可选安全系数下限 */
export type WfInitiatorGrantKind = 'user' | 'dept' | 'role' | 'position';

export interface WfInitiatorGrant {
  kind: WfInitiatorGrantKind;
  value?: string;
  label?: string;
}

export interface WfInitiatorPermission {
  grants: WfInitiatorGrant[];
  /** 组织架构安全系数 ≥ 该值（与 grants 并集） */
  minSecurityLevel?: number | null;
}

/** 节点绑定的表单字段展示策略（缺省按 visible） */
export type WfNodeFormFieldRule = 'visible' | 'hidden' | 'readonly' | 'required';

/** 节点表单来源：设计器库表或本地 `views/workflowExtForm/<key>/index.vue` */
export type WfNodeFormSource = 'designer' | 'ext';

/** 节点级表单绑定（与流程级绑定解耦：同表单在不同节点可有不同 fieldRules） */
export interface WfNodeFormBinding {
  /** 缺省按设计器；`ext` 时配合 `extFormKey`，`formCode` 固定为 `__wf_ext__:<key>` 便于兼容旧逻辑 */
  formSource?: WfNodeFormSource;
  /** `workflowExtForm` 下子目录名（可含一层路径，如 `pkg/foo`） */
  extFormKey?: string;
  formCode: string;
  formName?: string;
  formVersion?: string | number;
  /**
   * 主表字段用 `fieldName`；「上表+页签表格」下列字段用 `页签key::列field`（与设计器 FormTabsTablePreview 一致）。
   */
  fieldRules?: Record<string, WfNodeFormFieldRule>;
}

/** 节点 properties 完整形状（LogicFlow 另有 bizType、assignee、text 等） */
export interface WfNodeProperties {
  bizType?: WfBizNodeType;
  assignee?: string;
  desc?: string;
  assigneeStrategies?: WfAssigneeStrategy[];
  behaviors?: WfNodeBehaviors;
  /** behaviors.cc=true 时：抄送对象解析链 */
  ccStrategies?: WfAssigneeStrategy[];
  /** behaviors.countersign=true 时 */
  countersignPolicy?: WfCountersignPolicy;
  /** behaviors.signRequired / 签名节点 */
  signPolicy?: WfSignPolicy;
  wfSchemaVersion?: number;
  /** 审批人解析（审批节点） */
  approverResolve?: WfApproverResolve;
  /** 审批策略：会签 / 或签 / 依次 */
  approvalRoutingMode?: WfApprovalRoutingMode;
  /** 依次审批时的顺序 */
  sequentialApprovers?: WfSequentialApprover[];
  /** 表头：协办/过滤条件说明 */
  approvalHeaderCondition?: string;
  /** 表头条件结构化规则（支持 AND/OR、表单比较、创建人/前序节点人员条件） */
  approvalHeaderConditionRules?: WfApprovalHeaderConditionRule[];
  /** 表头：批次说明（与明细「批次」列配合） */
  approvalHeaderBatch?: string;
  /** 操作者明细表 */
  approvalOperatorRows?: WfApprovalOperatorRow[];
  /** 泛微式操作组界面字段快照 */
  approvalWeaverUi?: Partial<WfApprovalWeaverUiState>;
  /** 驳回 */
  rejectPolicy?: WfRejectPolicy;
  /** 超时 */
  timeoutPolicy?: WfTimeoutPolicy;
  /** 发起人权限（开始节点） */
  initiatorPermission?: WfInitiatorPermission;
  /** 本节点展示的表单及字段级可见性（设计器持久化在 graphData） */
  formBinding?: WfNodeFormBinding;
}

export type WfConditionScope = 'form' | 'initiator';

/** 连线条件：字段值类型（与表头条件 formFieldType 对齐，用于约束操作符与比较） */
export type WfEdgeFieldType = 'boolean' | 'date' | 'number' | 'string';

export interface WfEdgeConditionRule {
  scope: WfConditionScope;
  key: string;
  /** 缺省按 string 处理 */
  fieldType?: WfEdgeFieldType;
  op:
    | '=='
    | '!='
    | '>'
    | '>='
    | '<'
    | '<='
    | 'between'
    | 'not_between'
    | 'contains'
    | 'startsWith'
    | 'endsWith'
    | 'in'
    | 'notIn'
    | 'containsAny';
  value: string | number | boolean | string[] | number[];
  /** op 为 between / not_between 时的右边界 */
  valueTo?: string | number;
}

/** 单组：组内全部满足 */
export interface WfEdgeConditionGroup {
  allOf: WfEdgeConditionRule[];
}

/** 多组：任一组满足则该出口命中 */
export interface WfEdgeRuleGroups {
  anyOf: WfEdgeConditionGroup[];
}

export interface WfEdgeProperties {
  /** 同一源节点多条出线的检查顺序：数值越小越先判断；命中一条后不再判断其余出线（与引擎一致）。 */
  priority?: number;
  /** 是否为退回出口（用于运行时识别“驳回/退回”路径） */
  isReturn?: boolean;
  /** 单组 AND 的简写；与 ruleGroups 二存一时建议优先 ruleGroups */
  rules?: WfEdgeConditionRule[];
  ruleGroups?: WfEdgeRuleGroups;
  condition?: string;
  wfSchemaVersion?: number;
}

/** 随 definitionJson 顶层一并保存，不含画布坐标 */
export type WfInitiatorSource = 'server' | 'client' | 'hybrid';

export interface WfDefinitionTaskModelHint {
  /** 计划中的任务表/实例扩展，仅供文档与代码生成参考 */
  plannedTaskFields?: string[];
  plannedInstanceFields?: string[];
}

export interface WfDefinitionMeta {
  wfSchemaVersion: number;
  /** 发起人上下文由谁写入表单 / 流程变量 */
  initiatorSource: WfInitiatorSource;
  /** 设计器标识 */
  generatedBy?: string;
  taskModel?: WfDefinitionTaskModelHint;
}

export const WF_SCHEMA_VERSION = 2;

export function createDefaultWfDefinitionMeta(): WfDefinitionMeta {
  return {
    wfSchemaVersion: WF_SCHEMA_VERSION,
    initiatorSource: 'server',
    generatedBy: 'workflow-designer',
    taskModel: {
      plannedTaskFields: [
        'assignee_resolved',
        'assignee_strategies_snapshot',
        'cc_recipients',
        'countersign_group_id',
        'countersign_done_count',
        'sign_payload_ref',
      ],
      plannedInstanceFields: ['initiator_context_json'],
    },
  };
}

/** 顶层保存包（与后端 definition_json 根对象对齐） */
export interface WfDefinitionPayloadShape {
  processName: string;
  processCode: string;
  processVersion: number;
  wfMeta: WfDefinitionMeta;
  graphData: Record<string, unknown>;
  /** 供流程引擎直接解析的扁平执行模型（避免引擎依赖画布坐标/样式） */
  engineModel?: WfEngineDefinitionModel;
}

export type WfEngineNodeType = 'approve' | 'cc' | 'condition' | 'end' | 'start';

export interface WfEngineNodeModel {
  id: string;
  name: string;
  type: WfEngineNodeType;
  properties?: WfNodeProperties;
  /** 审批节点执行专用配置（从 properties 归一化，避免引擎自行猜语义） */
  approveConfig?: WfEngineApproveNodeConfig;
}

export interface WfEngineEdgeModel {
  id: string;
  sourceNodeId: string;
  targetNodeId: string;
  name?: string;
  desc?: string;
  priority: number;
  /** true=该出口表示“退回/驳回”语义 */
  isReturn?: boolean;
  /** 引擎优先读 ruleGroups，其次 rules，最后 condition */
  ruleGroups?: WfEdgeRuleGroups;
  rules?: WfEdgeConditionRule[];
  condition?: string;
}

/** 手动干预：支持将某节点后续强制路由到指定节点（例如 A 强制到 B） */
export interface WfEngineManualRouteRule {
  id: string;
  enabled: boolean;
  fromNodeId: string;
  /** 强制下一节点 */
  forceToNodeId: string;
  reason?: string;
}

export interface WfEngineManualInterventionModel {
  enabled: boolean;
  rules: WfEngineManualRouteRule[];
}

export interface WfEngineDefinitionModel {
  startNodeId?: string;
  nodes: WfEngineNodeModel[];
  edges: WfEngineEdgeModel[];
  /** 全局执行策略（冻结优先级与批次逻辑） */
  executionPolicy: WfEngineExecutionPolicy;
  /** 预留：运行时人工干预路由规则 */
  manualIntervention: WfEngineManualInterventionModel;
}

export type WfEngineSignMode = 'all' | 'any' | 'cc' | 'sequential';

export interface WfEngineApproveOperatorRow {
  id?: string;
  kind: string;
  name: string;
  refValue?: string;
  level?: string;
  batch: number;
  batchCondition?: string;
  signMode: WfEngineSignMode;
}

export interface WfEngineApproveNodeConfig {
  /** 执行数据源：仅使用明细表，表头仅做配置 */
  source: 'approvalOperatorRows';
  /** 不同批次命中首批即停 */
  batchMatchPolicy: 'first_matched_stop';
  /** 同批默认并发分发 */
  sameBatchDispatch: 'parallel';
  /** 相同批次默认语义：非会签（或签） */
  sameBatchDefaultSignMode: 'any';
  headerConditionText?: string;
  headerConditionRules?: WfApprovalHeaderConditionRule[];
  rows: WfEngineApproveOperatorRow[];
}

export interface WfEngineExecutionPolicy {
  /** 审批人解析优先级（从高到低） */
  resolverPriority: Array<
    'approvalWeaverUi_view_only' | 'approverResolve' | 'assigneeStrategies' | 'manualIntervention'
  >;
  /** 相同批次未显式会签属性时默认非会签 */
  sameBatchDefaultSignMode: 'any';
  /** 不同批次按顺序命中首批即停 */
  batchMatchPolicy: 'first_matched_stop';
}

export function summarizeEdgeRules(rules: WfEdgeConditionRule[] | undefined): string {
  if (!rules?.length) return '';
  return rules
    .map((r) => {
      const v = Array.isArray(r.value) ? `[${r.value.join(',')}]` : String(r.value);
      const ft = r.fieldType ? `[${r.fieldType}]` : '';
      if (r.op === 'between' || r.op === 'not_between') {
        const v2 =
          r.valueTo === undefined || r.valueTo === null ? '' : String(r.valueTo);
        return `${r.scope}.${r.key}${ft} ${r.op} ${v} ~ ${v2}`;
      }
      return `${r.scope}.${r.key}${ft} ${r.op} ${v}`;
    })
    .join(' ∧ ');
}

export function summarizeRuleGroups(ruleGroups: WfEdgeRuleGroups | undefined): string {
  if (!ruleGroups?.anyOf?.length) return '';
  return ruleGroups.anyOf
    .map((g) => summarizeEdgeRules(g.allOf))
    .filter(Boolean)
    .join(' ∨ ');
}

/**
 * 由 UI 多组规则生成 edge properties：同时写 ruleGroups；仅一组时同步 rules 供旧引擎读取。
 */
export function buildEdgeConditionProperties(params: {
  priority: number;
  groups: WfEdgeConditionRule[][];
  conditionFallback: string;
}): Pick<WfEdgeProperties, 'priority' | 'rules' | 'ruleGroups' | 'condition' | 'wfSchemaVersion'> {
  const anyOf: WfEdgeConditionGroup[] = params.groups
    .map((allOf) => ({ allOf }))
    .filter((g) => g.allOf.length > 0);

  const ruleGroups: WfEdgeRuleGroups | undefined =
    anyOf.length > 0 ? { anyOf } : undefined;
  const rules = anyOf.length === 1 ? anyOf[0]!.allOf : [];

  return {
    priority: params.priority,
    ruleGroups,
    rules,
    condition: params.conditionFallback.trim(),
    wfSchemaVersion: WF_SCHEMA_VERSION,
  };
}
