import type { Component, DefineComponent } from 'vue';

import type {
  AccessModeType,
  GenerateMenuAndRoutesOptions,
  RouteRecordRaw,
} from '@vben/types';

import { defineComponent, h } from 'vue';

import {
  cloneDeep,
  generateMenus,
  generateRoutesByBackend,
  generateRoutesByFrontend,
  isFunction,
  isString,
  mapTree,
} from '@vben/utils';

/**
 * vue-router 要求：命名路由全局唯一，且子路由 name 不能与任一祖先相同。
 * 后端/合并逻辑可能仍产生父子同名，在注册前统一修正。
 */
function collectRouteNames(routes: RouteRecordRaw[]) {
  const names: string[] = [];
  const walk = (r: RouteRecordRaw) => {
    const n = r.name;
    if (n != null && typeof n !== 'symbol') {
      const s = String(n);
      if (s) names.push(s);
    }
    (r.children ?? []).forEach((c) => walk(c as RouteRecordRaw));
  };
  routes.forEach((r) => walk(r));
  return names;
}

function uniquifyRouteTree(
  route: RouteRecordRaw,
  ancestorNames: Set<string>,
  globalUsed: Set<string>,
): void {
  const rawName = route.name;
  if (rawName == null || typeof rawName === 'symbol') {
    (route.children ?? []).forEach((child) =>
      uniquifyRouteTree(child as RouteRecordRaw, ancestorNames, globalUsed),
    );
    return;
  }
  let name = String(rawName);
  if (name === '') {
    (route.children ?? []).forEach((child) =>
      uniquifyRouteTree(child as RouteRecordRaw, ancestorNames, globalUsed),
    );
    return;
  }
  if (ancestorNames.has(name) || globalUsed.has(name)) {
    let i = 1;
    let candidate = `${name}__dup${i}`;
    while (ancestorNames.has(candidate) || globalUsed.has(candidate)) {
      i++;
      candidate = `${name}__dup${i}`;
    }
    route.name = candidate;
    name = candidate;
  }
  globalUsed.add(name);
  const nextAncestors = new Set(ancestorNames);
  nextAncestors.add(name);
  (route.children ?? []).forEach((child) =>
    uniquifyRouteTree(child as RouteRecordRaw, nextAncestors, globalUsed),
  );
}

function uniquifyAccessibleRouteNames(routes: RouteRecordRaw[]) {
  const globalUsed = new Set<string>();
  routes.forEach((route) => uniquifyRouteTree(route, new Set(), globalUsed));
}

async function generateAccessible(
  mode: AccessModeType,
  options: GenerateMenuAndRoutesOptions,
) {
  const { router } = options;

  options.routes = cloneDeep(options.routes);
  // 生成路由
  const accessibleRoutes = await generateRoutes(mode, options);
  uniquifyAccessibleRouteNames(accessibleRoutes);

  /**
   * 修复：支持三级菜单，避免多层 BasicLayout 嵌套导致的闪烁/空白
   * 场景：父/子菜单节点都使用 component='LAYOUT'(映射到 BasicLayout)，深层嵌套时容易出现多层 BasicLayout。
   *
   * 策略：
   * - 如果当前节点是 BasicLayout，且它的祖先节点已经是 BasicLayout，则删除当前节点 component，
   *   - 让子路由直接渲染在最外层 BasicLayout 的 RouterView 中。
   */
  const isLayoutComponent = (comp: unknown) => {
    if (!comp) return false;
    // 后端菜单常用 component='LAYOUT'（见 apps/web-antd/src/router/access.ts 的 layoutMap）
    if (typeof comp === 'string') {
      const s = comp.trim().toLowerCase();
      return s === 'layout' || s === 'basiclayout';
    }
    // 组件/函数：尽量从 name 识别
    const name = String((comp as any)?.name ?? '').trim().toLowerCase();
    if (name) return name.includes('basiclayout');
    // 兜底：函数/对象字符串化判断
    const s = String(comp).toLowerCase();
    return s.includes('basiclayout');
  };

  const stripNestedBasicLayout = (routes: RouteRecordRaw[]) => {
    const walk = (list: RouteRecordRaw[], hasLayoutAncestor: boolean) => {
      (list ?? []).forEach((r) => {
        const isThisLayout = isLayoutComponent(r.component);
        if (isThisLayout && hasLayoutAncestor) {
          // 删除 component，但保留 children 结构，让渲染落在祖先 BasicLayout 的 RouterView
          delete (r as any).component;
        }
        if (Array.isArray(r.children) && r.children.length > 0) {
          walk(r.children as RouteRecordRaw[], hasLayoutAncestor || isThisLayout);
        }
      });
    };
    walk(routes, false);
  };

  stripNestedBasicLayout(accessibleRoutes);

  const root = router.getRoutes().find((item) => item.path === '/');
  /** 在合并动态路由前备份根路由，避免 removeRoute 后 addRoute 抛错时 Router 处于半更新状态 */
  const rootBackup = root ? cloneDeep(root) : null;

  let accessibleMenus: ReturnType<typeof generateMenus> = [];

  try {
    /**
     * 登出只 reset Pinia，不会从 Router 移除已合并的动态路由，root.children 仍保留上次登录结果。
     * 若沿用「按 name 增量替换」且 names 为快照，易与旧树叠加，触发父子同名或重复注册。
     * Root 在 core 中初始 children 为空，业务动态路由由本次菜单全量重建即可。
     */
    // 先移除本次即将添加的同名旧路由，避免 matcher 里已存在导致 addRoute 抛错
    const nextNames = collectRouteNames(accessibleRoutes);
    for (const n of nextNames) {
      try {
        if (root?.name && n === String(root.name)) continue;
        if (router.hasRoute(n)) {
          router.removeRoute(n);
        }
      } catch {
        // ignore best-effort removal
      }
    }

    if (root?.children) {
      root.children.splice(0, root.children.length);
    }

    // 动态添加到router实例内
    accessibleRoutes.forEach((route) => {
      if (root && !route.meta?.noBasicLayout) {
        // 为了兼容之前的版本用法，如果包含子路由，则将component移除，以免出现多层BasicLayout
        // 如果你的项目已经跟进了本次修改，移除了所有自定义菜单首级的BasicLayout，可以将这段if代码删除
        if (route.children && route.children.length > 0) {
          delete route.component;
        }
        root.children?.push(route);
      } else {
        router.addRoute(route);
      }
    });

    if (root) {
      if (root.name) {
        router.removeRoute(root.name);
      }
      router.addRoute(root);
    }

    // 生成菜单
    accessibleMenus = generateMenus(accessibleRoutes, options.router);
  } catch (error) {
    if (rootBackup && rootBackup.name) {
      try {
        if (router.hasRoute(rootBackup.name as string)) {
          router.removeRoute(rootBackup.name);
        }
        router.addRoute(rootBackup);
      } catch {
        // 尽力恢复根路由，避免半更新状态
      }
    }
    throw error;
  }

  return { accessibleMenus, accessibleRoutes };
}

/**
 * Generate routes
 * @param mode
 * @param options
 */
async function generateRoutes(
  mode: AccessModeType,
  options: GenerateMenuAndRoutesOptions,
) {
  const { forbiddenComponent, roles, routes } = options;

  let resultRoutes: RouteRecordRaw[] = routes;
  switch (mode) {
    case 'backend': {
      resultRoutes = await generateRoutesByBackend(options);
      break;
    }
    case 'frontend': {
      resultRoutes = await generateRoutesByFrontend(
        routes,
        roles || [],
        forbiddenComponent,
      );
      break;
    }
    case 'mixed': {
      const [frontend_resultRoutes, backend_resultRoutes] = await Promise.all([
        generateRoutesByFrontend(routes, roles || [], forbiddenComponent),
        generateRoutesByBackend(options),
      ]);

      resultRoutes = [...frontend_resultRoutes, ...backend_resultRoutes];
      break;
    }
  }

  /**
   * 调整路由树，做以下处理：
   * 1. 对未添加redirect的路由添加redirect
   * 2. 将懒加载的组件名称修改为当前路由的名称（如果启用了keep-alive的话）
   */
  resultRoutes = mapTree(resultRoutes, (route) => {
    // 重新包装component，使用与路由名称相同的name以支持keep-alive的条件缓存。
    if (
      route.meta?.keepAlive &&
      isFunction(route.component) &&
      route.name &&
      isString(route.name)
    ) {
      const originalComponent = route.component as () => Promise<{
        default: Component | DefineComponent;
      }>;
      route.component = async () => {
        const component = await originalComponent();
        if (!component.default) return component;
        return defineComponent({
          name: route.name as string,
          setup(props, { attrs, slots }) {
            return () => h(component.default, { ...props, ...attrs }, slots);
          },
        });
      };
    }

    // 如果有redirect或者没有子路由，则直接返回
    if (route.redirect || !route.children || route.children.length === 0) {
      return route;
    }
    const firstChild = route.children[0];

    // 如果子路由不是以/开头，则直接返回,这种情况需要计算全部父级的path才能得出正确的path，这里不做处理
    if (!firstChild?.path || !firstChild.path.startsWith('/')) {
      return route;
    }

    route.redirect = firstChild.path;
    return route;
  });

  return resultRoutes;
}

export { generateAccessible };
