import type {
  ComponentRecordType,
  GenerateMenuAndRoutesOptions,
} from '@vben/types';

import { generateAccessible } from '@vben/access';
import { preferences } from '@vben/preferences';

import { message } from 'ant-design-vue';

import { getAllMenusApi } from '#/api';
import { BasicLayout, IFrameView } from '#/layouts';
import { $t } from '#/locales';

const forbiddenComponent = () => import('#/views/_core/fallback/forbidden.vue');

function safeRouteName(raw: unknown, fallback: string): string {
  const s = String(raw ?? '').trim();
  return s || fallback;
}

function sanitizeRouteNameToken(s: string): string {
  return String(s ?? '').replace(/[^a-zA-Z0-9_]/g, '_');
}

/**
 * 与 menuid 组合成路由 name，避免「父子节点被后端写成同一 menuid」时名称相同，
 * 触发 vue-router：nested route cannot use the same name as an ancestor。
 */
function pathTokenForRouteName(rawPath: string): string {
  const p = String(rawPath ?? '').trim();
  if (p === '' || p === '/') {
    return 'root';
  }
  const stripped = p.replace(/^\/+/, '').replace(/\//g, '_');
  const token = sanitizeRouteNameToken(stripped);
  return token || 'root';
}

function buildMenuRouteBaseName(
  node: any,
  index: number,
  title: string,
  rawPath: string,
): string {
  const q = node?.meta?.query;
  const menuIdRaw = q?.menuid ?? q?.menuId;
  const menuIdStr = String(menuIdRaw ?? '').trim();
  const pathToken = pathTokenForRouteName(rawPath);
  if (menuIdStr) {
    return `menu_${sanitizeRouteNameToken(menuIdStr)}__p${pathToken}`;
  }
  const pathPart = rawPath.replace(/\W/g, '_') || String(index);
  return `menu_${safeRouteName(node.name, `${title}_${pathPart}`)}__p${pathToken}`;
}

interface RouteNameConflictLog {
  source: 'menu' | 'routes';
  path: string;
  title: string;
  originalName: string;
  finalName: string;
  reason: 'duplicate' | 'same-as-ancestor' | 'empty-name';
}

/**
 * 兜底修复后端菜单的路由 name 冲突：
 * - 全局 name 必须唯一
 * - 子路由 name 不能与任一祖先相同（vue-router 会直接抛错）
 */
function normalizeMenuRouteNames(
  list: any[],
  source: 'menu' | 'routes',
  logs: RouteNameConflictLog[],
): any[] {
  const used = new Set<string>();

  const walk = (nodes: any[], ancestors: string[], depth: number): any[] => {
    return (nodes ?? []).map((node: any, index: number) => {
      const next = { ...(node ?? {}) };
      const title = next?.meta?.title ?? next?.title ?? '';
      const rawPath = String(next?.path ?? '');
      const path = rawPath.replace(/[^\w-]/g, '_');
      const originalName = String(next?.name ?? '').trim();
      const base =
        source === 'menu'
          ? buildMenuRouteBaseName(next, index, String(title), rawPath)
          : safeRouteName(next?.name, `${String(title || 'route')}_${path || index}`);
      if (!originalName) {
        logs.push({
          source,
          path: rawPath || '/',
          title: String(title || ''),
          originalName: '(empty)',
          finalName: base,
          reason: 'empty-name',
        });
      }

      let candidate = base;
      let seq = 1;
      while (used.has(candidate) || ancestors.includes(candidate)) {
        logs.push({
          source,
          path: rawPath || '/',
          title: String(title || ''),
          originalName: base,
          finalName: `${base}_${seq}`,
          reason: ancestors.includes(candidate) ? 'same-as-ancestor' : 'duplicate',
        });
        candidate = `${base}_${seq++}`;
      }
      next.name = candidate;
      used.add(candidate);

      if (
        source === 'menu' &&
        Array.isArray(next.children) &&
        next.children.length > 0 &&
        String(next.path) === '/'
      ) {
        next.path = '';
      }

      if (Array.isArray(next.children) && next.children.length) {
        next.children = walk(next.children, [...ancestors, candidate], depth + 1);
      }
      return next;
    });
  };

  return walk(list ?? [], [], 0);
}

async function generateAccess(options: GenerateMenuAndRoutesOptions) {
  const pageMap: ComponentRecordType = import.meta.glob('../views/**/*.vue');
  const conflictLogs: RouteNameConflictLog[] = [];

  const layoutMap: ComponentRecordType = {
    BasicLayout,
    IFrameView,
    /** 后台 vben_menus_new 目录节点常用 component = LAYOUT，需映射到实际布局 */
    LAYOUT: BasicLayout,
  };

  const normalizedRoutes = normalizeMenuRouteNames((options?.routes as any[]) ?? [], 'routes', conflictLogs);

  return await generateAccessible(preferences.app.accessMode, {
    ...options,
    routes: normalizedRoutes as any,
    fetchMenuListAsync: async () => {
      message.loading({
        content: `${$t('common.loadingMenu')}...`,
        duration: 1.5,
      });
      const rawMenus = await getAllMenusApi();
      const normalizedMenus = normalizeMenuRouteNames(rawMenus as any[], 'menu', conflictLogs);
      if (conflictLogs.length > 0) {
        console.group('[router-access] Route name normalization logs');
        conflictLogs.forEach((x, i) => {
          console.warn(
            `${i + 1}. [${x.source}] path=${x.path} title=${x.title} name=${x.originalName} -> ${x.finalName} (${x.reason})`,
          );
        });
        console.groupEnd();
      }
      return normalizedMenus;
    },
    // 可以指定没有权限跳转403页面
    forbiddenComponent,
    // 如果 route.meta.menuVisibleWithForbidden = true
    layoutMap,
    pageMap,
  });
}

export { generateAccess };
