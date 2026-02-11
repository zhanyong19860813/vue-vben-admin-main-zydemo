// components/QueryTable/types.ts
import type { VbenFormProps } from '#/adapter/form';
import type { VxeGridProps } from '#/adapter/vxe-table';

export interface QueryTableSchema<Row = any> {
  title: string;

  tableName: string;

  form: VbenFormProps;

  grid: VxeGridProps<Row>;

  api: {
    query: string;
    delete?: string;
    export?: string;
  };
}
