/**
 * 表单设计器 - 与 VbenFormSchema 兼容的类型定义
 */
import { backendApi } from '#/api/constants';
import type { VbenFormSchema } from '#/adapter/form';

export type FormDesignerSchemaItem = VbenFormSchema;

/** 表单类型：普通 / 流程（流程表单可配置编号前缀与内置字段） */
export type FormDesignerCategory = 'general' | 'workflow';

/**
 * 流程表单内置字段标记（保存在 schema 项 componentProps.workflowBuiltin）
 * 运行时由流程引擎或打开脚本赋值：流程编号按前缀+YYMMDD+四位流水生成等
 */
export type WorkflowBuiltinKind =
  | 'flowNo'
  | 'flowTitle'
  | 'userName'
  | 'employeeNo'
  | 'dept'
  | 'position'
  | 'timestamp';

/** 流程默认字段名（稳定英文，便于落库） */
export const WORKFLOW_FORM_FIELD_NAMES = {
  flowNo: 'wf_process_no',
  userName: 'wf_user_name',
  employeeNo: 'wf_employee_no',
  dept: 'wf_dept_name',
  position: 'wf_position_name',
  timestamp: 'wf_timestamp',
} as const;

function formatYYMMDD(d: Date): string {
  const y = String(d.getFullYear()).slice(-2);
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}${m}${day}`;
}

/**
 * 生成「流程表单」默认字段：流程编号、姓名、工号、部门、岗位、时间戳
 * 编号规则文案：前缀 + 两位年两位月两位日 + 四位流水号
 */
export function createWorkflowFormDefaultSchema(prefix: string): FormDesignerSchemaItem[] {
  const p = (prefix || 'WF').trim() || 'WF';
  const ymd = formatYYMMDD(new Date());
  const example = `${p}${ymd}0001`;

  return [
    {
      fieldName: WORKFLOW_FORM_FIELD_NAMES.flowNo,
      label: '流程编号',
      component: 'Input',
      componentProps: {
        readOnly: true,
        placeholder: `示例：${example}；规则：${p} + YYMMDD + 四位流水`,
        workflowBuiltin: 'flowNo' as WorkflowBuiltinKind,
      },
    } as FormDesignerSchemaItem,
    {
      fieldName: WORKFLOW_FORM_FIELD_NAMES.userName,
      label: '姓名',
      component: 'Input',
      componentProps: {
        readOnly: true,
        placeholder: '当前登录人姓名',
        workflowBuiltin: 'userName' as WorkflowBuiltinKind,
      },
    } as FormDesignerSchemaItem,
    {
      fieldName: WORKFLOW_FORM_FIELD_NAMES.employeeNo,
      label: '工号',
      component: 'Input',
      componentProps: {
        readOnly: true,
        placeholder: '当前登录人工号',
        workflowBuiltin: 'employeeNo' as WorkflowBuiltinKind,
      },
    } as FormDesignerSchemaItem,
    {
      fieldName: WORKFLOW_FORM_FIELD_NAMES.dept,
      label: '部门',
      component: 'Input',
      componentProps: {
        readOnly: true,
        placeholder: '当前登录人部门',
        workflowBuiltin: 'dept' as WorkflowBuiltinKind,
      },
    } as FormDesignerSchemaItem,
    {
      fieldName: WORKFLOW_FORM_FIELD_NAMES.position,
      label: '岗位',
      component: 'Input',
      componentProps: {
        readOnly: true,
        placeholder: '当前登录人岗位',
        workflowBuiltin: 'position' as WorkflowBuiltinKind,
      },
    } as FormDesignerSchemaItem,
    {
      fieldName: WORKFLOW_FORM_FIELD_NAMES.timestamp,
      label: '时间戳',
      component: 'Input',
      componentProps: {
        readOnly: true,
        placeholder: '提交/保存时由系统写入（如 ISO 时间）',
        workflowBuiltin: 'timestamp' as WorkflowBuiltinKind,
      },
    } as FormDesignerSchemaItem,
  ];
}

/**
 * 流程表单：将 6 个内置字段固定置于表单最前；已存在的同 fieldName 项会与默认合并（保留用户改的 label 等）。
 * 任意流程表单均应带齐这些信息，由设计器在「流程表单」类型下自动调用。
 */
export function mergeWorkflowBuiltinFieldsIntoSchema(
  schema: FormDesignerSchemaItem[],
  prefix: string,
): FormDesignerSchemaItem[] {
  const defaults = createWorkflowFormDefaultSchema(prefix);
  const builtinNames = new Set(defaults.map((d) => String(d.fieldName)));

  const head: FormDesignerSchemaItem[] = [];
  for (const d of defaults) {
    const ex = schema.find((s) => String(s.fieldName) === String(d.fieldName));
    if (ex) {
      head.push({
        ...d,
        ...ex,
        label: ex.label ?? d.label,
        component: ex.component ?? d.component,
        componentProps: {
          ...(d.componentProps as object),
          ...(ex.componentProps as object),
          workflowBuiltin: (d.componentProps as { workflowBuiltin?: WorkflowBuiltinKind })?.workflowBuiltin,
        },
      } as FormDesignerSchemaItem);
    } else {
      head.push(d);
    }
  }

  const tail = schema.filter((s) => !builtinNames.has(String(s.fieldName)));
  return [...head, ...tail];
}

/**
 * 控件联动配置（通用）：当本字段变化时，请求接口并将返回结果映射填充到其他表单字段
 * 例如：选用户 → 带出工号、性别
 */
export interface FormLinkageConfig {
  enabled: boolean;
  /** 预设（员工等）或自定义 API */
  type: 'preset' | 'api';
  /** 预设标识，如 employee = 员工 Lookup */
  preset?: 'employee';
  /** 自定义 API 时使用：路径或完整 URL */
  apiUrl?: string;
  /** 请求方式 */
  method?: 'GET' | 'POST';
  /** 参数来源：表单字段名，其值作为请求参数（不填则用当前字段） */
  paramKey?: string;
  /** 接口返回的键 -> 要填充的表单字段名，如 { "code": "工号", "gender": "性别" } */
  responseMap?: Record<string, string>;
}

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
    defaultProps: {
      name: 'file',
      action: backendApi('CommonUpload/upload'),
      listType: 'picture-card',
      valueType: 'url',
      uploadDir: 'form',
      maxCount: 1,
    },
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
