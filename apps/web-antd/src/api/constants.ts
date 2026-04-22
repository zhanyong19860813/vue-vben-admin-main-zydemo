/**
 * 后端 API 基础地址（StoneApi）
 * 通过 VITE_GLOB_BACKEND_URL 配置，默认 http://127.0.0.1:5155
 */
const raw = import.meta.env.VITE_GLOB_BACKEND_URL as string | undefined;
export const BACKEND_API_BASE = (raw || 'http://127.0.0.1:5155').replace(/\/$/, '');

/** 拼接后端 API 完整路径，如 backendApi('DynamicQueryBeta/queryforvben') */
export function backendApi(path: string): string {
  const p = path.startsWith('/') ? path.slice(1) : path;
  const base = resolveBackendApiBase();
  if (base.toLowerCase().endsWith('/api')) {
    return `${base}/${p}`;
  }
  return `${base}/api/${p}`;
}

function resolveBackendApiBase(): string {
  const base = BACKEND_API_BASE;
  if (/^https?:\/\//i.test(base)) {
    return base;
  }

  if (typeof window !== 'undefined' && window.location?.origin) {
    return new URL(base.startsWith('/') ? base : `/${base}`, window.location.origin)
      .toString()
      .replace(/\/$/, '');
  }

  return base;
}
