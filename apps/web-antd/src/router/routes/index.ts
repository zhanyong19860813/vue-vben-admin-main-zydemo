import type { RouteRecordRaw } from 'vue-router';
import { mergeRouteModules, traverseTreeValues } from '@vben/utils';
import { coreRoutes, fallbackNotFoundRoute } from './core';

// 自动导入 modules 文件夹下的路由模块
const dynamicRouteFiles = import.meta.glob('./modules/**/*.ts', { eager: true });

// 取每个模块的默认导出，保证是数组
const dynamicModules = Object.values(dynamicRouteFiles)
  .map((m: any) => m.default)
  .filter(Boolean);

// 动态路由（包含 simple-table.ts、advanced-table.ts 等）
const dynamicRoutes: RouteRecordRaw[] = mergeRouteModules(dynamicModules);

// 外部路由（访问这些页面不需要 Layout）
const externalRoutes: RouteRecordRaw[] = [];
const staticRoutes: RouteRecordRaw[] = [];

// 所有路由列表，由 core、外部路由和 404 兜底组成
const routes: RouteRecordRaw[] = [
  ...coreRoutes,
  ...externalRoutes,
  fallbackNotFoundRoute,
];

// 基本路由名称列表，不需要权限校验
const coreRouteNames = traverseTreeValues(coreRoutes, (route) => route.name);

// 有权限校验的路由列表，包含动态路由和静态路由
const accessRoutes = [...dynamicRoutes, ...staticRoutes];

export { accessRoutes, coreRouteNames, routes };
