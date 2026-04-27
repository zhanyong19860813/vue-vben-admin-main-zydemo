import type { VbenFormSchema } from '#/adapter/form';
import type { WfNodeFormFieldRule } from '#/views/demos/workflow-designer/workflow-definition.schema';
import { normalizeFieldRule } from '#/views/workflow/wfFormPreviewUtils';

export function isEmptyRequiredValue(v: unknown): boolean {
  if (v === null || v === undefined) return true;
  if (typeof v === 'string') return v.trim().length === 0;
  if (Array.isArray(v)) return v.length === 0;
  return false;
}

export function buildMainFieldLabelMap(schema: VbenFormSchema[]): Record<string, string> {
  const map: Record<string, string> = {};
  for (const item of schema || []) {
    const key = String((item as any)?.fieldName || '').trim();
    if (!key) continue;
    const label = String((item as any)?.label || (item as any)?.fieldLabel || '').trim();
    map[key] = label || key;
  }
  return map;
}

export function quoteCnList(values: string[]): string {
  return values.map((x) => `【${x}】`).join('、');
}

export function validateRequiredByFieldRulesForViewer(
  fieldRules: Record<string, WfNodeFormFieldRule> | undefined,
  mainForm: Record<string, unknown>,
  tabsData: Record<string, unknown>,
  mainFieldLabelMap?: Record<string, string>,
): { message?: string; missingMainKeys?: string[]; valid: boolean } {
  const missingMain: string[] = [];
  const missingTabs: string[] = [];
  for (const [k, rawRule] of Object.entries(fieldRules || {})) {
    if (normalizeFieldRule(rawRule) !== 'required') continue;
    if (!k.includes('::')) {
      if (isEmptyRequiredValue(mainForm[k])) missingMain.push(k);
      continue;
    }
    const idx = k.indexOf('::');
    if (idx <= 0) continue;
    const tabKey = k.slice(0, idx).trim();
    const colKey = k.slice(idx + 2).trim();
    const rows = Array.isArray(tabsData[tabKey]) ? (tabsData[tabKey] as Array<Record<string, unknown>>) : [];
    if (!rows.length) {
      missingTabs.push(`${tabKey}->${colKey}`);
      continue;
    }
    const missRow = rows.findIndex((r) => isEmptyRequiredValue((r || {})[colKey]));
    if (missRow >= 0) missingTabs.push(`${tabKey}第${missRow + 1}行->${colKey}`);
  }
  if (missingMain.length) {
    const names = missingMain.map((k) => String(mainFieldLabelMap?.[k] || k).trim() || k);
    return {
      valid: false,
      message: `以下字段未填写：${quoteCnList(names)}`,
      missingMainKeys: missingMain,
    };
  }
  if (missingTabs.length) {
    return { valid: false, message: `以下页签必填字段未填写：${missingTabs.join('、')}` };
  }
  return { valid: true };
}

export function collectRequiredMainFieldKeysFromRules(
  fieldRules: Record<string, WfNodeFormFieldRule> | undefined,
): string[] {
  const out: string[] = [];
  for (const [k, rawRule] of Object.entries(fieldRules || {})) {
    if (normalizeFieldRule(rawRule) !== 'required') continue;
    const key = String(k || '').trim();
    if (!key || key.includes('::')) continue;
    out.push(key);
  }
  return [...new Set(out)];
}

export function collectRequiredMainFieldKeysFromSchema(schema: VbenFormSchema[] = []): string[] {
  const isRequiredByRules = (rules: unknown): boolean => {
    if (!rules) return false;
    if (Array.isArray(rules)) {
      return rules.some((r) => {
        if (typeof r === 'string') return r.trim().toLowerCase().includes('required');
        if (r && typeof r === 'object') return (r as Record<string, unknown>).required === true;
        return false;
      });
    }
    if (typeof rules === 'string') return rules.trim().toLowerCase().includes('required');
    if (rules && typeof rules === 'object') return (rules as Record<string, unknown>).required === true;
    return false;
  };

  const out: string[] = [];
  for (const item of schema || []) {
    const key = String((item as any)?.fieldName || (item as any)?.field || '').trim();
    if (!key) continue;
    if ((item as any)?.hide === true || (item as any)?.ifShow === false) continue;
    const schemaRequired = (item as any)?.required === true;
    const rulesRequired = isRequiredByRules((item as any)?.rules);
    const componentRequired = (item as any)?.componentProps?.required === true;
    if (schemaRequired || rulesRequired || componentRequired) out.push(key);
  }
  return [...new Set(out)];
}
