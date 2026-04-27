import type { VbenFormSchema } from '#/adapter/form';
import type { WfNodeFormFieldRule } from '#/views/demos/workflow-designer/workflow-definition.schema';

import type { WfEngineRuntimeTodoItem } from '#/api/workflowEngine';

import {
  loadRuntimeInstanceDetailAction,
  loadRuntimeTimelineAction,
} from '../domain/runtimeWorkflowInspectActions';
import { openRuntimeActionModal } from '../domain/runtimeWorkflowActionEntry';
import { loadRuntimeTodos } from '../domain/runtimeWorkflowLoaders';
import { startRuntimeAction } from '../domain/runtimeWorkflowStartRuntime';
import { submitRuntimeTaskAction } from '../domain/runtimeWorkflowTaskSubmit';

/**
 * 运行台动作编排器。
 *
 * 说明：
 * - 本文件不直接实现业务规则，而是把页面 state/getter/setter 与 domain action 进行组装。
 * - 对外暴露统一动作：发起流程、拉取待办、打开办理弹窗、提交办理、刷新实例详情、刷新轨迹。
 * - `input` 参数较多，目的是把副作用集中注入，便于测试与复用。
 */
export function useWorkflowRuntimeActions(input: {
  // --- 发起/办理必填校验相关 ---
  applyStartRequiredVisual: (missingKeys: string[]) => Promise<void>;
  applyTaskRequiredVisual: (missingKeys: string[]) => Promise<void>;
  buildMainFieldLabelMap: (schema: VbenFormSchema[]) => Record<string, string>;
  buildStartRuntimeDebugRequestPayload: (...args: any[]) => any;
  collectRuntimePayloadFromStartHost: (opts?: { validate?: boolean }) => Promise<{
    mainForm: Record<string, unknown>;
    tabsData?: Record<string, unknown>;
  } | null>;
  collectRuntimePayloadFromTaskHost: () => Promise<{
    mainForm: Record<string, unknown>;
    tabsData?: Record<string, unknown>;
  } | null>;
  // --- API 请求适配 ---
  completeTask: (req: {
    action: 'agree' | 'reject';
    comment?: string;
    mainForm?: Record<string, unknown>;
    rejectToNodeId?: string;
    tabsData?: Record<string, unknown>;
    taskId: string;
  }) => Promise<Record<string, any>>;
  canRejectCurrentNode: () => boolean;
  currentPrimaryTodo: () => WfEngineRuntimeTodoItem | null;
  debugEvents: () => Array<Record<string, any>>;
  getActionComment: () => string;
  getActionRejectToNodeId: () => string;
  getActionRow: () => WfEngineRuntimeTodoItem | null;
  getActionType: () => 'agree' | 'reject';
  getBusinessKey: () => string;
  getInspectInstanceId: () => string;
  getMainFormJson: () => string;
  getMockStarterName: () => string;
  getMockStarterUserId: () => string;
  getProcessCode: () => string;
  getProcessDefId: () => string;
  getStartBoundFormMode: () => 'designer' | 'ext' | 'json';
  getStartDisplayFlowNo: () => string;
  getStartFormSchema: () => VbenFormSchema[];
  getStartLayoutIsTabs: () => boolean;
  getStartMetaWorkflowNo: () => string;
  getStartTabsConfigLength: () => number;
  getStartTabsFieldRulesMap: () => Record<string, WfNodeFormFieldRule>;
  getStarterDeptId: () => string;
  getTaskBoundFormMode: () => 'none' | 'designer' | 'ext' | 'snapshot';
  getTaskFormSchema: () => VbenFormSchema[];
  getTaskLayoutIsTabs: () => boolean;
  getTaskTabsConfigLength: () => number;
  getTaskTabsFieldRulesMap: () => Record<string, WfNodeFormFieldRule>;
  getTitle: () => string;
  getTodoPage: () => number;
  getTodoPageSize: () => number;
  getTodoRowsLength: () => number;
  getTimelineRows: () => Array<Record<string, any>>;
  getInstanceTasks: () => Array<Record<string, any>>;
  isTaskFormExclusiveUi: () => boolean;
  jsonSafeClone: <T>(value: T) => T;
  loadInstanceDetail: () => Promise<void>;
  loadTaskBoundForm: () => Promise<void>;
  loadTimeline: () => Promise<void>;
  loadTodos: () => Promise<void>;
  nextTick: () => Promise<void>;
  onDebugError: (action: string, err: unknown) => void;
  openAgreeAction: () => void;
  profiled: <T>(name: string, fn: () => Promise<T>) => Promise<T>;
  requestStart: (payload: Record<string, unknown>) => Promise<Record<string, any>>;
  requestInstanceDetail: (instanceId: string) => Promise<Record<string, any>>;
  requestTimeline: (instanceId: string) => Promise<Array<Record<string, any>>>;
  requestTodo: (query: Record<string, unknown>) => Promise<{ items?: any[]; total?: number }>;
  // --- 页面状态读写器 ---
  defaultRejectTargetNodeId: () => string;
  setActionModalOpen: (v: boolean) => void;
  setActionComment: (v: string) => void;
  setActionRejectToNodeId: (v: string) => void;
  setActionRow: (row: WfEngineRuntimeTodoItem | null) => void;
  setActionType: (type: 'agree' | 'reject') => void;
  setDetailLoading: (v: boolean) => void;
  setInspectInstanceId: (id: string) => void;
  setLastStartResp: (v: Record<string, unknown> | null) => void;
  setMainFormJson: (v: string) => void;
  setStartLoading: (v: boolean) => void;
  setStartRuntimePerfReset: () => void;
  setStartSubmittedHeaderFlowNo: (v: string) => void;
  setStartSubmittedInstanceNo: (v: string) => void;
  setSubmittedStartMainForm: (v: Record<string, any> | null) => void;
  setSubmittedStartTabsData: (v: Record<string, any[]> | null) => void;
  setTodoActionLoading: (v: string) => void;
  setTodoLoading: (v: boolean) => void;
  setTodoRows: (items: WfEngineRuntimeTodoItem[]) => void;
  setTodoTotal: (total: number) => void;
  setTimelineLoading: (v: boolean) => void;
  setTimelineRows: (rows: Array<Record<string, any>>) => void;
  setInstanceDetail: (detail: Record<string, any> | null) => void;
  setOperatorDisplayMap: (map: Record<string, string>) => void;
  startBoundFormGetValues: () => Promise<Record<string, unknown>>;
  startUpdateDesignerValues: (values: Record<string, unknown>) => Promise<void>;
  taskBoundFormGetValues: () => Promise<Record<string, unknown>>;
  trySyncMockAssigneeFromInstance: (instId: string) => Promise<void>;
  validateRequiredByFieldRules: (...args: any[]) => { valid: boolean; [k: string]: any };
  onWarn: (msg: string) => void;
}) {
  /**
   * 发起流程入口。
   * - 读取发起区当前表单数据（主表/页签）；
   * - 触发必填校验与请求组装；
   * - 发起成功后联动刷新实例/轨迹/待办等页面数据。
   */
  async function startRuntime() {
    await startRuntimeAction({
      applyStartRequiredVisual: input.applyStartRequiredVisual,
      buildStartRuntimeDebugRequestPayload: input.buildStartRuntimeDebugRequestPayload,
      collectRuntimePayloadFromFormHost: (opts) => input.collectRuntimePayloadFromStartHost(opts),
      currentPrimaryTodo: input.currentPrimaryTodo(),
      debugEvents: input.debugEvents(),
      jsonSafeClone: input.jsonSafeClone,
      loadInstanceDetail: input.loadInstanceDetail,
      loadTaskBoundForm: input.loadTaskBoundForm,
      loadTimeline: input.loadTimeline,
      loadTodos: input.loadTodos,
      mainFormJson: input.getMainFormJson(),
      mockStarterName: input.getMockStarterName(),
      mockStarterUserId: input.getMockStarterUserId(),
      nextTick: input.nextTick,
      openAgreeAction: input.openAgreeAction,
      processCode: input.getProcessCode(),
      processDefId: input.getProcessDefId(),
      profiled: input.profiled,
      pushDebugEvent: input.onDebugError,
      requestStart: (payload) => input.requestStart(payload),
      setInspectInstanceId: input.setInspectInstanceId,
      setLastStartResp: input.setLastStartResp,
      setMainFormJson: input.setMainFormJson,
      setStartSubmittedHeaderFlowNo: input.setStartSubmittedHeaderFlowNo,
      setStartSubmittedInstanceNo: input.setStartSubmittedInstanceNo,
      setSubmittedStartMainForm: input.setSubmittedStartMainForm,
      setSubmittedStartTabsData: input.setSubmittedStartTabsData,
      startBoundFormGetValues: input.startBoundFormGetValues,
      startBoundFormMode: input.getStartBoundFormMode(),
      startDisplayFlowNo: input.getStartDisplayFlowNo(),
      startFormSchema: input.getStartFormSchema(),
      startLayoutIsTabs: input.getStartLayoutIsTabs(),
      startLoadingSet: input.setStartLoading,
      startMetaWorkflowNo: input.getStartMetaWorkflowNo(),
      startRuntimePerfReset: input.setStartRuntimePerfReset,
      startTabsConfigLength: input.getStartTabsConfigLength(),
      startTabsFieldRulesMap: input.getStartTabsFieldRulesMap(),
      startTabsInitialMainValuesSet: () => {},
      startUpdateDesignerValues: input.startUpdateDesignerValues,
      starterDeptId: input.getStarterDeptId(),
      taskFormHasExclusiveUi: input.isTaskFormExclusiveUi,
      title: input.getTitle(),
      todoRowsLength: input.getTodoRowsLength,
      trySyncMockAssigneeFromInstance: input.trySyncMockAssigneeFromInstance,
      businessKey: input.getBusinessKey(),
    });
  }

  /**
   * 加载待办列表。
   * - 带 loading 状态；
   * - 失败统一上报到调试事件流。
   */
  async function loadTodos() {
    input.setTodoLoading(true);
    try {
      const data = await loadRuntimeTodos({
        page: input.getTodoPage(),
        pageSize: input.getTodoPageSize(),
        profiled: input.profiled,
        request: (query) => input.requestTodo(query),
      });
      input.setTodoRows(data.items as WfEngineRuntimeTodoItem[]);
      input.setTodoTotal(Number(data.total || 0));
    } catch (err) {
      input.onDebugError('加载待办', err);
    } finally {
      input.setTodoLoading(false);
    }
  }

  /**
   * 打开办理动作弹窗（同意/驳回）。
   * - 负责写入弹窗初始值；
   * - 驳回能力与默认驳回节点在这里注入。
   */
  function openAction(row: WfEngineRuntimeTodoItem, type: 'agree' | 'reject') {
    openRuntimeActionModal({
      canRejectCurrentNode: input.canRejectCurrentNode(),
      defaultRejectTargetNodeId: input.defaultRejectTargetNodeId(),
      row,
      type,
      onWarn: input.onWarn,
      setActionComment: input.setActionComment,
      setActionModalOpen: input.setActionModalOpen,
      setActionRejectToNodeId: input.setActionRejectToNodeId,
      setActionRow: input.setActionRow,
      setActionType: input.setActionType,
    });
  }

  /**
   * 提交办理动作。
   * - 先取当前 actionRow；
   * - 走 domain 提交逻辑（含必填校验、请求、刷新）；
   * - finally 阶段兜底清理按钮 loading。
   */
  async function submitAction() {
    const actionRow = input.getActionRow();
    if (!actionRow) return;
    input.setTodoActionLoading(actionRow.taskId);
    try {
      // 必填校验入口：提交时把“表单取值 + 必填规则校验函数”一起传给 domain 层。
      // 实际校验执行位置在 `submitRuntimeTaskAction` 内部（会调用 `validateRequiredByFieldRules`）。
      await submitRuntimeTaskAction({
        actionComment: input.getActionComment(),
        actionRejectToNodeId: input.getActionRejectToNodeId(),
        actionRow,
        actionType: input.getActionType(),
        applyTaskRequiredVisual: input.applyTaskRequiredVisual,
        buildMainFieldLabelMap: input.buildMainFieldLabelMap,
        // 读取当前办理表单 payload（主表 + 页签），供必填校验使用。
        collectRuntimePayloadFromFormHost: input.collectRuntimePayloadFromTaskHost,
        completeTask: input.completeTask,
        getInspectInstanceId: input.getInspectInstanceId,
        hasCurrentPrimaryTodo: () => Boolean(input.currentPrimaryTodo()),
        isTaskFormExclusiveUi: input.isTaskFormExclusiveUi,
        loadInstanceDetail: input.loadInstanceDetail,
        loadTaskBoundForm: input.loadTaskBoundForm,
        loadTimeline: input.loadTimeline,
        loadTodos: input.loadTodos,
        nextTick: input.nextTick,
        openAgreeAction: input.openAgreeAction,
        profiled: input.profiled,
        setActionModalOpen: input.setActionModalOpen,
        setInspectInstanceId: input.setInspectInstanceId,
        startBoundFormGetValues: input.taskBoundFormGetValues,
        startFormSchema: input.getTaskFormSchema(),
        taskBoundFormMode: input.getTaskBoundFormMode(),
        taskLayoutIsTabs: input.getTaskLayoutIsTabs(),
        taskTabsConfigLength: input.getTaskTabsConfigLength(),
        taskTabsFieldRulesMap: input.getTaskTabsFieldRulesMap(),
        todoRowsLength: input.getTodoRowsLength,
        trySyncMockAssigneeFromInstance: input.trySyncMockAssigneeFromInstance,
        // 必填校验函数（主表 + 页签规则）；由 submitRuntimeTaskAction 调用。
        validateRequiredByFieldRules: input.validateRequiredByFieldRules,
      });
    } catch (err) {
      input.onDebugError(input.getActionType() === 'agree' ? '同意办理' : '驳回办理', err);
    } finally {
      input.setTodoActionLoading('');
    }
  }

  /**
   * 刷新实例详情（头部信息、任务列表、当前节点相关信息来源）。
   */
  async function loadInstanceDetail() {
    await loadRuntimeInstanceDetailAction({
      inspectInstanceId: input.getInspectInstanceId(),
      onWarn: () => {},
      onError: (err) => input.onDebugError('加载实例详情', err),
      profiled: input.profiled,
      requestInstanceDetail: input.requestInstanceDetail,
      setDetailLoading: input.setDetailLoading,
      setInstanceDetail: input.setInstanceDetail,
      getTimelineRows: input.getTimelineRows,
      getInstanceTasks: input.getInstanceTasks,
      setOperatorDisplayMap: input.setOperatorDisplayMap,
    });
  }

  /**
   * 刷新轨迹（时间线 + 节点卡片展示数据）。
   */
  async function loadTimeline() {
    await loadRuntimeTimelineAction({
      inspectInstanceId: input.getInspectInstanceId(),
      onWarn: () => {},
      onError: (err) => input.onDebugError('加载实例轨迹', err),
      profiled: input.profiled,
      requestTimeline: input.requestTimeline,
      setTimelineLoading: input.setTimelineLoading,
      setTimelineRows: input.setTimelineRows,
      getInstanceTasks: input.getInstanceTasks,
      setOperatorDisplayMap: input.setOperatorDisplayMap,
    });
  }

  /** 向页面暴露统一动作 API。 */
  return { startRuntime, loadTodos, submitAction, loadInstanceDetail, loadTimeline, openAction };
}

/** `useWorkflowRuntimeActions` 的注入参数类型。 */
export type WorkflowRuntimeActionsInput = Parameters<typeof useWorkflowRuntimeActions>[0];
/** `useWorkflowRuntimeActions` 的返回 API 类型。 */
export type WorkflowRuntimeActionsApi = ReturnType<typeof useWorkflowRuntimeActions>;
