/** 与 public/workflow/process-preview-demo.json 及 sessionStorage 载荷对齐 */

import type { TabTableConfig } from '#/views/demos/form-designer/FormTabsTablePreview.vue';

export const WF_PROCESS_PREVIEW_SESSION_KEY = 'wf-process-preview-payload-v1';
export const WF_PROCESS_PREVIEW_LOCAL_KEY = 'wf-process-preview-payload-cross-tab-v1';

export type WfPreviewNodeStatus = 'done' | 'process' | 'wait';

/**
 * table：仅业务键值表；startForm：开始节点绑定表单（主表）；startFormTabs：上表+页签表格；
 * extComponent：`workflowExtForm/<key>/index.vue` 硬编码挂载
 */
export type WfProcessPreviewLayout =
  | 'table'
  | 'startForm'
  | 'startFormTabs'
  | 'extComponent';

export interface WfProcessPreviewMeta {
  processNo: string;
  formTitle: string;
  initiator: string;
  dept: string;
  startTime: string;
  status: { text: string; color?: string };
}

export interface WfProcessPreviewBusinessRow {
  field: string;
  value: string;
}

export interface WfProcessPreviewNode {
  key: string;
  title: string;
  owner: string;
  status: WfPreviewNodeStatus;
}

export interface WfProcessPreviewRecord {
  time: string;
  action: string;
  result: string;
  dotColor?: string;
  tagColor?: string;
}

export interface WfProcessPreviewActionBar {
  title: string;
  hint: string;
}

export interface WfProcessPreviewBoundForm {
  nodeKey: string;
  nodeTitle?: string;
  formCode?: string;
  formName?: string;
  previewLayout: WfProcessPreviewLayout;
  /** previewLayout=extComponent 时由前端按 key 动态 import */
  extFormKey?: string;
  schema?: Record<string, unknown>[];
  tabs?: TabTableConfig[];
  fieldRules?: Record<string, string>;
  workflowNoPrefix?: string;
}

export interface WfProcessPreviewJson {
  meta: WfProcessPreviewMeta;
  businessData: WfProcessPreviewBusinessRow[];
  nodes: WfProcessPreviewNode[];
  records: WfProcessPreviewRecord[];
  actionBar: WfProcessPreviewActionBar;
  /** 未设置或 table：展示 businessData 表格；否则由开始节点绑定表单驱动主区域 */
  previewLayout?: WfProcessPreviewLayout;
  /** 开始节点为硬编码表单时的目录 key（与 nodeBoundForms[].extFormKey 一致） */
  startExtFormKey?: string;
  /** 开始节点绑定表单的主表 schema（已做字段规则与预览用规范化，可 JSON 序列化） */
  startFormSchema?: Record<string, unknown>[];
  /** previewLayout=startFormTabs 时的页签表格配置 */
  startFormTabs?: TabTableConfig[];
  /** 与节点 formBinding.fieldRules 一致；页签列为 tabKey::field */
  startFormFieldRules?: Record<string, string>;
  startFormWorkflowNoPrefix?: string;
  /** 节点点击测试用：按 nodeKey 提供该节点绑定表单预览数据 */
  nodeBoundForms?: Record<string, WfProcessPreviewBoundForm>;
}

export function isWfProcessPreviewJson(v: unknown): v is WfProcessPreviewJson {
  if (!v || typeof v !== 'object') return false;
  const o = v as WfProcessPreviewJson;
  return (
    !!o.meta &&
    typeof o.meta === 'object' &&
    Array.isArray(o.businessData) &&
    Array.isArray(o.nodes) &&
    Array.isArray(o.records) &&
    !!o.actionBar
  );
}
