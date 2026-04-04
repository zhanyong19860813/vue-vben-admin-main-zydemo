import { message } from 'ant-design-vue';

import type { QueryTableActionContext } from '#/components/QueryTable/types';

/**
 * 数据权限配置（v_att_lst_Power）：打开「选人｜部门」弹窗
 * - 未勾选且未点中行：新增（进弹窗后再选管理员）
 * - 有勾选或当前行：编辑该管理员的权限
 * 列表 schema 需配置 actionModule: '/src/views/EntityList/dataPowerPermissionActions.ts'
 */
export default {
  async openDataPowerEditor({ gridApi }: QueryTableActionContext) {
    const grid = gridApi.grid;
    const checked = grid?.getCheckboxRecords?.() ?? [];
    const row = (checked.length ? checked[0] : grid?.getCurrentRecord?.()) as
      | Record<string, any>
      | undefined;

    if (row) {
      const managerKey = String(row.manager_id ?? row.Manager_id ?? '').trim();
      const managerName = String(row.manager_name ?? row.Manager_name ?? '').trim();
      if (!managerKey) {
        message.warning('当前行缺少管理员工号（manager_id）');
        return;
      }
      const managerKeyRaw = row.manager_id != null ? String(row.manager_id) : managerKey;
      return {
        type: 'openModal' as const,
        component: 'attendance/DataPowerPermissionEditor',
        props: {
          title: '编辑数据权限',
          width: 960,
          managerKeyRaw,
          managerKey,
          managerName: managerName || managerKey,
        },
      };
    }

    return {
      type: 'openModal' as const,
      component: 'attendance/DataPowerPermissionEditor',
      props: {
        title: '新增数据权限',
        width: 960,
        managerKeyRaw: '',
        managerKey: '',
        managerName: '',
      },
    };
  },
};
