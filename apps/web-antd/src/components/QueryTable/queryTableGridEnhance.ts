/**
 * 将列表 schema 中的设计器扩展字段转为 VxeGrid 可识别的配置：
 * - conditionalStyles：条件单元格/行背景色
 * - hyperlink：超链接渲染
 * - cellRender.name === 'CellFieldFallback'：主列为空时用 props.fallbackField 显示（在 adapter/vxe-table 注册）
 *
 * 固定表头 / 表体滚动：
 * - **fillViewportHeight**：用 ResizeObserver 量外层容器像素高度写入 grid.height，并配合 scoped !important 覆盖全局 .vxe-grid height:auto，表头固定、仅表体滚动；可在 grid 上设 fillViewportHeight: false 关闭。
 * - 或仅在 schema.grid 中显式设置 **height** / **maxHeight**。
 * - aggFunc：列汇总（与 Vxe 原生一致，仅自动 showFooter）
 */

export type ConditionalStyleOperator =
  | 'eq'
  | 'ne'
  | 'gt'
  | 'gte'
  | 'lt'
  | 'lte'
  | 'contains'
  | 'empty'
  | 'notEmpty';

export interface ColumnConditionalStyle {
  op: ConditionalStyleOperator;
  value?: string | number | boolean | null;
  backgroundColor: string;
  scope: 'cell' | 'row';
}

export interface ColumnHyperlink {
  hrefTemplate: string;
  openInNewTab?: boolean;
}

type PlainRecord = Record<string, any>;

function isEmptyValue(v: unknown): boolean {
  return v === null || v === undefined || v === '';
}

function toNumber(v: unknown): number | null {
  if (typeof v === 'number' && !Number.isNaN(v)) return v;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isNaN(n) ? null : n;
  }
  return null;
}

export function matchConditionalStyle(actual: unknown, rule: ColumnConditionalStyle): boolean {
  const { op, value } = rule;
  switch (op) {
    case 'empty':
      return isEmptyValue(actual);
    case 'notEmpty':
      return !isEmptyValue(actual);
    case 'contains':
      return String(actual ?? '').includes(String(value ?? ''));
    case 'eq':
      return actual == value;
    case 'ne':
      return actual != value;
    case 'gt':
    case 'gte':
    case 'lt':
    case 'lte': {
      const a = toNumber(actual);
      const b = toNumber(value);
      if (a === null || b === null) return false;
      if (op === 'gt') return a > b;
      if (op === 'gte') return a >= b;
      if (op === 'lt') return a < b;
      return a <= b;
    }
    default:
      return false;
  }
}

type InternalRule = ColumnConditionalStyle & { field: string };

function mergeStyleObjects(
  a: PlainRecord | undefined,
  b: PlainRecord | undefined,
): PlainRecord | undefined {
  if (!a && !b) return undefined;
  return { ...(a || {}), ...(b || {}) };
}

function normalizeUserStyleResult(
  u: void | null | string | PlainRecord | { [key: string]: boolean | null | undefined },
): PlainRecord | undefined {
  if (!u || typeof u === 'string') return undefined;
  if (typeof u !== 'object') return undefined;
  const out: PlainRecord = {};
  for (const [k, v] of Object.entries(u)) {
    if (typeof v === 'string' || typeof v === 'number') out[k] = String(v);
  }
  return Object.keys(out).length ? out : undefined;
}

/** 从 grid.columns 剥离设计器字段并生成 cellStyle / rowStyle / showFooter */
export function enhanceQueryTableGrid(grid: PlainRecord | undefined): PlainRecord {
  if (!grid) return {};
  const rawCols = Array.isArray(grid.columns) ? grid.columns : [];
  const cellRules: InternalRule[] = [];
  const rowRules: InternalRule[] = [];

  const columns = rawCols.map((col: PlainRecord) => {
    if (!col || col.type) return { ...col };
    const next: PlainRecord = { ...col };
    const field = col.field as string | undefined;
    const list = col.conditionalStyles as ColumnConditionalStyle[] | undefined;
    if (field && Array.isArray(list)) {
      for (const r of list) {
        if (!r?.backgroundColor || (r.scope !== 'cell' && r.scope !== 'row')) continue;
        const internal = { ...r, field };
        if (r.scope === 'cell') cellRules.push(internal);
        else rowRules.push(internal);
      }
    }
    const link = col.hyperlink as ColumnHyperlink | undefined;
    if (field && link?.hrefTemplate?.trim()) {
      next.cellRender = {
        name: 'SchemaHyperlink',
        props: {
          hrefTemplate: link.hrefTemplate.trim(),
          openInNewTab: !!link.openInNewTab,
        },
      };
    }
    delete next.conditionalStyles;
    delete next.hyperlink;
    return next;
  });

  const userCellStyle = grid.cellStyle;
  const userRowStyle = grid.rowStyle;

  const cellStyle =
    cellRules.length > 0
      ? (params: PlainRecord) => {
          let base: PlainRecord = {};
          if (typeof userCellStyle === 'function') {
            const u = normalizeUserStyleResult(userCellStyle(params));
            if (u) base = { ...u };
          } else if (userCellStyle && typeof userCellStyle === 'object') {
            base = { ...userCellStyle };
          }
          const field = params.column?.field as string | undefined;
          const row = params.row as PlainRecord;
          if (field && row) {
            for (const r of cellRules) {
              if (r.field !== field) continue;
              if (matchConditionalStyle(row[r.field], r)) {
                return mergeStyleObjects(base, { backgroundColor: r.backgroundColor }) ?? {
                  backgroundColor: r.backgroundColor,
                };
              }
            }
          }
          return Object.keys(base).length ? base : undefined;
        }
      : grid.cellStyle;

  const rowStyle =
    rowRules.length > 0
      ? (params: PlainRecord) => {
          let base: PlainRecord = {};
          if (typeof userRowStyle === 'function') {
            const u = normalizeUserStyleResult(userRowStyle(params));
            if (u) base = { ...u };
          } else if (userRowStyle && typeof userRowStyle === 'object') {
            base = { ...userRowStyle };
          }
          const row = params.row as PlainRecord;
          if (row) {
            for (const r of rowRules) {
              if (matchConditionalStyle(row[r.field], r)) {
                return mergeStyleObjects(base, { backgroundColor: r.backgroundColor }) ?? {
                  backgroundColor: r.backgroundColor,
                };
              }
            }
          }
          return Object.keys(base).length ? base : undefined;
        }
      : grid.rowStyle;

  const hasAgg = columns.some(
    (c: PlainRecord) => c?.aggFunc !== undefined && c?.aggFunc !== null && c?.aggFunc !== false && c?.aggFunc !== '',
  );
  const showFooter = grid.showFooter === true || hasAgg;

  const footerMethod =
    typeof grid.footerMethod === 'function'
      ? grid.footerMethod
      : hasAgg
        ? ({ columns: footerColumns, data }: { columns: PlainRecord[]; data: PlainRecord[] }) => {
            const values = footerColumns.map((c: PlainRecord, idx: number) => {
              // 第一列：显示“合计/汇总”
              if (idx === 0) return '合计';
              const field = c?.field as string | undefined;
              const fn = (c as any)?.aggFunc as string | undefined;
              if (!field || !fn) return '';
              const list = Array.isArray(data) ? data : [];
              const picked = list.map((r) => r?.[field]);
              const nums = picked
                .map((v) => toNumber(v))
                .filter((v): v is number => typeof v === 'number' && !Number.isNaN(v));

              switch (String(fn)) {
                case 'count':
                  return picked.filter((v) => !isEmptyValue(v)).length;
                case 'sum':
                  return nums.reduce((a, b) => a + b, 0);
                case 'avg':
                  return nums.length ? nums.reduce((a, b) => a + b, 0) / nums.length : '';
                case 'min':
                  return nums.length ? Math.min(...nums) : '';
                case 'max':
                  return nums.length ? Math.max(...nums) : '';
                case 'first': {
                  const v = picked.find((x) => !isEmptyValue(x));
                  return v ?? '';
                }
                case 'last': {
                  for (let i = picked.length - 1; i >= 0; i -= 1) {
                    const v = picked[i];
                    if (!isEmptyValue(v)) return v;
                  }
                  return '';
                }
                default:
                  return '';
              }
            });
            return [values];
          }
        : grid.footerMethod;

  return {
    ...grid,
    columns,
    cellStyle,
    rowStyle,
    showFooter,
    footerMethod,
  };
}

export function fillHrefTemplate(template: string, row: PlainRecord): string {
  return template.replace(/\{([^{}]+)\}/g, (_, rawKey: string) => {
    const key = rawKey.trim();
    const v = row[key];
    if (v === undefined || v === null) return '';
    return encodeURIComponent(String(v));
  });
}
