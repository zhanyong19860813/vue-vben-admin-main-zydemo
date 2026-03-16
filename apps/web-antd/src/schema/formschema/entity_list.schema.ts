import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

interface FormLayout {
  type: 'form';
  cols: number;
  schema: any[];
}

interface ButtonLayout {
  type: 'button';
  label: string;
  action: string;
  style?: Record<string, any>;
}

type LayoutItem = FormLayout | ButtonLayout;

/** 后端返回的字段定义 */
interface BackendField {
  field_name: string;
  label: string;
  component: string;
  component_props?: string;
  rules?: string;
  [key: string]: any;
}

/**
 * 各组件类型的默认 componentProps（参考 companyform.schema.ts）
 * 后端 component_props 为 JSON 字符串，会与默认值合并。
 * 例如 Select: {"options":[{"label":"选项A","value":"a"}],"placeholder":"请选择"}
 * TreeSelect: {"treeData":[{"title":"根","value":"root","children":[]}]}
 */
const COMPONENT_DEFAULTS: Record<string, Record<string, any>> = {
  Input: { placeholder: '请输入' },
  InputNumber: { placeholder: '请输入数字', min: 0, max: 999999 },
  InputPassword: { placeholder: '请输入密码' },
  AutoComplete: {
    options: [],
    placeholder: '请输入',
  },
  Select: {
    options: [],
    placeholder: '请选择',
  },
  RadioGroup: { options: [] },
  CheckboxGroup: { options: [] },
  DatePicker: { placeholder: '选择日期' },
  RangePicker: { placeholder: ['开始日期', '结束日期'] },
  TimePicker: { placeholder: '选择时间' },
  Switch: { checkedChildren: '开启', unCheckedChildren: '关闭' },
  Rate: {},
  Textarea: { placeholder: '请输入多行文本', rows: 3 },
  TreeSelect: { treeData: [], placeholder: '请选择' },
  Mentions: { options: [], placeholder: '@提及' },
  IconPicker: {},
  Upload: { name: 'file', action: '#', listType: 'picture-card' },
};

/** 组件名标准化（首字母大写） */
function normalizeComponentName(name: string): string {
  if (!name) return 'Input';
  const n = String(name).trim();
  return n.charAt(0).toUpperCase() + n.slice(1);
}

/** 将后端字段转换为表单 schema 项，支持各类控件 */
function buildFieldSchema(f: BackendField): any {
  const component = normalizeComponentName(f.component) || 'Input';
  const defaults = COMPONENT_DEFAULTS[component] ?? COMPONENT_DEFAULTS.Input;

  let componentProps: Record<string, any> = {};
  try {
    componentProps = JSON.parse(f.component_props || '{}');
  } catch {
    componentProps = {};
  }

  // 合并：后端配置覆盖默认值
  const mergedProps = { ...defaults, ...componentProps };

  // options 格式兼容：后端可能返回 [{value}] 或 [{label, value}]
  if (['Select', 'RadioGroup', 'CheckboxGroup', 'AutoComplete'].includes(component) && mergedProps.options) {
    mergedProps.options = (mergedProps.options || []).map((opt: any) =>
      typeof opt === 'string' ? { label: opt, value: opt } : { ...opt, label: opt.label ?? opt.value }
    );
  }

  const item: any = {
    fieldName: f.field_name,
    label: f.label,
    component,
    componentProps: mergedProps,
  };

  if (f.defaultValue !== undefined) item.defaultValue = f.defaultValue;

  // 仅支持简单校验字符串如 'required'，后端返回的 JSON 字符串会触发 "No such validator" 错误
  const rulesVal = f.rules;
  if (rulesVal && typeof rulesVal === 'string') {
    const trimmed = rulesVal.trim();
    // 排除 JSON 格式（后端可能存 {"type":"string",...}），表单库不支持
    if (trimmed && !trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      item.rules = trimmed;
    }
  }

  // Upload 需要 renderComponentContent
  if (component === 'Upload' && !item.renderComponentContent) {
    item.renderComponentContent = () => ['上传'];
  }

  return item;
}







export const getFormDemoLayoutData = async (
  FormValues: Record<string, any>, entityListId: string
): Promise<LayoutItem[]> => {

   
     console.log('获取表单布局数据，传入的FormValues.id:', FormValues.id);
  const fields = await requestClient.post<any>(
    backendApi('DynamicQueryBeta/queryforvben'),
    {
      TableName: "vben_form_schema_field",
      Page: 1,
      PageSize: 50,
      SortBy: "sort",
      SortOrder: "asc",
      SimpleWhere: { entitylistid : entityListId }
    },
    {
      headers: { 'Content-Type': 'application/json' }
    }
  );

  console.log('接口返回数据fields:', fields);

  const items = fields?.items ?? [];
  const schema = items.map((f: BackendField) => buildFieldSchema(f));
  console.log('格式化后schema:', schema);
   

    const layout: LayoutItem[] = [
    {
      type: 'form',
      cols: 4,  // 或者从接口获取配置
      schema: fillDefaultValue(schema, FormValues)
    }
  ];
   
   //console.log('最终layout:', JSON.stringify(layout));
  return layout;
}

function fillDefaultValue(schema: any[], values: any) {
  return schema.map(item => ({
    ...item,
    defaultValue: values?.[item.fieldName] ?? item.defaultValue
  }))
}
