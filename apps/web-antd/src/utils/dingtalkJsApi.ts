import type { DingH5Config } from '#/api/dingtalkAuth';

export type MaybeDingWindow = Window & {
  dd?: {
    config?: (cfg: Record<string, unknown>) => void;
    error?: (cb: (err: unknown) => void) => void;
    ready?: (cb: () => void) => void;
    runtime?: {
      permission?: {
        requestAuthCode?: (arg: {
          corpId: string;
          onSuccess?: (res: { code?: string }) => void;
          onFail?: (err: unknown) => void;
        }) => void;
      };
    };
  };
};

function safeStringify(obj: unknown): string {
  try {
    return JSON.stringify(obj);
  } catch {
    return String(obj);
  }
}

export function formatDingError(err: unknown): string {
  if (err instanceof Error) return err.message || err.toString();
  if (typeof err === 'string') return err;
  if (err && typeof err === 'object') {
    const o = err as Record<string, unknown>;
    const msg =
      (o.errorMessage as string) ||
      (o.message as string) ||
      (o.errMsg as string) ||
      '';
    const code = (o.errorCode as string | number) ?? (o.code as string | number);
    if (msg && code !== undefined) return `[${String(code)}] ${msg}`;
    if (msg) return msg;
    return safeStringify(o);
  }
  return String(err);
}

export function pickPayload<T extends Record<string, any>>(res: unknown): T | null {
  if (!res || typeof res !== 'object') return null;
  const o = res as Record<string, unknown>;
  if ('data' in o && o.data && typeof o.data === 'object') return o.data as T;
  return res as T;
}

export function looksLikeH5Config(v: unknown): v is DingH5Config {
  return Boolean(
    v &&
      typeof v === 'object' &&
      typeof (v as DingH5Config).corpId === 'string' &&
      typeof (v as DingH5Config).agentId === 'string' &&
      typeof (v as DingH5Config).signature === 'string',
  );
}

export function getDingWindow(): MaybeDingWindow {
  return window as MaybeDingWindow;
}

const DING_SDK_URLS = [
  'https://g.alicdn.com/dingding/dingtalk-jsapi/3.1.2/dingtalk.open.js',
  'https://g.alicdn.com/dingding/open-develop/1.9.0/dingtalk.js',
];

function hasDingAuthApi(): boolean {
  return Boolean(getDingWindow().dd?.runtime?.permission?.requestAuthCode);
}

function loadScriptAsync(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const existed = document.querySelector(`script[data-dd-sdk="${src}"]`);
    if (existed) {
      // 已存在脚本时，给一点时间等待其初始化 dd 对象
      window.setTimeout(() => resolve(), 120);
      return;
    }
    const script = document.createElement('script');
    script.src = src;
    script.async = true;
    script.defer = true;
    script.setAttribute('data-dd-sdk', src);
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`load script failed: ${src}`));
    document.head.append(script);
  });
}

/**
 * 尝试加载钉钉 JS SDK（适配某些 WebView 未自动注入 dd 的场景）
 */
export async function ensureDingSdkLoadedAsync(): Promise<void> {
  if (typeof window === 'undefined' || typeof document === 'undefined') return;
  if (hasDingAuthApi()) return;
  for (const url of DING_SDK_URLS) {
    try {
      await loadScriptAsync(url);
      if (hasDingAuthApi()) return;
    } catch {
      // 尝试下一个候选地址
    }
  }
}

export function isDingTalkContainer(): boolean {
  return hasDingAuthApi();
}

/** 注册 error / ready 后调用 config；ready 或 15s 超时 */
export function bindDdConfigAsync(cfg: DingH5Config): Promise<void> {
  const dd = getDingWindow().dd;
  if (!dd?.config) return Promise.reject(new Error('当前环境未检测到 dd.config（未加载 dd.js）'));

  return new Promise((resolve, reject) => {
    let settled = false;
    const timer = window.setTimeout(() => {
      if (settled) return;
      settled = true;
      reject(new Error('dd.ready 超时（15s），请检查 corpId/agentId/签名 URL 是否与当前页一致）'));
    }, 15_000);

    const done = (fn: () => void) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timer);
      fn();
    };

    dd.error?.((err: unknown) => {
      const formatted = formatDingError(err);
      done(() => reject(new Error(`dd.config 校验失败: ${formatted}`)));
    });
    dd.ready?.(() => {
      done(() => resolve());
    });

    dd.config({
      agentId: cfg.agentId,
      corpId: cfg.corpId,
      timeStamp: cfg.timeStamp,
      nonceStr: cfg.nonceStr,
      signature: cfg.signature,
      jsApiList: ['runtime.permission.requestAuthCode'],
    });
  });
}

export function requestAuthCodeAsync(corpId: string): Promise<string> {
  const dd = getDingWindow().dd;
  if (!dd?.runtime?.permission?.requestAuthCode) {
    return Promise.reject(new Error('当前环境不支持 requestAuthCode'));
  }
  return new Promise((resolve, reject) => {
    dd.runtime.permission.requestAuthCode!({
      corpId,
      onSuccess: (res) => {
        const code = (res?.code || '').trim();
        if (code) resolve(code);
        else reject(new Error('钉钉返回 code 为空'));
      },
      onFail: (err) => {
        reject(new Error(`requestAuthCode 失败: ${formatDingError(err)}`));
      },
    });
  });
}
