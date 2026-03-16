// components/QueryTable/types.ts
import type { VbenFormProps } from '#/adapter/form';
import type { VxeGridProps } from '#/adapter/vxe-table';

/**
 * 🔘 内置 Action 名
 */
export type BuiltinAction =
  | 'add'
  | 'reload'
  | 'deleteSelected'
  | 'export';

export type ToolbarActionName = BuiltinAction | string;

/**
 * 🔘 Toolbar 按钮定义
 */
export interface QueryTableToolbarAction {
  key: string;
  label: string;
  type?: 'primary' | 'default' | 'dashed' | 'link' | 'text';
  action: ToolbarActionName;
  confirm?: string;
  /** 表单设计器编码，按 code 查 vben_form_desinger 打开表单弹窗 */
  form_code?: string;
  /** 是否需勾选行（编辑场景传 selectedRows[0] 作为 initialValues） */
  requiresSelection?: boolean;
}

export interface QueryTableSchema<Row = any> {
  title: string;
  tableName: string;
  actionModule?: string; // 关联的 action 模块路径，支持相对路径和绝对路径
  primaryKey?: string;
  deleteEntityName?: string;
  saveEntityName?: string;// 用于实体保存  的时候的名字

  toolbar?: {
    actions?: QueryTableToolbarAction[];
    mode?: 'schema' | 'slot' | 'mixed';
  };

  form: VbenFormProps;
  grid: VxeGridProps<Row>;

  api: {
    query: string;
    delete?: string;
    export?: string;
  };
}

/**
 * 🔥 Action 执行上下文（运行期）
 */
// export interface QueryTableActionContext<Row = any> {
//   gridApi: any;
//   schema: QueryTableSchema<Row>;
// }


export interface QueryTableActionContext<Row = any> {
  gridApi: any;
  schema: QueryTableSchema<Row>;
}

/** Action 返回：打开表单+页签+表格弹窗（用于 action 文件 return） */
export interface OpenFormTabsTableModalResult {
  type: 'openFormTabsTableModal';
  title?: string;
  formSchema: any[];
  tabs: import('#/components/FormTabsTableModal/types').TabTableItem[];
  width?: number;
}

/** Action 返回：打开表单设计器表单弹窗 */
export interface OpenFormFromDesignerResult {
  type: 'openFormFromDesigner';
  formCode: string;
  initialValues?: Record<string, any>;
  title?: string;
}

/** Action 返回值类型 */
export type QueryTableActionResult =
  | { type: 'openModal'; component: string; props?: Record<string, any> }
  | OpenFormTabsTableModalResult
  | OpenFormFromDesignerResult
  | void;
