/**
 * 通用组件共同的使用的基础组件，原先放在 adapter/form 内部，限制了使用范围，这里提取出来，方便其他地方使用
 * 可用于 vben-form、vben-modal、vben-drawer 等组件使用,
 */

import type {
  UploadChangeParam,
  UploadFile,
  UploadProps,
} from 'ant-design-vue';

import type { Component, Ref } from 'vue';

import type { BaseFormComponentType } from '@vben/common-ui';
import type { Recordable } from '@vben/types';

import {
  Fragment,
  defineAsyncComponent,
  defineComponent,
  h,
  nextTick,
  ref,
  render,
  unref,
  watch,
} from 'vue';

import { ApiComponent, globalShareState, IconPicker } from '@vben/common-ui';
import { IconifyIcon } from '@vben/icons';
import { $t } from '@vben/locales';
import { isEmpty } from '@vben/utils';
import { useAccessStore } from '@vben/stores';

import { Modal, notification } from 'ant-design-vue';
import { BACKEND_API_BASE, backendApi } from '#/api/constants';

const AutoComplete = defineAsyncComponent(
  () => import('ant-design-vue/es/auto-complete'),
);
const Button = defineAsyncComponent(() => import('ant-design-vue/es/button'));
const Checkbox = defineAsyncComponent(
  () => import('ant-design-vue/es/checkbox'),
);
const CheckboxGroup = defineAsyncComponent(() =>
  import('ant-design-vue/es/checkbox').then((res) => res.CheckboxGroup),
);
const DatePicker = defineAsyncComponent(
  () => import('ant-design-vue/es/date-picker'),
);
const Divider = defineAsyncComponent(() => import('ant-design-vue/es/divider'));
const Input = defineAsyncComponent(() => import('ant-design-vue/es/input'));
const InputNumber = defineAsyncComponent(
  () => import('ant-design-vue/es/input-number'),
);
const InputPassword = defineAsyncComponent(() =>
  import('ant-design-vue/es/input').then((res) => res.InputPassword),
);
const Mentions = defineAsyncComponent(
  () => import('ant-design-vue/es/mentions'),
);
const Radio = defineAsyncComponent(() => import('ant-design-vue/es/radio'));
const RadioGroup = defineAsyncComponent(() =>
  import('ant-design-vue/es/radio').then((res) => res.RadioGroup),
);
const RangePicker = defineAsyncComponent(() =>
  import('ant-design-vue/es/date-picker').then((res) => res.RangePicker),
);
const Rate = defineAsyncComponent(() => import('ant-design-vue/es/rate'));
const Select = defineAsyncComponent(() => import('ant-design-vue/es/select'));
const Space = defineAsyncComponent(() => import('ant-design-vue/es/space'));
const Switch = defineAsyncComponent(() => import('ant-design-vue/es/switch'));
const Textarea = defineAsyncComponent(() =>
  import('ant-design-vue/es/input').then((res) => res.Textarea),
);
const TimePicker = defineAsyncComponent(
  () => import('ant-design-vue/es/time-picker'),
);
const TreeSelect = defineAsyncComponent(
  () => import('ant-design-vue/es/tree-select'),
);
const Cascader = defineAsyncComponent(
  () => import('ant-design-vue/es/cascader'),
);
const Upload = defineAsyncComponent(() => import('ant-design-vue/es/upload'));
const Tooltip = defineAsyncComponent(() => import('ant-design-vue/es/tooltip'));
const Image = defineAsyncComponent(() => import('ant-design-vue/es/image'));
const PreviewGroup = defineAsyncComponent(() =>
  import('ant-design-vue/es/image').then((res) => res.ImagePreviewGroup),
);

const withDefaultPlaceholder = <T extends Component>(
  component: T,
  type: 'input' | 'select',
  componentProps: Recordable<any> = {},
) => {
  return defineComponent({
    name: component.name,
    inheritAttrs: false,
    setup: (props: any, { attrs, expose, slots }) => {
      const placeholder =
        props?.placeholder ||
        attrs?.placeholder ||
        $t(`ui.placeholder.${type}`);
      // 透传组件暴露的方法
      const innerRef = ref();
      expose(
        new Proxy(
          {},
          {
            get: (_target, key) => innerRef.value?.[key],
            has: (_target, key) => key in (innerRef.value || {}),
          },
        ),
      );
      return () =>
        h(
          component,
          { ...componentProps, placeholder, ...props, ...attrs, ref: innerRef },
          slots,
        );
    },
  });
};

/** 快照里可能是相对路径 /uploads/...，在独立前端域名下需拼到 StoneApi 根地址才能打开 */
/** 开启后每个 Upload 下方显示表单绑定值与内部 fileList，便于排查「闪一下就没」 */
const UPLOAD_DEBUG_LS_KEY = 'vben-wf-upload-debug';

function isUploadDebugEnabled(): boolean {
  try {
    if (typeof window === 'undefined') return false;
    if (localStorage.getItem(UPLOAD_DEBUG_LS_KEY) === '0') return false;
    if (localStorage.getItem(UPLOAD_DEBUG_LS_KEY) === '1') return true;
    if (sessionStorage.getItem(UPLOAD_DEBUG_LS_KEY) === '1') return true;
    const q = new URLSearchParams(window.location.search).get('uploadDebug');
    if (q === '1' || q === 'true') return true;
    /** 开发环境默认打开，便于联调；生产需显式 localStorage=1 或 ?uploadDebug=1 */
    if (import.meta.env?.DEV) return true;
  } catch {
    /* ignore */
  }
  return false;
}

function resolveUploadDownloadHref(href: string): string {
  const u = String(href || '').trim();
  if (!u) return u;
  if (/^https?:\/\//i.test(u)) return u;
  if (u.startsWith('//') && typeof window !== 'undefined') {
    return `${window.location.protocol}${u}`;
  }
  if (u.startsWith('/')) {
    const base = String(BACKEND_API_BASE || '').replace(/\/$/, '');
    return base ? `${base}${u}` : u;
  }
  return u;
}

/** 拉取已上传文件（与下载共用鉴权逻辑） */
async function fetchUploadBlobResponse(
  rawUrl: string,
  accessToken: string | null | undefined,
): Promise<Response> {
  const url = resolveUploadDownloadHref(rawUrl);
  const tryFetch = async (withAuth: boolean) => {
    const headers: Record<string, string> = {};
    const t = String(accessToken || '').trim();
    if (withAuth && t) headers.Authorization = `Bearer ${t}`;
    return fetch(url, { method: 'GET', headers });
  };
  let res = await tryFetch(true);
  if (res.status === 401) {
    res = await tryFetch(false);
  }
  return res;
}

/** 跨域时 <a download> 往往无效，用 Blob 触发保存；字节与服务器一致，本地用 UTF-8 打开即可避免「预览乱码」 */
async function downloadFileAsBlob(
  rawUrl: string,
  filenameHint: string,
  accessToken: string | null | undefined,
): Promise<void> {
  const url = resolveUploadDownloadHref(rawUrl);
  const fallbackName =
    filenameHint.replace(/[/\\?*:|"<>]/g, '_').trim() ||
    decodeURIComponent(String(url.split('/').pop() || '').split('?')[0] || '') ||
    'download';
  const res = await fetchUploadBlobResponse(rawUrl, accessToken);
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  const blob = await res.blob();
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = fallbackName;
  a.rel = 'noopener';
  a.style.display = 'none';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(a.href);
}

function isUploadImageFile(file: UploadFile): boolean {
  const imageExtensions = new Set(['bmp', 'gif', 'jpeg', 'jpg', 'png', 'webp']);
  if (file.url) {
    const ext = file.url?.split('.').pop()?.toLowerCase();
    return ext ? imageExtensions.has(ext) : false;
  }
  if (!file.type) {
    const ext = file.name?.split('.').pop()?.toLowerCase();
    return ext ? imageExtensions.has(ext) : false;
  }
  return file.type.startsWith('image/');
}

type OnlinePreviewKind = 'image' | 'pdf' | 'text' | 'video' | 'audio' | 'unsupported';

const TEXT_PREVIEW_MAX_BYTES = 1.5 * 1024 * 1024;

function detectOnlinePreviewKind(file: UploadFile): OnlinePreviewKind {
  if (isUploadImageFile(file)) return 'image';
  const name = String(file.name || '');
  const fromUrl = String(file.url || '');
  const rawExt = name.includes('.') ? name.split('.').pop() : fromUrl.split('.').pop();
  const ext = String(rawExt || '')
    .toLowerCase()
    .split('?')[0]
    .trim();

  if (ext === 'pdf') return 'pdf';
  if (['mp4', 'webm', 'mov', 'm4v'].includes(ext)) return 'video';
  if (['mp3', 'wav', 'm4a', 'aac', 'flac'].includes(ext)) return 'audio';
  if (ext === 'ogg') return 'video';

  const textLike = new Set([
    'txt',
    'md',
    'json',
    'csv',
    'xml',
    'log',
    'ts',
    'tsx',
    'js',
    'jsx',
    'vue',
    'css',
    'scss',
    'less',
    'html',
    'htm',
    'yaml',
    'yml',
    'properties',
    'env',
    'sh',
    'bat',
    'cmd',
    'sql',
    'http',
    'ini',
    'conf',
  ]);
  if (textLike.has(ext)) return 'text';

  return 'unsupported';
}

/** 悬停上传区域时提示在线预览能力（与 detectOnlinePreviewKind 一致） */
function renderUploadPreviewFormatTooltipTitle() {
  return h(
    'div',
    {
      class:
        'text-left text-xs leading-relaxed max-w-[340px] space-y-2 text-white [&_span]:text-white',
    },
    [
      h('div', [
        h('span', { class: 'font-medium text-white' }, '支持在线预览：'),
        h(
          'span',
          { class: 'text-white/95' },
          ' 图片（jpg/png/gif/webp/bmp 等）、PDF、文本与代码（txt、md、json、csv、xml、html、css、js/ts/vue 等）、音视频（mp4/webm/mov、mp3/wav 等）。',
        ),
      ]),
      h('div', [
        h('span', { class: 'font-medium text-white' }, '不支持在线预览：'),
        h(
          'span',
          { class: 'text-white/95' },
          ' Word / Excel / PowerPoint、压缩包（zip/rar/7z 等）等，请使用「下载」后在本地打开。',
        ),
      ]),
    ],
  );
}

const uploadPreviewTooltipProps = {
  placement: 'topLeft' as const,
  /** 与 Ant Design 深色气泡一致，保证白字对比度 */
  overlayInnerStyle: {
    maxWidth: '400px',
    color: '#ffffff',
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
  },
  mouseEnterDelay: 0.35,
};

/** 列表：预览 + 下载；预览走在线 Modal（支持类型见 detectOnlinePreviewKind） */
function mergeUploadShowUploadList(componentProps: Record<string, any>) {
  const sul = componentProps?.showUploadList;
  if (sul === false) return false;
  const base =
    typeof sul === 'object' && sul !== null && !Array.isArray(sul) ? { ...sul } : {};
  return {
    ...base,
    showPreviewIcon: base.showPreviewIcon !== false,
    showDownloadIcon: base.showDownloadIcon !== false,
    showRemoveIcon: base.showRemoveIcon !== false,
  };
}

const withPreviewUpload = () => {
  return defineComponent({
    name: Upload.name,
    props: {
      fileList: { type: [Array, String, Object] as unknown as any, default: undefined },
      modelValue: { type: [Array, String, Object] as unknown as any, default: undefined },
      value: { type: [Array, String, Object] as unknown as any, default: undefined },
    },
    emits: ['change', 'update:fileList', 'update:modelValue'],
    setup: (
      props: any,
      { attrs, slots, emit }: { attrs: any; emit: any; slots: any },
    ) => {
      const previewVisible = ref<boolean>(false);

      /**
       * VbenForm 对 Upload 使用 v-model:fileList，绑定会落在 setup 的 props 上；
       * 未声明 props 时它们不会进入 attrs，仅 watch attrs 会导致回填/只读展示永远为空。
       */
      function mergedUploadAttrs(): Record<string, any> {
        return { ...(props as Record<string, any>), ...(attrs as Record<string, any>) };
      }

      function resolveUploadPlaceholder(): string {
        const m = mergedUploadAttrs();
        const raw = String(m?.placeholder ?? '').trim();
        if (raw) return raw;
        const t = String($t(`ui.placeholder.upload`) ?? '').trim();
        if (t && !/^ui\.placeholder\.upload$/i.test(t) && !/^placeholder\.upload$/i.test(t)) return t;
        return '上传';
      }

      const accessStore = useAccessStore();

      const extractUrlFromFile = (f: UploadFile): string => {
        if (typeof f.url === 'string' && f.url.trim()) return f.url.trim();
        const resp = (f as any)?.response;
        const url =
          resp?.data?.url ??
          resp?.data?.relativeUrl ??
          resp?.url ??
          resp?.relativeUrl ??
          '';
        return String(url || '').trim();
      };

      /** 主表快照可能是字符串 URL，也可能是 Ant Upload 文件对象或后端 upload 响应形状 */
      const extractUrlFromStoredPiece = (x: any): string => {
        if (x == null) return '';
        if (typeof x === 'string') return x.trim();
        if (typeof x === 'object') {
          const o = x as Record<string, any>;
          const direct =
            o.url ??
            o.relativeUrl ??
            o.relative_url ??
            o.thumbUrl ??
            o.response?.data?.url ??
            o.response?.data?.relativeUrl ??
            o.response?.url;
          if (typeof direct === 'string' && direct.trim()) return direct.trim();
        }
        return '';
      };

      const pickDisplayNameFromStoredPiece = (x: any, url: string, idx: number): string => {
        if (x && typeof x === 'object') {
          const o = x as Record<string, any>;
          const n =
            o.originalName ??
            o.original_name ??
            o.name ??
            o.fileName ??
            o.file_name ??
            o.filename;
          if (typeof n === 'string' && n.trim()) return n.trim();
        }
        if (url) return url.split('/').pop() || `file_${idx + 1}`;
        return `file_${idx + 1}`;
      };

      const toUploadFileListFromValue = (val: any): UploadProps['fileList'] => {
        if (val == null || val === '') return [];
        if (Array.isArray(val)) {
          if (!val.length) return [];
          if (typeof val[0] === 'object' && val[0] !== null && !Array.isArray(val[0])) {
            const out: UploadFile[] = [];
            val.forEach((x: any, idx: number) => {
              let url = extractUrlFromStoredPiece(x);
              if (!url && x && typeof x === 'object') url = extractUrlFromFile(x as UploadFile);
              if (!url) return;
              const name = pickDisplayNameFromStoredPiece(x, url, idx);
              out.push({
                uid: String((x as any)?.uid ?? `u_${idx}_${Date.now()}`),
                name,
                status: 'done',
                url,
              } as UploadFile);
            });
            return out;
          }
          return val
            .map((x: any, idx: number) => {
              const url = extractUrlFromStoredPiece(x);
              if (!url) return null;
              const name = pickDisplayNameFromStoredPiece(x, url, idx);
              return {
                uid: `u_${idx}_${Date.now()}`,
                name,
                status: 'done' as const,
                url,
              };
            })
            .filter((x): x is NonNullable<typeof x> => !!x);
        }
        if (typeof val === 'object' && val !== null && !Array.isArray(val)) {
          const url = extractUrlFromStoredPiece(val);
          if (!url) return [];
          const name = pickDisplayNameFromStoredPiece(val, url, 0);
          return [
            {
              uid: String((val as any)?.uid ?? `u_0_${Date.now()}`),
              name,
              status: 'done' as const,
              url,
            },
          ];
        }
        const url = String(val).trim();
        if (!url) return [];
        const name = url.split('/').pop() || 'file_1';
        return [{ uid: `u_0_${Date.now()}`, name, status: 'done' as const, url }];
      };

      function pickIncomingUploadValue(a: Record<string, any>): unknown {
        const fl = a?.fileList ?? a?.['file-list'];
        if (fl !== undefined && fl !== null && !(Array.isArray(fl) && fl.length === 0)) return fl;
        const mv = a?.modelValue;
        if (mv !== undefined && mv !== null && mv !== '') return mv;
        const v = a?.value;
        if (v !== undefined && v !== null && v !== '') return v;
        return undefined;
      }

      const listType =
        mergedUploadAttrs().listType || mergedUploadAttrs()['list-type'] || 'text';

      const fileList = ref<UploadProps['fileList']>(
        toUploadFileListFromValue(pickIncomingUploadValue(mergedUploadAttrs())) || [],
      );

      const handleChange = async (event: UploadChangeParam) => {
        fileList.value = (event.fileList || []).map((f) => {
          const next = { ...f } as UploadFile;
          const url = extractUrlFromFile(next);
          if (url) next.url = url;
          return next;
        });
        emit('change', event);
        const m = mergedUploadAttrs();
        const valueType = String(m.valueType || m['value-type'] || 'url');
        if (valueType === 'fileList') {
          const v = fileList.value?.length ? fileList.value : undefined;
          emit('update:fileList', v);
          emit('update:modelValue', v);
          return;
        }
        const urls = (fileList.value || [])
          .map((f) => extractUrlFromFile(f))
          .filter(Boolean);
        if (valueType === 'url-array') {
          const v = urls.length ? urls : undefined;
          emit('update:fileList', v);
          emit('update:modelValue', v);
          return;
        }
        const v = urls[0] || undefined;
        emit('update:fileList', v);
        emit('update:modelValue', v);
      };

      async function handleDownloadFile(file: UploadFile) {
        const url = extractUrlFromFile(file);
        if (!url) {
          notification.warning({ message: '无法下载', description: '没有可用的文件地址' });
          return;
        }
        try {
          await downloadFileAsBlob(
            url,
            String(file.name || '').trim() || url.split('/').pop() || 'file',
            accessStore.accessToken,
          );
        } catch (e) {
          notification.error({
            message: '下载失败',
            description: String((e as Error)?.message || e),
          });
          window.open(resolveUploadDownloadHref(url), '_blank', 'noopener,noreferrer');
        }
      }

      /** 在线预览：图片 / PDF / 文本 / 音视频；其余类型提示下载 */
      async function openOnlinePreview(file: UploadFile) {
        const raw = extractUrlFromFile(file);
        if (!raw) {
          notification.warning({ message: '无法预览', description: '没有可用的文件地址' });
          return;
        }
        const kind = detectOnlinePreviewKind(file);
        const title =
          String(file.name || '').trim() || raw.split('/').pop()?.split('?')[0] || '文件';

        if (kind === 'image') {
          previewVisible.value = true;
          await previewImage(file, previewVisible, fileList);
          return;
        }

        if (kind === 'unsupported') {
          Modal.confirm({
            title: '暂不支持在线预览',
            icon: null,
            content:
              'Word / Excel / 压缩包等需在本地用对应软件打开。可点击下方按钮下载文件。',
            okText: '下载',
            cancelText: '关闭',
            onOk: () => handleDownloadFile(file),
          });
          return;
        }

        try {
          const res = await fetchUploadBlobResponse(raw, accessStore.accessToken);
          if (!res.ok) {
            throw new Error(`HTTP ${res.status}`);
          }
          const blob = await res.blob();

          if (kind === 'text' && blob.size > TEXT_PREVIEW_MAX_BYTES) {
            Modal.confirm({
              title: '文件过大',
              icon: null,
              content: `超过 ${(TEXT_PREVIEW_MAX_BYTES / 1024 / 1024).toFixed(1)}MB 的文本无法在页面内流畅预览，请下载后查看。`,
              okText: '下载',
              cancelText: '关闭',
              onOk: () => handleDownloadFile(file),
            });
            return;
          }

          if (kind === 'pdf') {
            const objUrl = URL.createObjectURL(blob);
            Modal.confirm({
              title: `在线预览 · ${title}`,
              icon: null,
              width: 'min(960px, 96vw)',
              style: { top: '24px' } as Record<string, string>,
              maskClosable: true,
              footer: null,
              afterClose: () => URL.revokeObjectURL(objUrl),
              content: () =>
                h('div', { class: 'w-full', style: { height: '70vh' } }, [
                  h('iframe', {
                    src: objUrl,
                    class: 'h-full w-full rounded border border-border',
                    title,
                  }),
                ]),
            });
            return;
          }

          if (kind === 'text') {
            const text = await blob.text();
            Modal.confirm({
              title: `在线预览 · ${title}`,
              icon: null,
              width: 'min(880px, 96vw)',
              maskClosable: true,
              footer: null,
              content: () =>
                h(
                  'pre',
                  {
                    class:
                      'max-h-[65vh] overflow-auto rounded border border-border bg-muted/40 p-3 text-xs leading-relaxed whitespace-pre-wrap break-words font-mono text-foreground',
                  },
                  text,
                ),
            });
            return;
          }

          if (kind === 'video') {
            const objUrl = URL.createObjectURL(blob);
            Modal.confirm({
              title: `在线预览 · ${title}`,
              icon: null,
              width: 'min(900px, 96vw)',
              maskClosable: true,
              footer: null,
              afterClose: () => URL.revokeObjectURL(objUrl),
              content: () =>
                h('div', { class: 'flex justify-center p-2' }, [
                  h('video', {
                    src: objUrl,
                    controls: true,
                    class: 'max-h-[65vh] max-w-full rounded',
                  }),
                ]),
            });
            return;
          }

          if (kind === 'audio') {
            const objUrl = URL.createObjectURL(blob);
            Modal.confirm({
              title: `在线预览 · ${title}`,
              icon: null,
              width: 520,
              maskClosable: true,
              footer: null,
              afterClose: () => URL.revokeObjectURL(objUrl),
              content: () =>
                h('div', { class: 'py-3' }, [
                  h('audio', { src: objUrl, controls: true, class: 'w-full' }),
                ]),
            });
          }
        } catch (e) {
          notification.error({
            message: '预览失败',
            description: String((e as Error)?.message || e),
          });
        }
      }

      const handlePreview = async (file: UploadFile) => {
        await openOnlinePreview(file);
      };

      const renderUploadButton = (): any => {
        const m = mergedUploadAttrs();
        const isDisabled = m.disabled || m.readOnly || m.readonly;

        // 如果禁用，不渲染上传按钮
        if (isDisabled) {
          return null;
        }

        // 否则渲染默认上传按钮
        return isEmpty(slots)
          ? createDefaultSlotsWithUpload(listType, resolveUploadPlaceholder())
          : slots;
      };

      const isReadOnlyView = () => {
        const m = mergedUploadAttrs();
        return !!(m.disabled || m.readOnly || m.readonly);
      };

      /**
       * 与 vee-validate 同步时，父级可能短暂传入 undefined，若此处立刻把 fileList 置空，
       * 会覆盖本地上传中/刚上传完成的列表，表现为「点一下闪一下就没了」。
       */
      watch(
        () => pickIncomingUploadValue(mergedUploadAttrs()),
        (incoming) => {
          const next = toUploadFileListFromValue(incoming);
          const cur = fileList.value || [];

          if (cur.some((f) => f.status === 'uploading' || f.status === 'error')) {
            if (incoming === undefined || incoming === null) {
              return;
            }
          }

          if (
            (incoming === undefined || incoming === null) &&
            cur.some((f) => f.status === 'done' && extractUrlFromFile(f as UploadFile))
          ) {
            void nextTick(() => {
              const again = pickIncomingUploadValue(mergedUploadAttrs());
              if (again !== undefined && again !== null) {
                fileList.value = toUploadFileListFromValue(again);
                return;
              }
              const still = fileList.value || [];
              if (!still.some((x) => x.status === 'uploading')) {
                fileList.value = next;
              }
            });
            return;
          }

          fileList.value = next;
        },
        { flush: 'post', immediate: true, deep: true },
      );

      function renderUploadDebugPanel() {
        if (!isUploadDebugEnabled()) return null;
        const incoming = pickIncomingUploadValue(mergedUploadAttrs());
        const list = (fileList.value || []) as UploadFile[];
        const payload = {
          tip: '关闭：localStorage.removeItem("vben-wf-upload-debug") 或去掉 ?uploadDebug=1',
          incomingPreview:
            typeof incoming === 'object'
              ? incoming
              : incoming === undefined
                ? '(undefined)'
                : incoming,
          internalFileList: list.map((f) => ({
            uid: f.uid,
            name: f.name,
            status: f.status,
            url: extractUrlFromFile(f),
          })),
          readOnly: isReadOnlyView(),
          valueType: mergedUploadAttrs().valueType ?? mergedUploadAttrs()['value-type'],
        };
        return h(
          'pre',
          {
            class:
              'mt-1 max-w-full overflow-x-auto rounded border border-dashed border-amber-500/50 bg-amber-50/90 p-2 text-[10px] leading-snug text-amber-950 dark:border-amber-600 dark:bg-amber-950/40 dark:text-amber-100',
          },
          JSON.stringify(payload, null, 2),
        );
      }

      return () => {
        const readOnly = isReadOnlyView();
        const list = (fileList.value || []) as UploadFile[];
        const debugEl = renderUploadDebugPanel();

        if (readOnly) {
          const body =
            !list.length
              ? h('span', { class: 'text-muted-foreground text-sm' }, '暂无附件')
              : h(
                  Tooltip,
                  {
                    title: renderUploadPreviewFormatTooltipTitle(),
                    ...uploadPreviewTooltipProps,
                  },
                  {
                    default: () =>
                      h(
                        'div',
                        { class: 'flex flex-col gap-1.5' },
                        list.map((f, idx) => {
                          const url = extractUrlFromFile(f);
                          const label =
                            (f.name && String(f.name).trim()) ||
                            (url ? url.split('/').pop() || '附件' : '附件');
                          if (!url) {
                            return h(
                              'span',
                              { key: f.uid || idx, class: 'text-muted-foreground text-sm' },
                              label,
                            );
                          }
                          const fakeFile = {
                            uid: String(f.uid ?? `ro_${idx}`),
                            name: label,
                            url,
                            status: 'done' as const,
                          } as UploadFile;
                          return h(
                            'div',
                            { key: f.uid || idx, class: 'flex flex-wrap items-center gap-x-2 gap-y-1' },
                            [
                              h(
                                'a',
                                {
                                  href: '#',
                                  class: 'text-primary cursor-pointer hover:underline text-sm',
                                  onClick: (e: Event) => {
                                    e.preventDefault();
                                    void openOnlinePreview(fakeFile);
                                  },
                                },
                                '预览',
                              ),
                              h('span', { class: 'text-muted-foreground' }, '|'),
                              h(
                                'a',
                                {
                                  href: '#',
                                  class: 'text-primary cursor-pointer hover:underline text-sm',
                                  title: '下载到本地',
                                  onClick: (e: Event) => {
                                    e.preventDefault();
                                    void downloadFileAsBlob(url, label, accessStore.accessToken).catch(
                                      (err) => {
                                        notification.error({
                                          message: '下载失败',
                                          description: String((err as Error)?.message || err),
                                        });
                                        window.open(
                                          resolveUploadDownloadHref(url),
                                          '_blank',
                                          'noopener,noreferrer',
                                        );
                                      },
                                    );
                                  },
                                },
                                [
                                  '下载',
                                  h(
                                    'span',
                                    { class: 'text-muted-foreground ml-0.5 text-xs' },
                                    '↓',
                                  ),
                                ],
                              ),
                              h(
                                'span',
                                {
                                  class: 'text-muted-foreground ml-1 max-w-[200px] truncate text-xs',
                                },
                                label,
                              ),
                            ],
                          );
                        }),
                      ),
                  },
                );
          return debugEl ? h(Fragment, [body, debugEl]) : body;
        }

        const uploadEl = h(
          Upload,
          {
            ...props,
            ...attrs,
            action: (() => {
              const m = mergedUploadAttrs();
              const base =
                m.action && String(m.action).trim() !== '#'
                  ? String(m.action)
                  : backendApi('CommonUpload/upload');
              const uploadDir = String(m.uploadDir || m['upload-dir'] || '').trim();
              if (!uploadDir) return base;
              const sep = base.includes('?') ? '&' : '?';
              return `${base}${sep}dir=${encodeURIComponent(uploadDir)}`;
            })(),
            headers: {
              ...(mergedUploadAttrs().headers || {}),
              ...(accessStore.accessToken
                ? { Authorization: `Bearer ${accessStore.accessToken}` }
                : {}),
            },
            disabled: (() => {
              const m = mergedUploadAttrs();
              return !!(m.disabled || m.readOnly || m.readonly);
            })(),
            showUploadList: mergeUploadShowUploadList(mergedUploadAttrs()),
            fileList: fileList.value,
            onChange: handleChange,
            onPreview: handlePreview,
            onDownload: handleDownloadFile,
          },
          renderUploadButton(),
        );
        const uploadWithHint = h(
          Tooltip,
          {
            title: renderUploadPreviewFormatTooltipTitle(),
            ...uploadPreviewTooltipProps,
          },
          { default: () => uploadEl },
        );
        return debugEl ? h(Fragment, [uploadWithHint, debugEl]) : uploadWithHint;
      };
    },
  });
};

const createDefaultSlotsWithUpload = (
  listType: string,
  placeholder: string,
) => {
  switch (listType) {
    case 'picture-card': {
      return {
        default: () => placeholder,
      };
    }
    default: {
      return {
        default: () =>
          h(
            Button,
            {
              icon: h(IconifyIcon, {
                icon: 'ant-design:upload-outlined',
                class: 'mb-1 size-4',
              }),
            },
            () => placeholder,
          ),
      };
    }
  }
};

const previewImage = async (
  file: UploadFile,
  visible: Ref<boolean>,
  fileList: Ref<UploadProps['fileList']>,
) => {
  // 如果当前文件不是图片，直接打开（仅当仍被调用时兜底；非图片优先走 handlePreview 下载）
  if (!isUploadImageFile(file)) {
    if (file.url) {
      window.open(file.url, '_blank');
    } else if (file.preview) {
      window.open(file.preview, '_blank');
    } else {
      console.warn('无法打开文件，没有可用的URL或预览地址');
    }
    return;
  }

  // 对于图片文件，继续使用预览组
  const [ImageComponent, PreviewGroupComponent] = await Promise.all([
    Image,
    PreviewGroup,
  ]);

  const getBase64 = (file: File) => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.readAsDataURL(file);
      reader.addEventListener('load', () => resolve(reader.result));
      reader.addEventListener('error', (error) => reject(error));
    });
  };
  // 从fileList中过滤出所有图片文件
  const imageFiles = (unref(fileList) || []).filter((element) =>
    isUploadImageFile(element),
  );

  // 为所有没有预览地址的图片生成预览
  for (const imgFile of imageFiles) {
    if (!imgFile.url && !imgFile.preview && imgFile.originFileObj) {
      imgFile.preview = (await getBase64(imgFile.originFileObj)) as string;
    }
  }
  const container: HTMLElement | null = document.createElement('div');
  document.body.append(container);

  // 用于追踪组件是否已卸载
  let isUnmounted = false;

  const PreviewWrapper = {
    setup() {
      return () => {
        if (isUnmounted) return null;
        return h(
          PreviewGroupComponent,
          {
            class: 'hidden',
            preview: {
              visible: visible.value,
              // 设置初始显示的图片索引
              current: imageFiles.findIndex((f) => f.uid === file.uid),
              onVisibleChange: (value: boolean) => {
                visible.value = value;
                if (!value) {
                  // 延迟清理，确保动画完成
                  setTimeout(() => {
                    if (!isUnmounted && container) {
                      isUnmounted = true;
                      render(null, container);
                      container.remove();
                    }
                  }, 300);
                }
              },
            },
          },
          () =>
            // 渲染所有图片文件
            imageFiles.map((imgFile) =>
              h(ImageComponent, {
                key: imgFile.uid,
                src: imgFile.url || imgFile.preview,
              }),
            ),
        );
      };
    },
  };

  render(h(PreviewWrapper), container);
};

// 这里需要自行根据业务组件库进行适配，需要用到的组件都需要在这里类型说明
export type ComponentType =
  | 'ApiCascader'
  | 'ApiSelect'
  | 'ApiTreeSelect'
  | 'AutoComplete'
  | 'Cascader'
  | 'Checkbox'
  | 'CheckboxGroup'
  | 'DatePicker'
  | 'DefaultButton'
  | 'Divider'
  | 'IconPicker'
  | 'Input'
  | 'InputNumber'
  | 'InputPassword'
  | 'Mentions'
  | 'PrimaryButton'
  | 'Radio'
  | 'RadioGroup'
  | 'RangePicker'
  | 'Rate'
  | 'Select'
  | 'Space'
  | 'Switch'
  | 'Textarea'
  | 'TimePicker'
  | 'TreeSelect'
  | 'Upload'
  | BaseFormComponentType;

async function initComponentAdapter() {
  const components: Partial<Record<ComponentType, Component>> = {
    // 如果你的组件体积比较大，可以使用异步加载
    // Button: () =>
    // import('xxx').then((res) => res.Button),
    ApiCascader: withDefaultPlaceholder(ApiComponent, 'select', {
      component: Cascader,
      fieldNames: { label: 'label', value: 'value', children: 'children' },
      loadingSlot: 'suffixIcon',
      modelPropName: 'value',
      visibleEvent: 'onVisibleChange',
    }),
    ApiSelect: withDefaultPlaceholder(
      {
        ...ApiComponent,
        name: 'ApiSelect',
      },
      'select',
      {
        component: Select,
        loadingSlot: 'suffixIcon',
        visibleEvent: 'onDropdownVisibleChange',
        modelPropName: 'value',
      },
    ),
    ApiTreeSelect: withDefaultPlaceholder(
      {
        ...ApiComponent,
        name: 'ApiTreeSelect',
      },
      'select',
      {
        component: TreeSelect,
        fieldNames: { label: 'label', value: 'value', children: 'children' },
        loadingSlot: 'suffixIcon',
        modelPropName: 'value',
        optionsPropName: 'treeData',
        visibleEvent: 'onVisibleChange',
      },
    ),
    AutoComplete,
    Cascader,
    Checkbox,
    CheckboxGroup,
    DatePicker,
    // 自定义默认按钮
    DefaultButton: (props, { attrs, slots }) => {
      return h(Button, { ...props, attrs, type: 'default' }, slots);
    },
    Divider,
    IconPicker: withDefaultPlaceholder(IconPicker, 'select', {
      iconSlot: 'addonAfter',
      inputComponent: Input,
      modelValueProp: 'value',
    }),
    Input: withDefaultPlaceholder(Input, 'input'),
    InputNumber: withDefaultPlaceholder(InputNumber, 'input'),
    InputPassword: withDefaultPlaceholder(InputPassword, 'input'),
    Mentions: withDefaultPlaceholder(Mentions, 'input'),
    // 自定义主要按钮
    PrimaryButton: (props, { attrs, slots }) => {
      return h(Button, { ...props, attrs, type: 'primary' }, slots);
    },
    Radio,
    RadioGroup,
    RangePicker,
    Rate,
    Select: withDefaultPlaceholder(Select, 'select'),
    Space,
    Switch,
    Textarea: withDefaultPlaceholder(Textarea, 'input'),
    TimePicker,
    TreeSelect: withDefaultPlaceholder(TreeSelect, 'select'),
    Upload: withPreviewUpload(),
  };

  // 将组件注册到全局共享状态中
  globalShareState.setComponents(components);

  // 定义全局共享状态中的消息提示
  globalShareState.defineMessage({
    // 复制成功消息提示
    copyPreferencesSuccess: (title, content) => {
      notification.success({
        description: content,
        message: title,
        placement: 'bottomRight',
      });
    },
  });
}

export { initComponentAdapter };
