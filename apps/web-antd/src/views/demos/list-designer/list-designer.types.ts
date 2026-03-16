/**
 * 列表设计器 - 与 QueryTableSchema 兼容的类型定义
 */
import type { QueryTableSchema } from '#/components/QueryTable/types';

export type ListDesignerSchema = QueryTableSchema;

/** 查询表单字段项 */
export interface FormSchemaItem {
  component: string;
  fieldName: string;
  label: string;
  /** Select 等控件的数据源配置 */
  componentProps?: {
    options?: Array<{ label: string; value: string }>;
    dataSourceType?: 'manual' | 'dictionary';
    dictionaryId?: string;
  };
}

/** 表格列项 */
export interface GridColumnItem {
  type?: 'checkbox' | 'seq' | 'expand';
  field?: string;
  title?: string;
  width?: number;
  minWidth?: number;
  sortable?: boolean;
}

/** 工具栏按钮项 */
export interface ToolbarActionItem {
  key: string;
  label: string;
  type?: 'primary' | 'default' | 'dashed' | 'link' | 'text';
  /** 按钮逻辑键（来自菜单按钮），列表设计器中只读展示 */
  action: string;
  confirm?: string;
  /** 表单设计器编码，对应 vben_form_desinger.code */
  form_code?: string;
  /** 是否需勾选行（编辑场景） */
  requiresSelection?: boolean;
}

/** 可用的表单组件（查询条件用） */
export const FORM_COMPONENT_OPTIONS = [
  { value: 'Input', label: '输入框' },
  { value: 'InputNumber', label: '数字' },
  { value: 'DatePicker', label: '日期' },
  { value: 'RangePicker', label: '日期范围' },
  { value: 'Select', label: '下拉' },
];

/** 创建默认表单字段 */
export function createDefaultFormSchemaItem(index: number): FormSchemaItem {
  return {
    component: 'Input',
    fieldName: `field_${index}`,
    label: `查询项${index}`,
  };
}

/** 创建默认表格列 */
export function createDefaultGridColumn(index: number): GridColumnItem {
  return {
    field: `col_${index}`,
    title: `列${index}`,
    sortable: true,
  };
}

/** 创建默认工具栏按钮（仅自定义按钮，删除/导出由 QueryTable 内置，无需配置） */
export function createDefaultToolbarAction(index: number): ToolbarActionItem {
  return {
    key: `btn_${index}`,
    label: '', // 由用户自己输入
    type: 'default',
    action: 'add', // 默认 action，用户可改
  };
}
