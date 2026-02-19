// components/QueryTable/types.ts
import type { VbenFormProps } from '#/adapter/form';
import type { VxeGridProps } from '#/adapter/vxe-table';

export interface QueryTableSchema<Row = any> {
  title: string;

  tableName: string;

    /** 🔥 主键字段名（默认 FID） */
  primaryKey?: string;

  /** 🔥 要删除数据时使用的实体名称  主要有些情况 列表用的是视图，删除数据则需要用到 表*/
  deleteEntityName?: string;

  form: VbenFormProps;

  grid: VxeGridProps<Row>;

  api: {
    query: string;
    delete?: string;
    export?: string;
  };
}
