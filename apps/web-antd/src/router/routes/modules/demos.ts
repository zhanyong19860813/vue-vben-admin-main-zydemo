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
          /** 与顶部标签切换时保留画布/属性等编辑状态（Layout KeepAlive + tabbar cachedTabs） */
          keepAlive: true,
        },
        name: 'FormDesigner',
        path: '/demos/form-designer',
        component: () => import('#/views/demos/form-designer/index.vue'),
      },
      {
        meta: {
          icon: 'lucide:list',
          title: '列表设计器',
          keepAlive: true,
        },
        name: 'ListDesigner',
        path: '/demos/list-designer',
        component: () => import('#/views/demos/list-designer/index.vue'),
      },
      {
        meta: {
          icon: 'lucide:database',
          title: '表结构设计器',
          keepAlive: true,
        },
        name: 'TableBuilder',
        path: '/demos/table-builder',
        component: () => import('#/views/demos/table-builder/index.vue'),
      },
      {
        meta: {
          icon: 'lucide:search',
          title: 'AutoComplete 远程查询',
        },
        name: 'AutoCompleteRemoteDemo',
        path: '/demos/autocomplete-remote',
        component: () => import('#/views/demos/autocomplete-remote/index.vue'),
      },
      {
        meta: {
          icon: 'lucide:arrow-right-left',
          title: '迁移测试·人事黑名单',
        },
        name: 'MigrationTestHrmBlacklist',
        path: '/demos/migration-hrm-blacklist',
        component: () => import('#/views/migration/HRMBlacklist.vue'),
      },
      {
        meta: {
          icon: 'lucide:calendar-off',
          title: '迁移测试·假别设定',
        },
        name: 'MigrationTestHolidayCategory',
        path: '/demos/migration-holiday-category',
        component: () => import('#/views/migration/HolidayCategory.vue'),
      },
    ],
  },
  {
    meta: {
      icon: 'lucide:workflow',
      keepAlive: true,
      order: 1001,
      title: '流程引擎',
    },
    name: 'Workflow',
    path: '/workflow',
    children: [
      {
        meta: {
          icon: 'lucide:git-branch-plus',
          title: '流程引擎（静态）',
        },
        name: 'WorkflowEngineDemo',
        path: '/workflow/engine',
        component: () => import('#/views/demos/workflow-engine/index.vue'),
      },
      {
        meta: {
          icon: 'lucide:workflow',
          title: '流程设计器（静态）',
        },
        name: 'WorkflowDesignerDemo',
        path: '/workflow/designer',
        component: () => import('#/views/demos/workflow-designer/index.vue'),
      },
      {
        meta: {
          icon: 'lucide:play-circle',
          title: '发起流程',
        },
        name: 'WorkflowStart',
        path: '/workflow/start',
        component: () => import('#/views/workflow/start/index.vue'),
      },
      {
        meta: {
          icon: 'lucide:list-checks',
          title: '流程待办中心',
        },
        name: 'WorkflowTodo',
        path: '/workflow/todo',
        component: () => import('#/views/workflow/todo/index.vue'),
      },
    ],
  },
];

export default routes;
