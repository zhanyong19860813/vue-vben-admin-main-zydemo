import type { VbenFormSchema } from '#/adapter/form';

import type { TabTableConfig } from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import type { WfNodeFormFieldRule } from '#/views/demos/workflow-designer/workflow-definition.schema';

export function normalizeFieldRule(rule: unknown): WfNodeFormFieldRule {
  const v = String(rule || '').trim().toLowerCase();
  if (v === 'hidden') return 'hidden';
  if (v === 'readonly') return 'readonly';
  if (v === 'required') return 'required';
  return 'visible';
}

/** 与画布 ensureGraphNodeStyles 一致：无 bizType 时由图形与文案推断 */
export function inferBizTypeFromGraphNode(n: any): string {
  let biz = n?.properties?.bizType;
  if (biz != null && String(biz).trim()) return String(biz).trim();
  switch (n?.type) {
    case 'circle': {
      const tv = String(n?.text?.value ?? n?.text ?? '');
      return /结束|完成/.test(tv) ? 'end' : 'start';
    }
    case 'diamond':
      return 'condition';
    default:
      return 'approve';
  }
}

/** 实例详情里 latestData 的主表 JSON（兼容 snake_case / camelCase 与已解析对象） */
export function readLatestMainFormRaw(latestData: unknown): unknown {
  if (!latestData || typeof latestData !== 'object') return undefined;
  const d = latestData as Record<string, unknown>;
  return d.main_form_json ?? d.mainFormJson ?? d.MainFormJson;
}

/** 实例详情里 latestData 的页签明细 JSON（兼容多种命名） */
export function readLatestTabsDataRaw(latestData: unknown): unknown {
  if (!latestData || typeof latestData !== 'object') return undefined;
  const d = latestData as Record<string, unknown>;
  return d.tabs_data_json ?? d.tabsDataJson ?? d.TabsDataJson;
}

export function parseLatestMainFormPayload(raw: unknown): Record<string, any> {
  if (raw === null || raw === undefined) return {};
  try {
    if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
      return raw as Record<string, any>;
    }
    const s = String(raw).trim();
    if (!s) return {};
    return JSON.parse(s) as Record<string, any>;
  } catch {
    return {};
  }
}

export function coerceLatestMainForm(latestData: unknown): Record<string, any> {
  return parseLatestMainFormPayload(readLatestMainFormRaw(latestData));
}

export function coerceLatestTabsData(latestData: unknown): Record<string, any[]> {
  const raw = readLatestTabsDataRaw(latestData);
  if (raw === null || raw === undefined) return {};
  try {
    if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
      const o = raw as Record<string, unknown>;
      const out: Record<string, any[]> = {};
      for (const k of Object.keys(o)) {
        if (Array.isArray(o[k])) out[k] = o[k] as any[];
      }
      return out;
    }
    const s = String(raw).trim();
    if (!s) return {};
    const o = JSON.parse(s) as Record<string, any>;
    const out: Record<string, any[]> = {};
    for (const k of Object.keys(o)) {
      if (Array.isArray(o[k])) out[k] = o[k];
    }
    return out;
  } catch {
    return {};
  }
}

export function parseStoredFormSchemaJson(raw: string | undefined): {
  layoutIsTabs: boolean;
  srcSchema: unknown[];
  tabs: TabTableConfig[];
  workflowNoPrefix?: string;
} | null {
  if (!raw?.trim()) return null;
  try {
    const parsed = JSON.parse(raw) as Record<string, any>;
    const srcSchema = Array.isArray(parsed?.schema) ? parsed.schema : [];
    const layoutType = parsed?.layout?.layoutType ?? parsed?.layoutType;
    const tabs = Array.isArray(parsed?.tabs) ? (parsed.tabs as TabTableConfig[]) : [];
    const layoutIsTabs = layoutType === 'formTabsTable' && tabs.length > 0;
    return {
      layoutIsTabs,
      srcSchema,
      tabs,
      workflowNoPrefix: parsed?.workflowNoPrefix as string | undefined,
    };
  } catch {
    return null;
  }
}

/** 与 NodeFormBindingModal：多行控件在预览里压成单行，避免弹窗/页内过高 */
export function normalizeSchemaForPreview(src: unknown[]): VbenFormSchema[] {
  return (src as any[]).map((s: any) => {
    const cp = s?.componentProps ?? {};
    const isTextarea =
      String(s?.component ?? '').toLowerCase().includes('textarea') ||
      String(cp?.type ?? '').toLowerCase() === 'textarea' ||
      typeof cp?.rows === 'number';
    if (!isTextarea) return s as VbenFormSchema;
    return {
      ...s,
      componentProps: {
        ...cp,
        rows: 1,
        autoSize: false,
        showCount: false,
      },
      formItemClass: [s?.formItemClass, 'md:col-span-2'].filter(Boolean).join(' '),
    } as VbenFormSchema;
  });
}

/**
 * 将节点 fieldRules 应用到主表 schema（可 JSON 序列化；不含 Vue 渲染函数）
 */
export function applyFieldRulesToSchemaPlain(
  src: VbenFormSchema[],
  rules: Record<string, WfNodeFormFieldRule> | undefined,
): VbenFormSchema[] {
  const rmap = rules || {};
  return src.map((item) => {
    const key = String(item.fieldName || '').trim();
    const labelKey = String((item as any)?.label || '').trim();
    let rule: WfNodeFormFieldRule = key ? normalizeFieldRule(rmap[key]) : 'visible';
    // 兼容历史数据：有些节点字段规则可能按“中文标题(label)”存储，而不是 fieldName。
    if (rule === 'visible' && labelKey) {
      rule = normalizeFieldRule(rmap[labelKey]);
    }
    const baseCp =
      typeof item.componentProps === 'object' &&
      item.componentProps !== null &&
      !Array.isArray(item.componentProps)
        ? { ...(item.componentProps as Record<string, unknown>) }
        : {};
    if (rule === 'hidden') {
      return {
        ...item,
        hide: true,
        ifShow: false,
        componentProps: { ...baseCp, readOnly: true },
      } as VbenFormSchema;
    }
    if (rule === 'readonly') {
      return {
        ...item,
        hide: false,
        ifShow: true,
        componentProps: { ...baseCp, readOnly: true },
      } as VbenFormSchema;
    }
    if (rule === 'required') {
      return {
        ...item,
        hide: false,
        ifShow: true,
        required: true as any,
        formItemClass: [String((item as any)?.formItemClass || '').trim(), 'wf-required-field']
          .filter(Boolean)
          .join(' '),
        componentProps: { ...baseCp, readOnly: false },
      } as VbenFormSchema;
    }
    return {
      ...item,
      hide: false,
      ifShow: true,
      componentProps: { ...baseCp, readOnly: false },
    } as VbenFormSchema;
  });
}

export function jsonSafeClone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}

/** 与运行台 / 流程管理：从 graph 节点 properties.formBinding 解析出的绑定 */
export type WfRuntimeNodeBinding = {
  formCode: string;
  formName: string;
  formSource?: string;
  extFormKey?: string;
  fieldRules?: Record<string, any>;
  workflowNoPrefix?: string;
};

export function parseFormBindingRecord(fb: Record<string, any>): WfRuntimeNodeBinding | null {
  const formCode = String(fb.formCode || '').trim();
  const formName = String(fb.formName || '').trim();
  const formSource = String(fb.formSource || '').trim();
  const extFormKey = String(fb.extFormKey || '').trim();
  if (!formCode && !(formSource === 'ext' && extFormKey)) return null;
  return {
    formCode,
    formName: formName || formCode || extFormKey,
    formSource,
    extFormKey,
    fieldRules: (fb.fieldRules || {}) as Record<string, any>,
    workflowNoPrefix: String(fb.workflowNoPrefix || '').trim() || undefined,
  };
}

/** 识别画布上的发起/开始节点（与运行台 runtimeStartNodeId 等逻辑一致） */
export function isLikelyStartNode(n: any): boolean {
  if (String(n?.properties?.bizType || '').trim() === 'start') return true;
  const biz = inferBizTypeFromGraphNode(n);
  if (biz === 'start') return true;
  const tv = String(n?.text?.value ?? n?.text ?? '').trim();
  return /发起|开始|起草/.test(tv);
}

/** 发起节点（或首个节点）上的表单绑定 */
export function getStartNodeBinding(definitionJson: string): WfRuntimeNodeBinding | null {
  try {
    const parsed = JSON.parse(definitionJson) as Record<string, any>;
    const graphData = (parsed?.graphData ?? {}) as { nodes?: any[] };
    const nodes = Array.isArray(graphData.nodes) ? graphData.nodes : [];
    const start = nodes.find((n) => isLikelyStartNode(n)) ?? nodes[0];
    if (!start) return null;
    const fb = (start?.properties?.formBinding ?? {}) as Record<string, any>;
    return parseFormBindingRecord(fb);
  } catch {
    return null;
  }
}

/** 指定节点上的表单绑定（无则 null，不做回退） */
export function getNodeBindingFromDefinition(
  definitionJson: string,
  nodeId: string,
): WfRuntimeNodeBinding | null {
  const id = String(nodeId || '').trim();
  if (!id || !definitionJson.trim()) return null;
  try {
    const parsed = JSON.parse(definitionJson) as Record<string, any>;
    const nodes = (parsed?.graphData?.nodes ?? []) as any[];
    const node = Array.isArray(nodes) ? nodes.find((n) => String(n?.id ?? '').trim() === id) : null;
    if (!node) return null;
    const fb = (node?.properties?.formBinding ?? {}) as Record<string, any>;
    return parseFormBindingRecord(fb);
  } catch {
    return null;
  }
}

/**
 * 办理节点未单独配置 formBinding 时，沿用发起节点表单（与「只配发起、不配审批」的常见建模一致）。
 */
export function resolveNodeFormBindingWithStartFallback(
  definitionJson: string,
  nodeId: string,
): {
  binding: WfRuntimeNodeBinding | null;
  usedStartFallback: boolean;
  nodeFoundInGraph: boolean;
} {
  const id = String(nodeId || '').trim();
  if (!id || !definitionJson.trim()) {
    return { binding: null, usedStartFallback: false, nodeFoundInGraph: false };
  }
  let nodes: any[] = [];
  let node: any = null;
  try {
    const parsed = JSON.parse(definitionJson) as Record<string, any>;
    nodes = (parsed?.graphData?.nodes ?? []) as any[];
    node = Array.isArray(nodes) ? nodes.find((n) => String(n?.id ?? '').trim() === id) : null;
  } catch {
    return { binding: null, usedStartFallback: false, nodeFoundInGraph: false };
  }
  if (!node) {
    return { binding: null, usedStartFallback: false, nodeFoundInGraph: false };
  }
  const direct = parseFormBindingRecord((node?.properties?.formBinding ?? {}) as Record<string, any>);
  if (direct) {
    return { binding: direct, usedStartFallback: false, nodeFoundInGraph: true };
  }
  const startNode = nodes.find((n) => isLikelyStartNode(n)) ?? nodes[0];
  if (startNode && String(startNode?.id ?? '').trim() === id) {
    return { binding: null, usedStartFallback: false, nodeFoundInGraph: true };
  }
  const startB = getStartNodeBinding(definitionJson);
  if (startB) {
    return { binding: startB, usedStartFallback: true, nodeFoundInGraph: true };
  }
  return { binding: null, usedStartFallback: false, nodeFoundInGraph: true };
}
