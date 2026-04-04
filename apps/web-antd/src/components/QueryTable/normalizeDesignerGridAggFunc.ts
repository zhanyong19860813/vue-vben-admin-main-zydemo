/**
 * vxe-table 4.x：非透视模式下 column.aggFunc 不能为 'sum' 等字符串，会报 errProp。
 * 列表设计器里的 aggFunc 语义改为表尾 footerMethod 汇总（当前页数据）。
 */

function computeAgg(data: any[], field: string, fn: string): string {
  const values = data.map((row) => row?.[field]);
  const nums = values.map((v) => Number(v)).filter((n) => !Number.isNaN(n));
  switch (fn) {
    case 'sum': {
      const s = nums.reduce((a, b) => a + b, 0);
      return Number.isFinite(s) ? String(s) : '';
    }
    case 'avg': {
      if (!nums.length) return '';
      const s = nums.reduce((a, b) => a + b, 0) / nums.length;
      return Number.isFinite(s) ? s.toFixed(4).replace(/\.?0+$/, '') : '';
    }
    case 'min':
      return nums.length ? String(Math.min(...nums)) : '';
    case 'max':
      return nums.length ? String(Math.max(...nums)) : '';
    case 'count':
      return String(values.filter((v) => v !== null && v !== undefined && v !== '').length);
    case 'first':
      return values[0] != null && values[0] !== '' ? String(values[0]) : '';
    case 'last': {
      const last = values.length ? values[values.length - 1] : undefined;
      return last != null && last !== '' ? String(last) : '';
    }
    default:
      return '';
  }
}

function walkColumns(cols: any[], aggByField: Map<string, string>): any[] {
  return cols.map((col) => {
    const next: Record<string, any> = { ...col };
    if (Array.isArray(col.children) && col.children.length) {
      next.children = walkColumns(col.children, aggByField);
    }
    const af = col.aggFunc;
    if (af != null && af !== false && af !== true) {
      const field = col.field;
      if (field) {
        aggByField.set(String(field), String(af).toLowerCase());
      }
      delete next.aggFunc;
    }
    return next;
  });
}

export function normalizeDesignerGridAggFunc(
  grid: Record<string, any> | undefined | null,
): Record<string, any> {
  if (!grid || !Array.isArray(grid.columns)) {
    return grid ? { ...grid } : {};
  }
  const aggByField = new Map<string, string>();
  const columns = walkColumns(grid.columns, aggByField);
  const hasAgg = aggByField.size > 0;
  const prevFooter = grid.footerMethod;

  if (!hasAgg) {
    return { ...grid, columns };
  }

  const footerMethod = (opts: { columns: { field?: string }[]; data: any[] }) => {
    const { columns: visibleColumn, data } = opts;
    const row = visibleColumn.map((column) => {
      const field = column.field;
      if (!field) return '';
      const fn = aggByField.get(field);
      if (!fn) return '';
      return computeAgg(data, field, fn);
    });
    const designerRows = row.some((c) => c !== '') ? [row] : [];
    if (typeof prevFooter === 'function') {
      const rest = prevFooter(opts as any);
      const extra = Array.isArray(rest) ? rest : [];
      return [...designerRows, ...extra];
    }
    return designerRows;
  };

  return {
    ...grid,
    columns,
    showFooter: true,
    footerMethod,
  };
}
