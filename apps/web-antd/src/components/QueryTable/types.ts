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
}

export interface QueryTableSchema<Row = any> {
  title: string;
  tableName: string;
  actionModule?: string; // 关联的 action 模块路径，支持相对路径和绝对路径
  primaryKey?: string;
  deleteEntityName?: string;

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
export interface QueryTableActionContext<Row = any> {
  gridApi: any;
  schema: QueryTableSchema<Row>;
}
