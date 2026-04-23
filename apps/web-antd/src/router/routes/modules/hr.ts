import type { RouteRecordRaw } from 'vue-router';

import { HR_EMPLOYEE_ONBOARDING_LEAF_MENU_ID } from '#/views/hr/employee-onboarding/menuMeta';

/**
 * 人力资源 → 人事管理 → …
 * 与老系统 t_sys_function.path：@001-007 / @001-007-002 对应。
 */
const routes: RouteRecordRaw[] = [
  {
    meta: {
      icon: 'lucide:users-round',
      order: 450,
      title: '人力资源',
    },
    name: 'HR',
    path: '/hr',
    redirect: '/hr/personnel/employee-onboarding',
    children: [
      {
        meta: {
          icon: 'lucide:contact',
          title: '人事管理',
        },
        name: 'HRPersonnel',
        path: 'personnel',
        component: () => import('#/views/hr/personnel/layout.vue'),
        redirect: '/hr/personnel/employee-onboarding',
        children: [
          {
            meta: {
              icon: 'lucide:user-plus',
              keepAlive: true,
              title: '员工入职登记',
              /** 与库表菜单 meta 一致，供页面拉取 vben_v_user_role_menu_actions */
              query: { menuid: HR_EMPLOYEE_ONBOARDING_LEAF_MENU_ID },
            },
            name: 'EmployeeOnboarding',
            path: 'employee-onboarding',
            component: () => import('#/views/hr/employee-onboarding/index.vue'),
          },
        ],
      },
    ],
  },
];

export default routes;
