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
