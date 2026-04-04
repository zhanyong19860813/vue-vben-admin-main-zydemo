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

/** 条件样式运算符（与 queryTableGridEnhance 一致） */
export type ListDesignerConditionalOp =
  | 'eq'
  | 'ne'
  | 'gt'
  | 'gte'
  | 'lt'
  | 'lte'
  | 'contains'
  | 'empty'
  | 'notEmpty';

/** 单列条件着色规则 */
export interface GridColumnConditionalStyle {
  op: ListDesignerConditionalOp;
  value?: string | number | boolean | null;
  backgroundColor: string;
  /** cell=仅该列单元格；row=整行 */
  scope: 'cell' | 'row';
}

/** 表格列项 */
export interface GridColumnItem {
  type?: 'checkbox' | 'seq' | 'expand';
  field?: string;
  title?: string;
  width?: number;
  minWidth?: number;
  sortable?: boolean;
  /**
   * 列顺序（越小越靠前）。未设置时按当前数组顺序渲染/保存。
   * 仅对普通列生效（type 列忽略）。
   */
  order?: number;
  /** false 时列表不显示该列，行数据仍含该字段（如编辑用 FID） */
  visible?: boolean;
  /** 满足条件时设置背景色（可多条，先匹配先生效） */
  conditionalStyles?: GridColumnConditionalStyle[];
  /** 非空 hrefTemplate 时该列渲染为链接，支持 {字段名} 占位 */
  hyperlink?: { hrefTemplate: string; openInNewTab?: boolean };
  /** Vxe 列汇总：与原生 aggFunc 一致 */
  aggFunc?: 'sum' | 'count' | 'avg' | 'min' | 'max' | 'first' | 'last';
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
    visible: true,
    order: index,
    conditionalStyles: [],
    hyperlink: { hrefTemplate: '', openInNewTab: false },
  };
}

export const CONDITIONAL_OP_OPTIONS: { value: ListDesignerConditionalOp; label: string }[] = [
  { value: 'eq', label: '等于' },
  { value: 'ne', label: '不等于' },
  { value: 'gt', label: '大于' },
  { value: 'gte', label: '大于等于' },
  { value: 'lt', label: '小于' },
  { value: 'lte', label: '小于等于' },
  { value: 'contains', label: '包含文本' },
  { value: 'empty', label: '为空' },
  { value: 'notEmpty', label: '非空' },
];

export const COLUMN_AGG_OPTIONS: {
  value: NonNullable<GridColumnItem['aggFunc']>;
  label: string;
}[] = [
  { value: 'sum', label: '求和' },
  { value: 'avg', label: '平均' },
  { value: 'min', label: '最小' },
  { value: 'max', label: '最大' },
  { value: 'count', label: '计数' },
];

/** 创建默认工具栏按钮（仅自定义按钮，删除/导出由 QueryTable 内置，无需配置） */
export function createDefaultToolbarAction(index: number): ToolbarActionItem {
  return {
    key: `btn_${index}`,
    label: '', // 由用户自己输入
    type: 'default',
    action: 'add', // 默认 action，用户可改
  };
}
