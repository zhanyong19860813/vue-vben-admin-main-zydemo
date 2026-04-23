/**
 * 老系统 FL.WebUI（MVC）根地址，用于打开入职表单、工牌打印等仍托管在老站的页面。
 *
 * 老系统列表脚本 `FL.WebUI/Scripts/app/list/v_t_base_employee.list.js` 里「员工入职」为：
 * `mini.open({ url: "/BaseEmployee/Create", title: "人员入职" })` 后 `win.max()`（MiniUI 最大化弹窗）。
 * 「员工入职」已在新前端用原生表单 + StoneApi 写入 t_base_employee，不再依赖本文件。
 * 修改 / 转正日期 / 档案打印等仍可用 LegacyHrmIframeModal；需配置完整站点根 URL。
 *
 * 在 apps/web-antd/.env.development 中配置（无末尾斜杠），保存后重启 dev：
 * `VITE_LEGACY_HRM_ORIGIN=https://your-hrm-host`
 */
export function getLegacyHrmOrigin(): string {
  const raw = (import.meta.env.VITE_LEGACY_HRM_ORIGIN as string | undefined) ?? '';
  return String(raw).replace(/\/$/, '');
}

export function legacyHrmUrl(path: string): string {
  const origin = getLegacyHrmOrigin();
  if (!origin) return '';
  const p = path.startsWith('/') ? path : `/${path}`;
  return `${origin}${p}`;
}

/** 新标签打开（备用：弹窗被 X-Frame-Options 拦截时使用） */
export function openLegacyHrmInNewTab(path: string): boolean {
  const url = legacyHrmUrl(path);
  if (!url) return false;
  window.open(url, '_blank', 'noopener,noreferrer');
  return true;
}
