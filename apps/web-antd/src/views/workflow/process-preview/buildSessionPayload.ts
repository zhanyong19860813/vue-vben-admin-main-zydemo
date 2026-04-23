import { getWorkflowFormSchemaList } from '#/api/workflow';
import type { WfNodeFormBinding } from '#/views/demos/workflow-designer/workflow-definition.schema';
import {
  applyFieldRulesToSchemaPlain,
  inferBizTypeFromGraphNode,
  jsonSafeClone,
  normalizeSchemaForPreview,
  parseStoredFormSchemaJson,
} from '#/views/workflow/wfFormPreviewUtils';
import {
  buildExtFormCode,
  parseExtFormKeyFromFormCode,
} from '#/views/workflowExtForm/registry';

import type {
  WfProcessPreviewBoundForm,
  WfProcessPreviewJson,
  WfProcessPreviewNode,
  WfProcessPreviewRecord,
  WfProcessPreviewLayout,
} from './types';

type FormRec = { id: string; code: string; title?: string; schemaJson?: string };

export interface BuildPreviewBasicForm {
  code: string;
  name: string;
  version: string;
  initiatorScope: string;
  remark: string;
}

function pickUserLabel(u: Record<string, any> | null | undefined): string {
  if (!u) return '—';
  return (
    String(u.realName || u.name || u.username || u.userName || '').trim() || '当前用户'
  );
}

function pickDeptLabel(u: Record<string, any> | null | undefined): string {
  if (!u) return '—';
  return String(u.deptName || u.departmentName || u.orgName || '').trim() || '—';
}

function formatNowForPreview(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

function nodeTitle(n: any): string {
  const textVal =
    typeof n?.text === 'object' && n?.text !== null && 'value' in n.text
      ? String((n.text as { value?: string }).value ?? '')
      : String(n?.text ?? '');
  return textVal.trim() || String(n?.id ?? '节点');
}

function nodeOwner(n: any): string {
  const strategies = Array.isArray(n?.properties?.assigneeStrategies)
    ? n.properties.assigneeStrategies
    : [];
  const parts = strategies
    .filter((s: any) => s?.kind)
    .map((s: any) => String(s.label || s.value || s.kind || '').trim())
    .filter(Boolean);
  if (parts.length) return `+ ${parts.join(' / ')}`;
  const base = String(n?.properties?.assignee ?? '').trim();
  return base ? `+ ${base}` : '—';
}

function sortFlowNodes(nodes: any[]): any[] {
  return [...nodes].sort((a, b) => {
    const ay = Number(a?.y ?? 0);
    const by = Number(b?.y ?? 0);
    if (ay !== by) return ay - by;
    return Number(a?.x ?? 0) - Number(b?.x ?? 0);
  });
}

function extKeyFromBinding(b: WfNodeFormBinding | undefined): string | null {
  if (!b) return null;
  if (b.formSource === 'ext' && String(b.extFormKey || '').trim()) {
    return String(b.extFormKey).trim();
  }
  return parseExtFormKeyFromFormCode(String(b.formCode || ''));
}

function hasUsableBindingFormCode(n: any): boolean {
  const fb = n?.properties?.formBinding as WfNodeFormBinding | undefined;
  if (extKeyFromBinding(fb)) return true;
  const code = String(fb?.formCode || '').trim();
  return !!code;
}

function isLikelyStartByHeuristic(n: any): boolean {
  const biz = String(n?.properties?.bizType || '').trim();
  if (biz === 'start') return true;
  const tp = String(n?.type || '').trim();
  const tv = String(n?.text?.value ?? n?.text ?? '').trim();
  if (tp === 'circle' && /发起|开始|起草/.test(tv)) return true;
  return false;
}

function pickBindingNode(rawNodes: any[]): any | undefined {
  const sorted = sortFlowNodes(rawNodes);
  const explicit = sorted.find((n) => hasUsableBindingFormCode(n));
  if (explicit) return explicit;
  return sorted.find((n) => isLikelyStartByHeuristic(n));
}

function buildPreviewNodesFromGraph(nodes: any[]): WfProcessPreviewNode[] {
  const sorted = sortFlowNodes(nodes).filter((n) => inferBizTypeFromGraphNode(n) !== 'condition');
  return sorted.map((n, idx) => {
    const title = nodeTitle(n);
    const owner = nodeOwner(n);
    const status: WfProcessPreviewNode['status'] = idx === 0 ? 'process' : 'wait';
    return { key: String(n?.id || title), title, owner, status };
  });
}

function buildSyntheticRecords(
  nodes: WfProcessPreviewNode[],
  now: string,
  fallback: WfProcessPreviewRecord[],
): WfProcessPreviewRecord[] {
  if (!nodes.length) return fallback.map((r) => ({ ...r }));
  const out: WfProcessPreviewRecord[] = [];
  for (const n of nodes) {
    if (n.status === 'done') {
      out.push({
        time: now,
        action: `${n.owner.replace(/^\+ /, '')} — ${n.title}`,
        result: '已完成',
        dotColor: 'green',
        tagColor: 'success',
      });
    }
  }
  const cur = nodes.find((x) => x.status === 'process');
  if (cur) {
    out.push({
      time: now,
      action: `${cur.title}（当前环节）`,
      result: '待办',
      dotColor: 'blue',
      tagColor: 'processing',
    });
  }
  return out.length ? out : fallback.map((r) => ({ ...r }));
}

function getBindingFromNode(n: any): WfNodeFormBinding | null {
  const p = (n?.properties || {}) as Record<string, any>;
  const fb = p.formBinding as WfNodeFormBinding | undefined;
  const extKey = extKeyFromBinding(fb);
  if (extKey) {
    return {
      formSource: 'ext',
      extFormKey: extKey,
      formCode: buildExtFormCode(extKey),
      formName: String(fb?.formName || extKey).trim(),
      fieldRules: (fb?.fieldRules || {}) as Record<string, any>,
    };
  }
  const code = String(fb?.formCode || p.formCode || p.bindFormCode || '').trim();
  const name = String(
    fb?.formName || p.formName || p.bindFormName || p.formTitle || p.formLabel || '',
  ).trim();
  if (!code && !name) return null;
  return {
    formCode: code,
    formName: name || code,
    fieldRules: (fb?.fieldRules || {}) as Record<string, any>,
  };
}

/**
 * 合并静态模板 + 流程管理当前基础信息 + 画布快照：若开始节点已绑定表单则拉取 schema 供新标签页动态渲染。
 */
export async function buildWfProcessPreviewSessionPayload(input: {
  baseJson: WfProcessPreviewJson;
  basicForm: BuildPreviewBasicForm;
  userInfo: Record<string, any> | undefined;
  definition: Record<string, unknown> | null | undefined;
}): Promise<{ ok: true; merged: WfProcessPreviewJson } | { ok: false; message: string }> {
  const { baseJson, basicForm, userInfo, definition } = input;
  const u = userInfo;
  const code = (basicForm.code || 'PROC').replace(/\s+/g, '_');
  const now = formatNowForPreview();

  const graphData = (definition?.graphData ?? {}) as { nodes?: any[] };
  const rawNodes = Array.isArray(graphData.nodes) ? graphData.nodes : [];
  const previewNodes = rawNodes.length
    ? buildPreviewNodesFromGraph(rawNodes)
    : baseJson.nodes.map((n) => ({ ...n }));

  const bindingNode = pickBindingNode(rawNodes);
  const bindingNorm = bindingNode ? getBindingFromNode(bindingNode) : null;
  const mainExtKey = extKeyFromBinding(bindingNorm || undefined);
  const formCode = String(bindingNorm?.formCode || '').trim();

  const metaBase = {
    ...baseJson.meta,
    formTitle: `${basicForm.name || baseJson.meta.formTitle}（预览）`,
    processNo: `WF-PREVIEW-${code}`,
    initiator: pickUserLabel(u),
    dept: pickDeptLabel(u),
    startTime: now,
    status: { text: '静态预览', color: 'default' as const },
  };

  const tableBusinessRows = [
    { field: '流程编码', value: basicForm.code || '—' },
    { field: '版本', value: basicForm.version || '—' },
    { field: '发起人范围', value: basicForm.initiatorScope || '—' },
    { field: '说明', value: basicForm.remark || '—' },
    ...baseJson.businessData.map((r) => ({ ...r })),
  ];

  const recordsFromGraph = buildSyntheticRecords(
    previewNodes,
    now,
    baseJson.records,
  );

  const nodeBindings = rawNodes
    .map((n) => ({ node: n, binding: getBindingFromNode(n) }))
    .filter((x) => !!x.binding) as { node: any; binding: WfNodeFormBinding }[];

  let needsDesignerList = false;
  for (const { binding: b } of nodeBindings) {
    if (!extKeyFromBinding(b) && String(b.formCode || '').trim()) needsDesignerList = true;
  }
  if (bindingNorm && !extKeyFromBinding(bindingNorm) && String(bindingNorm.formCode || '').trim()) {
    needsDesignerList = true;
  }

  let list: FormRec[] = [];
  if (needsDesignerList) {
    try {
      const raw = (await getWorkflowFormSchemaList()) as any;
      const rows =
        (Array.isArray(raw) ? raw : undefined) ||
        (Array.isArray(raw?.items) ? raw.items : undefined) ||
        (Array.isArray(raw?.records) ? raw.records : undefined) ||
        [];
      list = rows as FormRec[];
    } catch {
      return { ok: false, message: '加载表单定义失败，请检查接口与登录状态' };
    }
  }

  const nodeBoundForms: Record<string, WfProcessPreviewBoundForm> = {};
  for (const { node, binding: b } of nodeBindings) {
    const nodeKey = String(node?.id || '').trim();
    if (!nodeKey) continue;
    const extK = extKeyFromBinding(b);
    if (extK) {
      nodeBoundForms[nodeKey] = {
        nodeKey,
        nodeTitle: nodeTitle(node),
        formCode: b.formCode,
        formName: String(b.formName || extK).trim(),
        previewLayout: 'extComponent',
        extFormKey: extK,
        fieldRules: jsonSafeClone((b.fieldRules || {}) as any),
      };
      continue;
    }
    const fCode = String(b.formCode || '').trim();
    if (!fCode) continue;
    const rec = list.find((x) => x.code === fCode);
    if (!rec?.schemaJson?.trim()) continue;
    const parsed = parseStoredFormSchemaJson(rec.schemaJson);
    if (!parsed) continue;
    const normalized = normalizeSchemaForPreview(parsed.srcSchema);
    const rules = b.fieldRules || {};
    const decoratedMain = applyFieldRulesToSchemaPlain(normalized, rules);
    const layout: WfProcessPreviewLayout =
      parsed.layoutIsTabs && parsed.tabs.length > 0 ? 'startFormTabs' : 'startForm';
    nodeBoundForms[nodeKey] = {
      nodeKey,
      nodeTitle: nodeTitle(node),
      formCode: fCode,
      formName: String(b.formName || rec.title || fCode).trim(),
      previewLayout: layout,
      schema: jsonSafeClone(decoratedMain as unknown[]) as Record<string, unknown>[],
      tabs: layout === 'startFormTabs' ? jsonSafeClone(parsed.tabs) : undefined,
      fieldRules: jsonSafeClone(rules as any),
      workflowNoPrefix: parsed.workflowNoPrefix,
    };
  }

  if (!formCode) {
    const merged: WfProcessPreviewJson = {
      ...baseJson,
      meta: metaBase,
      previewLayout: 'table',
      businessData: tableBusinessRows,
      nodes: previewNodes,
      records: recordsFromGraph,
      actionBar: { ...baseJson.actionBar },
      nodeBoundForms,
    };
    return { ok: true, merged };
  }

  if (mainExtKey) {
    const formTitle = `${basicForm.name || bindingNorm?.formName || mainExtKey}（预览 · 硬编码 · ${mainExtKey}）`;
    const merged: WfProcessPreviewJson = {
      ...baseJson,
      meta: {
        ...metaBase,
        formTitle,
      },
      previewLayout: 'extComponent',
      businessData: [],
      startExtFormKey: mainExtKey,
      startFormSchema: undefined,
      startFormTabs: undefined,
      startFormFieldRules: undefined,
      startFormWorkflowNoPrefix: undefined,
      nodeBoundForms,
      nodes: previewNodes,
      records: recordsFromGraph,
      actionBar: { ...baseJson.actionBar },
    };
    return { ok: true, merged };
  }

  const rec = list.find((x) => x.code === formCode);
  if (!rec?.schemaJson?.trim()) {
    return {
      ok: false,
      message: `未找到表单「${formCode}」或其 schema 为空，请确认表单设计器已保存`,
    };
  }

  const parsed = parseStoredFormSchemaJson(rec.schemaJson);
  if (!parsed) {
    return { ok: false, message: '表单 schemaJson 解析失败' };
  }

  const rules = bindingNorm?.fieldRules || {};
  const normalized = normalizeSchemaForPreview(parsed.srcSchema);
  const decoratedMain = applyFieldRulesToSchemaPlain(normalized, rules);
  const wfPrefix = parsed.workflowNoPrefix;

  let previewLayout: WfProcessPreviewLayout = 'startForm';
  let startFormTabs: WfProcessPreviewJson['startFormTabs'] = undefined;
  if (parsed.layoutIsTabs && parsed.tabs.length > 0) {
    previewLayout = 'startFormTabs';
    startFormTabs = jsonSafeClone(parsed.tabs);
  }

  const formTitle =
    `${basicForm.name || (rec.title || '').trim() || formCode}（预览 · ${(rec.title || formCode).trim()}）`;

  const merged: WfProcessPreviewJson = {
    ...baseJson,
    meta: {
      ...metaBase,
      formTitle,
    },
    previewLayout,
    businessData: [],
    startFormSchema: jsonSafeClone(decoratedMain as unknown[]) as Record<string, unknown>[],
    startFormTabs,
    startFormFieldRules: jsonSafeClone(rules),
    startFormWorkflowNoPrefix: wfPrefix,
    nodeBoundForms,
    nodes: previewNodes,
    records: recordsFromGraph,
    actionBar: { ...baseJson.actionBar },
  };

  return { ok: true, merged };
}
