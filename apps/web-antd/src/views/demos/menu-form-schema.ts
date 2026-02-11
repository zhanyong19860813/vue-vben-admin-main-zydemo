import type { FormSchema } from '@/components/schema-form/form-types';

export const menuFormSchema: FormSchema = {
  fields: [
    {
      field: 'name',
      label: '菜单名称',
      component: 'Input',
      required: true,
    },
    {
      field: 'path',
      label: '路由路径',
      component: 'Input',
    },
    {
      field: 'order',
      label: '排序',
      component: 'InputNumber',
      defaultValue: 0,
    },
    {
      field: 'status',
      label: '是否启用',
      component: 'Switch',
      defaultValue: true,
    },
  ],
};
