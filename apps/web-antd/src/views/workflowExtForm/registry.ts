import type { Component } from 'vue';
import { defineAsyncComponent } from 'vue';

type IndexLoader = () => Promise<{ default: Component }>;

const modules = import.meta.glob('./**/index.vue') as Record<string, IndexLoader>;

function pathToExtKey(path: string): string | null {
  const m = /^\.\/(.+)\/index\.vue$/.exec(path);
  return m?.[1] ?? null;
}

/** 扫描 `workflowExtForm` 下各子目录的 `index.vue`（不含本文件） */
export function listExtWorkflowForms(): { key: string; label: string }[] {
  const out: { key: string; label: string }[] = [];
  for (const path of Object.keys(modules)) {
    const key = pathToExtKey(path);
    if (!key) continue;
    out.push({ key, label: `${key}（硬编码）` });
  }
  out.sort((a, b) => a.key.localeCompare(b.key, 'zh-CN'));
  return out;
}

export function loadExtWorkflowFormLoader(key: string): IndexLoader | null {
  const k = String(key || '').trim().replace(/^\/+|\/+$/g, '');
  if (!k) return null;
  const path = `./${k}/index.vue`;
  return modules[path] ?? null;
}

export function createExtWorkflowFormComponent(key: string) {
  const loader = loadExtWorkflowFormLoader(key);
  if (!loader) return null;
  return defineAsyncComponent({
    loader,
    suspensible: false,
  });
}

export const EXT_FORM_CODE_PREFIX = '__wf_ext__:';

export function buildExtFormCode(key: string): string {
  return `${EXT_FORM_CODE_PREFIX}${String(key || '').trim()}`;
}

export function parseExtFormKeyFromFormCode(code: string): string | null {
  const c = String(code || '').trim();
  if (!c.toLowerCase().startsWith(EXT_FORM_CODE_PREFIX.toLowerCase())) return null;
  const rest = c.slice(EXT_FORM_CODE_PREFIX.length).trim();
  return rest || null;
}
