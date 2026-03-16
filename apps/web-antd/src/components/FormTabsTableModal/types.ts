import type { VxeGridProps } from '#/adapter/vxe-table';
import type { VbenFormSchema } from '#/adapter/form';

export interface TabTableItem {
  key: string;
  tab: string;
  gridOptions: VxeGridProps;
}

export interface FormTabsTableModalOptions {
  formSchema?: VbenFormSchema[];
  tabs?: TabTableItem[];
}
