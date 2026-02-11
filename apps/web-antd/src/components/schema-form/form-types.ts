export type FormComponent =
  | 'Input'
  | 'InputNumber'
  | 'Select'
  | 'Switch';

// 单个字段 schema
export interface FormFieldSchema {
  field: string;              // 字段名，如 name
  label: string;              // 中文名
  component: FormComponent;   // 用什么组件
  required?: boolean;

  // Select 用
  options?: { label: string; value: any }[];

  // 默认值
  defaultValue?: any;
}

// 整个表单 schema
export interface FormSchema {
  fields: FormFieldSchema[];
}
