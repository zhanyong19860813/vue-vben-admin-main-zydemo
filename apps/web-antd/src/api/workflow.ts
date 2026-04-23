import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

export interface WorkflowDefinitionPayload {
  processCode: string;
  processName: string;
  definitionJson: string;
}

export function saveWorkflowDefinition(payload: WorkflowDefinitionPayload) {
  return requestClient.post(backendApi('Workflow/definition/save'), payload);
}

export function publishWorkflowDefinition(payload: {
  processCode: string;
  version?: number;
}) {
  return requestClient.post(backendApi('Workflow/definition/publish'), payload);
}

export function getWorkflowTodoTasks() {
  return requestClient.get(backendApi('Workflow/task/todo'));
}

export function approveWorkflowTask(payload: { taskId: string; comment?: string }) {
  return requestClient.post(backendApi('Workflow/task/approve'), payload);
}

export function rejectWorkflowTask(payload: { taskId: string; comment?: string }) {
  return requestClient.post(backendApi('Workflow/task/reject'), payload);
}

export function startWorkflowInstance(payload: {
  processCode: string;
  businessKey?: string;
  formDataJson?: string;
  comment?: string;
}) {
  return requestClient.post(backendApi('Workflow/instance/start'), payload);
}

export function getPublishedWorkflowDefinitions() {
  return requestClient.get(backendApi('Workflow/definition/published-list'));
}

export function getWorkflowDefinition(
  params: { processCode: string; version?: number },
  /** 如 404 时静默（流程管理嵌入设计器：编码可能尚未落库） */
  requestConfig?: { skipGlobalErrorMessage?: boolean },
) {
  const qs = new URLSearchParams({ processCode: params.processCode });
  if (params.version !== undefined) qs.set('version', String(params.version));
  return requestClient.get(
    `${backendApi('Workflow/definition/get')}?${qs.toString()}`,
    requestConfig as any,
  );
}

export function getAllWorkflowDefinitions() {
  return requestClient.get(backendApi('Workflow/definition/all-list'));
}

export function saveWorkflowFormBinding(payload: {
  processCode: string;
  processVersion: number;
  formCode: string;
  formRecordId?: string;
}) {
  return requestClient.post(backendApi('Workflow/binding/save'), payload);
}

export function getWorkflowFormBinding(params: { processCode: string; processVersion?: number }) {
  const qs = new URLSearchParams({ processCode: params.processCode });
  if (params.processVersion !== undefined) qs.set('processVersion', String(params.processVersion));
  return requestClient.get(`${backendApi('Workflow/binding/get')}?${qs.toString()}`);
}

export function getWorkflowFormSchemaList(keyword?: string) {
  const qs = new URLSearchParams();
  if (keyword?.trim()) qs.set('keyword', keyword.trim());
  const q = qs.toString();
  return requestClient.get(`${backendApi('Workflow/form-schema/list')}${q ? `?${q}` : ''}`);
}
