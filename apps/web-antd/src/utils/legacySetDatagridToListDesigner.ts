/**
 * 将老系统 t_set_datagrid 行映射为列表设计器使用的列 / 查询表单
 */
import type { FormSchemaItem, GridColumnItem } from '#/views/demos/list-designer/list-designer.types';

export interface LegacySetDatagridRow {
  name?: string;
  caption?: string;
  width?: number;
  sort?: number;
  data_type?: string;
  /** Y/N/空 */
  is_visiable?: string | null;
  /** Y/N/空 */
  is_query?: string | null;
  /** Y/N */
  is_key?: string | null;
  entity?: string;
}

function isTruthyFlag(v: unknown): boolean {
  const s = String(v ?? '').trim().toUpperCase();
  return s === 'Y' || s === '1' || s === 'TRUE';
}

/** 同一 entity 多条 function_id 时按 name 去重，保留 sort 最小的一条 */
export function dedupeLegacyDatagridByName(rows: LegacySetDatagridRow[]): LegacySetDatagridRow[] {
  const sorted = [...rows].sort((a, b) => (a.sort ?? 0) - (b.sort ?? 0));
  const seen = new Set<string>();
  const out: LegacySetDatagridRow[] = [];
  for (const r of sorted) {
    const n = String(r.name ?? '').trim();
    if (!n || seen.has(n)) continue;
    seen.add(n);
    out.push(r);
  }
  return out;
}

export function legacyDatagridRowsToGridColumns(rows: LegacySetDatagridRow[]): GridColumnItem[] {
  const list = dedupeLegacyDatagridByName(rows);
  const prefix: GridColumnItem[] = [
    { type: 'checkbox', width: 50 },
    { type: 'seq', width: 50 },
  ];
  const cols: GridColumnItem[] = list.map((r) => {
    const visRaw = String(r.is_visiable ?? 'Y').trim().toUpperCase();
    const visible = visRaw !== 'N';
    const w = Number(r.width);
    const width = Number.isFinite(w) && w > 0 ? w : 100;
    return {
      field: String(r.name).trim(),
      title: (r.caption && String(r.caption).trim()) || String(r.name).trim(),
      width,
      sortable: true,
      visible,
      conditionalStyles: [],
      hyperlink: { hrefTemplate: '', openInNewTab: false },
    };
  });
  return [...prefix, ...cols];
}

export function legacyDatagridRowsToFormSchema(rows: LegacySetDatagridRow[]): FormSchemaItem[] {
  const list = dedupeLegacyDatagridByName(rows).filter((r) => isTruthyFlag(r.is_query));
  return list.map((r) => ({
    component: 'Input',
    fieldName: String(r.name).trim(),
    label: (r.caption && String(r.caption).trim()) || String(r.name).trim(),
  }));
}

export function guessPrimaryKeyFromLegacy(rows: LegacySetDatagridRow[]): string {
  const list = dedupeLegacyDatagridByName(rows);
  const keyRow = list.find((r) => isTruthyFlag(r.is_key));
  if (keyRow?.name) return String(keyRow.name).trim();
  const fid = list.find((r) => String(r.name).toUpperCase() === 'FID');
  if (fid) return 'FID';
  const id = list.find((r) => String(r.name).toLowerCase() === 'id');
  if (id) return 'id';
  return 'FID';
}
