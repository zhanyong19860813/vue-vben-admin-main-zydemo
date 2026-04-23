import type { RouteRecordRaw } from 'vue-router';

import { LOGIN_PATH } from '@vben/constants';
import { preferences } from '@vben/preferences';

import { $t } from '#/locales';

const BasicLayout = () => import('#/layouts/basic.vue');
const AuthPageLayout = () => import('#/layouts/auth.vue');
/** 全局404页面 */
const fallbackNotFoundRoute: RouteRecordRaw = {
  component: () => import('#/views/_core/fallback/not-found.vue'),
  meta: {
    hideInBreadcrumb: true,
    hideInMenu: true,
    hideInTab: true,
    title: '404',
  },
  name: 'FallbackNotFound',
  path: '/:path(.*)*',
};

/** 基本路由，这些路由是必须存在的 */
const coreRoutes: RouteRecordRaw[] = [
  /**
   * 根路由
   * 使用基础布局，作为所有页面的父级容器，子级就不必配置BasicLayout。
   * 此路由必须存在，且不应修改
   */
  {
    component: BasicLayout,
    meta: {
      hideInBreadcrumb: true,
      title: 'Root',
    },
    name: 'Root',
    path: '/',
    redirect: preferences.app.defaultHomePath,
    children: [],
  },
  {
    component: AuthPageLayout,
    meta: {
      hideInTab: true,
      title: 'Authentication',
    },
    name: 'Authentication',
    path: '/auth',
    redirect: LOGIN_PATH,
    children: [
      {
        name: 'Login',
        path: 'login',
        component: () => import('#/views/_core/authentication/login.vue'),
        meta: {
          title: $t('page.auth.login'),
        },
      },
      {
        name: 'CodeLogin',
        path: 'code-login',
        component: () => import('#/views/_core/authentication/code-login.vue'),
        meta: {
          title: $t('page.auth.codeLogin'),
        },
      },
      {
        name: 'QrCodeLogin',
        path: 'qrcode-login',
        component: () =>
          import('#/views/_core/authentication/qrcode-login.vue'),
        meta: {
          title: $t('page.auth.qrcodeLogin'),
        },
      },
      {
        name: 'ForgetPassword',
        path: 'forget-password',
        component: () =>
          import('#/views/_core/authentication/forget-password.vue'),
        meta: {
          title: $t('page.auth.forgetPassword'),
        },
      },
      {
        name: 'Register',
        path: 'register',
        component: () => import('#/views/_core/authentication/register.vue'),
        meta: {
          title: $t('page.auth.register'),
        },
      },
    ],
  },
  /**
   * 流程管理「预览」新页签：不走菜单权限合并，保证 router.resolve 可解析。
   */
  {
    component: BasicLayout,
    meta: {
      hideInBreadcrumb: true,
      hideInMenu: true,
      title: '流程预览',
    },
    name: 'WorkflowProcessPreviewLayout',
    path: '/workflow/process-preview',
    children: [
      {
        name: 'WorkflowProcessPreview',
        path: '',
        component: () => import('#/views/workflow/process-preview/index.vue'),
        meta: {
          title: '流程预览',
          hideInMenu: true,
        },
      },
    ],
  },
  /**
   * 流程运行台（MVP）：由流程管理页按钮新开窗口进入，不依赖菜单权限合并。
   */
  {
    component: BasicLayout,
    meta: {
      hideInBreadcrumb: true,
      hideInMenu: true,
      title: '流程运行台',
    },
    name: 'WorkflowRuntimeLayout',
    path: '/workflow/runtime',
    children: [
      {
        name: 'WorkflowRuntimeMvpCore',
        path: '',
        component: () => import('#/views/workflow/runtime/index.vue'),
        meta: {
          title: '流程运行台（MVP）',
          hideInMenu: true,
        },
      },
    ],
  },
  /**
   * 流程查看（只读）：独立页面（无 BasicLayout 壳），用于新窗口打开查看。
   */
  {
    component: () => import('#/views/workflow/runtime-viewer/index.vue'),
    meta: {
      hideInBreadcrumb: true,
      hideInMenu: true,
      hideInTab: true,
      title: '流程查看（只读）',
    },
    name: 'WorkflowRuntimeViewerCore',
    path: '/workflow/runtime-viewer',
  },
  /**
   * 流程运行台（发起/办理）：独立全屏，无 BasicLayout，与「流程查看」新开窗口体验一致。
   * query 与 /workflow/runtime 相同（processDefId、instanceId、runtimeDraftKey 等）。
   */
  {
    component: () => import('#/views/workflow/runtime/index.vue'),
    meta: {
      hideInBreadcrumb: true,
      hideInMenu: true,
      hideInTab: true,
      title: '流程运行台',
    },
    name: 'WorkflowRuntimeEmbedCore',
    path: '/workflow/runtime-embed',
  },
  /**
   * 钉钉第三方应用首页（移动端）：独立轻量页面，仅展示当前登录人基础信息。
   */
  {
    component: () => import('#/views/dingtalk/home/index.vue'),
    meta: {
      hideInBreadcrumb: true,
      hideInMenu: true,
      hideInTab: true,
      ignoreAccess: true,
      title: '钉钉首页',
    },
    name: 'DingTalkMobileHome',
    path: '/dingtalk/home',
  },
];

export { coreRoutes, fallbackNotFoundRoute };
