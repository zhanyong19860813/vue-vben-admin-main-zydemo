import { queryForVbenPaged } from '#/components/org-picker/orgPickerQuery';

export function looksLikeGuid(s: string): boolean {
  const t = String(s || '').trim();
  if (!t) return false;
  if (
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(t)
  ) {
    return true;
  }
  const hex = t.replace(/-/g, '');
  return /^[0-9a-f]{32}$/i.test(hex);
}

export function normOperatorKey(id: string): string {
  return String(id || '')
    .trim()
    .replace(/^\{|\}$/g, '')
    .replace(/-/g, '')
    .toLowerCase();
}

function pickEmpField(row: Record<string, any>, keys: string[]): string {
  for (const k of keys) {
    const v = row[k];
    if (v !== undefined && v !== null && String(v).trim()) return String(v).trim();
  }
  return '';
}

/** 轨迹行、待办上的办理人 id（GUID）→ 批量查员工视图 */
export function collectEmployeeIdsForDisplay(
  timelineRows: Array<Record<string, any>>,
  tasks: Array<Record<string, any>> | undefined,
): string[] {
  const out = new Set<string>();
  const add = (uid: unknown) => {
    const u = String(uid ?? '').trim();
    if (u && looksLikeGuid(u)) out.add(u);
  };
  for (const r of timelineRows || []) {
    add(r.operator_user_id);
    const n = String(r.operator_name ?? '').trim();
    if (n && looksLikeGuid(n)) add(n);
  }
  for (const t of tasks || []) {
    add(t.assignee_user_id);
    const n = String(t.assignee_name ?? '').trim();
    if (n && looksLikeGuid(n)) add(n);
  }
  return [...out];
}

export async function fetchEmployeeDisplayLabelsByIds(
  ids: string[],
): Promise<Record<string, string>> {
  const map: Record<string, string> = {};
  const uniq = [...new Set(ids.map((x) => String(x).trim()).filter(Boolean))];
  if (!uniq.length) return map;
  const chunkSize = 35;
  for (let i = 0; i < uniq.length; i += chunkSize) {
    const part = uniq.slice(i, i + chunkSize);
    const where = {
      Logic: 'AND',
      Conditions: [],
      Groups: [
        {
          Logic: 'OR',
          Conditions: part.map((id) => ({ Field: 'id', Operator: 'eq', Value: id })),
          Groups: [],
        },
      ],
    };
    try {
      const { items } = await queryForVbenPaged({
        TableName: 'v_t_base_employee',
        Page: 1,
        PageSize: 100,
        SortBy: 'EMP_ID',
        SortOrder: 'asc',
        Where: where,
      });
      for (const r of items || []) {
        const rec = r as Record<string, any>;
        const id = pickEmpField(rec, ['id', 'ID']);
        if (!id) continue;
        const name = pickEmpField(rec, ['name', 'NAME', 'first_name']) || '—';
        const code = pickEmpField(rec, ['EMP_ID', 'emp_id', 'code']);
        const label = code ? `${name}（${code}）` : name;
        map[normOperatorKey(id)] = label;
        map[String(id).trim()] = label;
      }
    } catch {
      /* ignore */
    }
  }
  return map;
}

/**
 * 展示办理人：优先用缓存的「姓名（工号）」；否则保留可读姓名；再否则显示 id。
 */
export function formatOperatorLabel(
  dm: Record<string, string>,
  name: string | undefined,
  userId: string | undefined,
): string {
  const uRaw = String(userId ?? '').trim();
  let nRaw = String(name ?? '').trim();
  const idForLookup = uRaw || (looksLikeGuid(nRaw) ? nRaw : '');
  if (looksLikeGuid(nRaw)) nRaw = '';
  if (idForLookup) {
    const hit = dm[normOperatorKey(idForLookup)] ?? dm[idForLookup] ?? dm[String(idForLookup).trim()];
    if (hit) return hit;
  }
  if (nRaw) return nRaw;
  if (uRaw) return uRaw;
  return '—';
}

/** 与 runtime 页「审批记录」卡片一致：latest 优先，再 pending */
export function resolveActorFromLatestAndPending(
  dm: Record<string, string>,
  latest: Record<string, any> | undefined,
  pendingTask: Record<string, any> | undefined,
): string {
  const n1 = String(latest?.operator_name ?? '').trim();
  const u1 = String(latest?.operator_user_id ?? '').trim();
  const n2 = String(pendingTask?.assignee_name ?? '').trim();
  const u2 = String(pendingTask?.assignee_user_id ?? '').trim();
  if (n1 || u1) return formatOperatorLabel(dm, n1 || undefined, u1 || undefined);
  if (n2 || u2) return formatOperatorLabel(dm, n2 || undefined, u2 || undefined);
  return '—';
}
