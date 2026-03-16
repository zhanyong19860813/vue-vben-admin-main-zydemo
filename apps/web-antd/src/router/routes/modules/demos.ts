import type { RouteRecordRaw } from 'vue-router';

import { $t } from '#/locales';

const routes: RouteRecordRaw[] = [
  {
    meta: {
      icon: 'ic:baseline-view-in-ar',
      keepAlive: true,
      order: 1000,
      title: $t('demos.title'),
    },
    name: 'Demos',
    path: '/demos',
    children: [
      {
        meta: {
          title: $t('demos.antd'),
        },
        name: 'AntDesignDemos',
        path: '/demos/ant-design',
        component: () => import('#/views/demos/antd/index.vue'),
      },
      {
        meta: {
          icon: 'lucide:form-input',
          title: '表单设计器',
        },
        name: 'FormDesigner',
        path: '/demos/form-designer',
        component: () => import('#/views/demos/form-designer/index.vue'),
      },
      {
        meta: {
          icon: 'lucide:list',
          title: '列表设计器',
        },
        name: 'ListDesigner',
        path: '/demos/list-designer',
        component: () => import('#/views/demos/list-designer/index.vue'),
      },
      {
        meta: {
          icon: 'lucide:database',
          title: '表结构设计器',
        },
        name: 'TableBuilder',
        path: '/demos/table-builder',
        component: () => import('#/views/demos/table-builder/index.vue'),
      },
    ],
  },
];

export default routes;
