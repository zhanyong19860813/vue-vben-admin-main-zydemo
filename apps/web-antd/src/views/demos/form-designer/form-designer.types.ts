/**
 * 表单设计器 - 与 VbenFormSchema 兼容的类型定义
 */
import type { VbenFormSchema } from '#/adapter/form';

export type FormDesignerSchemaItem = VbenFormSchema;

/** 可用的表单组件类型及默认配置 */
export const FORM_COMPONENT_OPTIONS = [
  {
    component: 'Input',
    label: '输入框',
    defaultProps: { placeholder: '请输入' },
  },
  {
    component: 'InputNumber',
    label: '数字输入',
    defaultProps: { placeholder: '请输入数字', min: 0, max: 999999 },
  },
  {
    component: 'InputPassword',
    label: '密码框',
    defaultProps: { placeholder: '请输入密码' },
  },
  {
    component: 'Textarea',
    label: '多行文本',
    defaultProps: { placeholder: '请输入', rows: 3 },
  },
  {
    component: 'Select',
    label: '下拉选择',
    defaultProps: { options: [], placeholder: '请选择' },
  },
  {
    component: 'RadioGroup',
    label: '单选框组',
    defaultProps: { options: [] },
  },
  {
    component: 'CheckboxGroup',
    label: '复选框组',
    defaultProps: { options: [] },
  },
  {
    component: 'DatePicker',
    label: '日期选择',
    defaultProps: { placeholder: '选择日期' },
  },
  {
    component: 'RangePicker',
    label: '日期范围',
    defaultProps: { placeholder: ['开始日期', '结束日期'] },
  },
  {
    component: 'TimePicker',
    label: '时间选择',
    defaultProps: { placeholder: '选择时间' },
  },
  {
    component: 'Switch',
    label: '开关',
    defaultProps: { checkedChildren: '开', unCheckedChildren: '关' },
  },
  {
    component: 'TreeSelect',
    label: '树选择',
    defaultProps: { treeData: [], placeholder: '请选择' },
  },
  {
    component: 'AutoComplete',
    label: '自动完成',
    defaultProps: { options: [], placeholder: '请输入' },
  },
  {
    component: 'Cascader',
    label: '级联选择',
    defaultProps: { options: [], placeholder: '请选择' },
  },
  {
    component: 'Rate',
    label: '评分',
    defaultProps: {},
  },
  {
    component: 'Upload',
    label: '文件上传',
    defaultProps: { name: 'file', action: '#', listType: 'picture-card' },
  },
] as const;

/** 根据组件类型创建默认 schema 项 */
export function createDefaultSchemaItem(
  component: string,
  index: number,
): FormDesignerSchemaItem {
  const option = FORM_COMPONENT_OPTIONS.find((o) => o.component === component);
  const fieldName = `field_${index}_${Date.now()}`;
  const label = option?.label ?? component;

  return {
    fieldName,
    label: `${label} ${index}`,
    component: component as FormDesignerSchemaItem['component'],
    componentProps: { ...(option?.defaultProps ?? { placeholder: '请输入' }) },
  } as FormDesignerSchemaItem;
}
