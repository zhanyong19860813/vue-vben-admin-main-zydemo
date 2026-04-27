import { h } from 'vue';

import type { VbenFormSchema } from '#/adapter/form';

export function applyRequiredVisualToSchema(
  schema: VbenFormSchema[],
  requiredKeys: string[],
  missingKeys: string[] = [],
): VbenFormSchema[] {
  const required = new Set((requiredKeys || []).map((k) => String(k || '').trim()).filter(Boolean));
  const missing = new Set((missingKeys || []).map((k) => String(k || '').trim()).filter(Boolean));
  return (schema || []).map((item) => {
    const fieldKey = String((item as any)?.fieldName || '').trim();
    const oldCls = String((item as any)?.formItemClass || '')
      .split(/\s+/)
      .filter(Boolean)
      .filter((x) => x !== 'wf-required-mark')
      .filter((x) => x !== 'wf-required-missing');
    const oldLabelCls = String((item as any)?.labelClass || '')
      .split(/\s+/)
      .filter(Boolean)
      .filter((x) => x !== 'wf-required-label')
      .filter((x) => x !== 'wf-required-missing-label');
    const hasRequired = fieldKey && required.has(fieldKey);
    if (hasRequired) {
      oldCls.push('wf-required-mark');
      oldLabelCls.push('wf-required-label');
    }
    if (fieldKey && missing.has(fieldKey)) {
      oldCls.push('wf-required-missing');
      oldLabelCls.push('wf-required-missing-label');
    }
    const prevComponentProps = ((item as any)?.componentProps || {}) as Record<string, any>;
    const nextComponentProps = { ...prevComponentProps };
    if (fieldKey && missing.has(fieldKey)) {
      // 与发起流程一致：直接使用 AntD `status=error` 触发控件红框。
      nextComponentProps.status = 'error';
    } else if (nextComponentProps.status === 'error') {
      delete nextComponentProps.status;
    }
    const originalSuffix = (item as any)?.suffix;
    const requiredSuffix = hasRequired
      ? () =>
          h(
            'span',
            {
              class: 'wf-required-inline-star',
              title: '必填',
              style: {
                color: '#ff4d4f',
                fontWeight: 700,
              },
            },
            '*',
          )
      : originalSuffix;
    return {
      ...(item as any),
      required: !!hasRequired,
      formItemClass: oldCls.join(' '),
      labelClass: oldLabelCls.join(' '),
      componentProps: nextComponentProps,
      suffix: requiredSuffix,
    } as VbenFormSchema;
  });
}
