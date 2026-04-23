import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

const WF_RUNTIME_MOCK_STORAGE = 'wf-runtime-mock-assignee-id';

/** 流程运行台测试：模拟「办理人」工号，随请求发给后端（需 StoneApi WorkflowEngine:AllowRuntimeMockUser=true） */
let runtimeMockAssigneeUserId = '';

export function setWorkflowRuntimeMockAssigneeUserId(id: string) {
  runtimeMockAssigneeUserId = String(id || '').trim();
  try {
    if (typeof sessionStorage === 'undefined') return;
    if (runtimeMockAssigneeUserId) {
      sessionStorage.setItem(WF_RUNTIME_MOCK_STORAGE, runtimeMockAssigneeUserId);
    } else {
      sessionStorage.removeItem(WF_RUNTIME_MOCK_STORAGE);
    }
  } catch {
    /* ignore */
  }
}

export function getWorkflowRuntimeMockAssigneeUserId() {
  return runtimeMockAssigneeUserId;
}

function workflowRuntimeMockHeaders(): Record<string, string> {
  if (!runtimeMockAssigneeUserId) return {};
  return { 'X-Workflow-Mock-User-Id': runtimeMockAssigneeUserId };
}

export interface WfEngineCategoryRow {
  id: string;
  parentId: string | null;
  folderCode?: string | null;
  name: string;
  sortNo: number;
  status: number;
}

export interface WfEngineProcessRow {
  id: string;
  categoryId: string | null;
  processCode: string;
  processName: string;
  status: number;
  /** 业务开关：是否有效（与 status 独立） */
  isValid?: boolean;
  latestVersion: number;
}

export interface WfEngineTreePayload {
  categories: WfEngineCategoryRow[];
  processes: WfEngineProcessRow[];
}

export function wfEngineGetTree() {
  return requestClient.get<WfEngineTreePayload>(backendApi('workflow-engine/tree'));
}

export function wfEngineGetProcess(processDefId: string) {
  return requestClient.get<{
    processDef: {
      id: string;
      processCode: string;
      processName: string;
      categoryId: string | null;
      categoryCode?: string | null;
      status: number;
      isValid?: boolean;
      latestVersion: number;
      updatedAt?: string;
    };
    version: null | {
      id: string;
      versionNo: number;
      isPublished: boolean;
      publishedAt?: string | null;
      definitionJson: string;
      engineModelJson?: string | null;
      createdAt?: string;
    };
  }>(backendApi(`workflow-engine/process/${processDefId}`));
}

export function wfEngineSaveProcess(payload: {
  processDefId: string;
  processName: string;
  categoryId?: string | null;
  initiatorScope?: string;
  remark?: string;
  /** 是否有效，默认 true */
  isValid?: boolean;
  definition: Record<string, unknown>;
}) {
  return requestClient.post<{
    processDefId: string;
    versionId: string;
    versionNo: number;
  }>(backendApi('workflow-engine/process/save'), payload);
}

export function wfEngineCreateProcess(payload: {
  processCode: string;
  processName: string;
  categoryId?: string | null;
}) {
  return requestClient.post<{ processDefId: string }>(
    backendApi('workflow-engine/process/create'),
    payload,
  );
}

export function wfEnginePublishProcess(payload: {
  processDefId: string;
  versionNo: number;
}) {
  return requestClient.post(backendApi('workflow-engine/process/publish'), payload);
}

export function wfEngineSeedDemoTree() {
  return requestClient.post<{ skipped?: boolean }>(
    backendApi('workflow-engine/seed/demo-tree'),
    {},
  );
}

export function wfEngineCreateCategory(payload: {
  /** 不传或 null 表示根目录下新建 */
  parentId?: string | null;
  name: string;
  folderCode?: string;
  sortNo?: number;
}) {
  return requestClient.post<{ categoryId: string }>(
    backendApi('workflow-engine/category/create'),
    payload,
  );
}

export function wfEngineUpdateCategory(payload: {
  categoryId: string;
  name: string;
  folderCode?: string;
  sortNo?: number;
}) {
  return requestClient.post<{ categoryId: string }>(
    backendApi('workflow-engine/category/update'),
    payload,
  );
}

export function wfEngineDeleteCategory(payload: { categoryId: string }) {
  return requestClient.post(backendApi('workflow-engine/category/delete'), payload);
}

export function wfEngineUpdateProcessMeta(payload: {
  processDefId: string;
  processName: string;
  /** 传 null 表示挂到根下（无目录） */
  categoryId?: string | null;
}) {
  return requestClient.post<{ processDefId: string }>(
    backendApi('workflow-engine/process/update-meta'),
    payload,
  );
}

export function wfEngineDeleteProcess(payload: { processDefId: string }) {
  return requestClient.post(backendApi('workflow-engine/process/delete'), payload);
}

export interface WfEngineRuntimeStartResp {
  instanceId: string;
  instanceNo: string;
  status: 'completed' | 'running';
  nextNodeIds: string[];
}

export function wfEngineRuntimeStart(payload: {
  processCode?: string;
  processDefId?: string;
  businessKey?: string;
  title?: string;
  starterDeptId?: string;
  /** 调试用：模拟发起人（不传则使用当前登录人） */
  mockStarterUserId?: string;
  /** 调试展示用：模拟发起人姓名 */
  mockStarterName?: string;
  mainForm?: Record<string, unknown>;
  tabsData?: Record<string, unknown>;
}) {
  return requestClient.post<WfEngineRuntimeStartResp>(
    backendApi('workflow-engine/runtime/start'),
    payload,
  );
}

export interface WfEngineRuntimeTodoItem {
  taskId: string;
  taskNo: string;
  instanceId: string;
  instanceNo: string;
  processName: string;
  nodeId: string;
  nodeName: string;
  assigneeUserId: string;
  assigneeName?: string;
  taskType?: number | string;
  receivedAt?: string;
  completedAt?: string;
  businessKey?: string;
  title?: string;
  status?: number | string;
}

export function wfEngineRuntimeTodo(params?: { page?: number; pageSize?: number }) {
  return requestClient.get<{
    page: number;
    pageSize: number;
    total: number;
    items: WfEngineRuntimeTodoItem[];
  }>(backendApi('workflow-engine/runtime/todo'), {
    params,
    headers: workflowRuntimeMockHeaders(),
  });
}

/** 全员任务箱（不按当前用户过滤），用于总览 */
export function wfEngineRuntimeTodoAll(params?: {
  page?: number;
  pageSize?: number;
  box?: 'cc' | 'done' | 'todo';
}) {
  return requestClient.get<{
    page: number;
    pageSize: number;
    total: number;
    items: WfEngineRuntimeTodoItem[];
  }>(backendApi('workflow-engine/runtime/todo/all'), { params });
}

export function wfEngineRuntimeCompleteTask(payload: {
  taskId: string;
  action: 'agree' | 'reject';
  comment?: string;
  rejectToNodeId?: string;
  mainForm?: Record<string, unknown>;
  tabsData?: Record<string, unknown>;
}) {
  return requestClient.post<{
    instanceId: string;
    action: string;
    nodeMode?: string;
    status: 'ended' | 'running';
    nextNodeIds: string[];
  }>(backendApi('workflow-engine/runtime/task/complete'), payload, {
    headers: workflowRuntimeMockHeaders(),
  });
}

export function wfEngineRuntimeDeleteTasks(payload: { taskIds: string[] }) {
  return requestClient.post<{ affected: number; requested: number }>(
    backendApi('workflow-engine/runtime/task/delete-batch'),
    payload,
  );
}

export function wfEngineRuntimeInstanceDetail(instanceId: string) {
  return requestClient.get<{
    instance: Record<string, unknown>;
    process?: Record<string, unknown>;
    latestData?: Record<string, unknown>;
    tasks: Array<Record<string, unknown>>;
  }>(backendApi(`workflow-engine/runtime/instance/${instanceId}`));
}

export function wfEngineRuntimeInstanceTimeline(instanceId: string) {
  return requestClient.get<Array<Record<string, unknown>>>(
    backendApi(`workflow-engine/runtime/instance/${instanceId}/timeline`),
  );
}

export interface WfEngineAiGenerateConfigRequest {
  prompt: string;
  provider?: 'deepseek' | 'qwen';
}

export interface WfEngineAiGenerateConfigResponse {
  json: string;
  raw?: string;
  model?: string;
  provider?: string;
  source?: string;
  valid?: boolean;
  errors?: string[];
  autoRepaired?: boolean;
}

export function wfEngineAiGenerateConfig(payload: WfEngineAiGenerateConfigRequest) {
  return requestClient.post<WfEngineAiGenerateConfigResponse>(
    backendApi('workflow-engine/ai/generate-config'),
    payload,
  );
}
