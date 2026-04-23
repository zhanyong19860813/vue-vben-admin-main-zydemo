import dayjs from 'dayjs';

import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

const ZERO_UUID = '00000000-0000-0000-0000-000000000000';

export type WhereGroup = {
  Logic: string;
  Conditions: Array<{ Field: string; Operator: string; Value: string }>;
  Groups: any[];
};

export async function queryForVben(body: Record<string, any>): Promise<any[]> {
  const res = await requestClient.post<{ items?: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), body);
  return res?.items ?? [];
}

/**
 * 静默查询：失败时不弹全局 message（用于白名单不确定的兜底表，避免 400 误扰用户）。
 */
export async function queryForVbenOptional(body: Record<string, any>): Promise<any[]> {
  try {
    const res = await requestClient.post<{ items?: any[] }>(
      backendApi('DynamicQueryBeta/queryforvben'),
      body,
      { skipGlobalErrorMessage: true } as any,
    );
    return res?.items ?? [];
  } catch {
    return [];
  }
}

/** queryforvben 返回 data：{ items, total }（分页统计用） */
export async function queryForVbenPaged(
  body: Record<string, any>,
): Promise<{ items: any[]; total: number }> {
  const res = await requestClient.post<{ items?: any[]; total?: number }>(
    backendApi('DynamicQueryBeta/queryforvben'),
    body,
  );
  return {
    items: Array.isArray(res?.items) ? res.items : [],
    total: Number(res?.total ?? 0),
  };
}

export async function saveDatasaveMulti(tables: any[]) {
  return requestClient.post(backendApi('DataSave/datasave-multi'), { tables });
}

export async function batchDelete(
  items: Array<{ tablename: string; key: string; Keys: string[] }>,
) {
  return requestClient.post(backendApi('DataBatchDelete/BatchDelete'), items);
}

export async function executeProcedure(
  procedureName: string,
  parameters: Record<string, any>,
) {
  return requestClient.post(backendApi('Procedure/execute'), {
    procedureName,
    parameters,
    returnData: false,
  });
}

/** 按公历年加载法定节假日日期集合（YYYY-MM-DD），供排班表头等展示 △ 标记 */
export async function loadStatutoryHolidayDateSet(year: string): Promise<Set<string>> {
  const y = Number(year);
  const set = new Set<string>();
  if (!Number.isFinite(y)) return set;

  let rows = await queryForVbenOptional({
    TableName: 'v_att_lst_StatutoryHoliday',
    Page: 1,
    PageSize: 5000,
    SortBy: 'Holidaydate',
    SortOrder: 'asc',
  });
  if (rows.length === 0) {
    rows = await queryForVbenOptional({
      TableName: 'att_lst_StatutoryHoliday',
      Page: 1,
      PageSize: 5000,
      SortBy: 'Holidaydate',
      SortOrder: 'asc',
    });
  }
  for (const r of rows) {
    const raw = (r as any)?.Holidaydate ?? (r as any)?.holidaydate;
    if (!raw) continue;
    const dt = dayjs(raw);
    if (!dt.isValid() || dt.year() !== y) continue;
    set.add(dt.format('YYYY-MM-DD'));
  }
  return set;
}

/**
 * 客户端复刻老系统 `AttLstJobScheduling.UpdateSchedulingByTime`（StoneApi 无该 MVC 路由）。
 * 按日期区间写入 `Day*_ID` / `Day*_Name`，并 `saveDatasave-multi` 落库。
 */
export async function clientApplySchedulingByTime(opts: {
  bcCode: string;
  bcName: string;
  startDate: string; // yyyyMMdd
  endDate: string; // yyyyMMdd
  empIds: string[];
  modifier: string;
  excludeSat: boolean;
  excludeSun: boolean;
  excludePublicHoliday: boolean;
}): Promise<void> {
  const { startDate, endDate, bcCode, bcName, excludeSat, excludeSun, excludePublicHoliday } = opts;
  if (startDate.length !== 8 || endDate.length !== 8) {
    throw new Error('排班日期格式无效');
  }
  if (startDate.slice(0, 6) !== endDate.slice(0, 6)) {
    throw new Error('开始与结束日期须在同一个月内');
  }
  const monthStr = startDate.slice(0, 6);
  const year = monthStr.slice(0, 4);

  const empIds = opts.empIds.map((x) => String(x).trim()).filter(Boolean);
  if (!empIds.length) {
    throw new Error('没有可保存的人员工号');
  }

  const holidaySet = excludePublicHoliday ? await loadStatutoryHolidayDateSet(year) : new Set<string>();

  const patchByDayNum = new Map<number, { id: string; name: string }>();
  let cursor = dayjs(startDate, 'YYYYMMDD');
  const end = dayjs(endDate, 'YYYYMMDD');
  if (!cursor.isValid() || !end.isValid()) {
    throw new Error('排班日期无效');
  }
  while (!cursor.isAfter(end, 'day')) {
    const dayNum = cursor.date();
    const weekday = cursor.day();
    let id = bcCode;
    let name = bcName;
    if (excludeSat && weekday === 6) {
      id = ZERO_UUID;
      name = '';
    } else if (excludeSun && weekday === 0) {
      id = ZERO_UUID;
      name = '';
    } else if (excludePublicHoliday && holidaySet.has(cursor.format('YYYY-MM-DD'))) {
      id = ZERO_UUID;
      name = '';
    }
    patchByDayNum.set(dayNum, { id, name });
    cursor = cursor.add(1, 'day');
  }

  const res = await queryForVbenPaged({
    TableName: 'v_att_lst_JobScheduling',
    Page: 1,
    PageSize: 5000,
    SortBy: 'EMP_ID',
    SortOrder: 'asc',
    Where: whereAnd([{ Field: 'JS_Month', Operator: 'contains', Value: monthStr }]),
  });

  const byEmp = new Map<string, any>();
  for (const r of res.items) {
    const eid = String(r?.EMP_ID ?? '').trim();
    if (eid) byEmp.set(eid, r);
  }

  const payloads: Record<string, any>[] = [];

  for (const eid of empIds) {
    const base = byEmp.get(eid);
    const fid = base?.FID ? String(base.FID) : crypto.randomUUID();
    const jsMonthVal = base?.JS_Month ?? monthStr;

    const payload: Record<string, any> = {
      FID: fid,
      EMP_ID: eid,
      JS_Month: jsMonthVal,
      modifier: opts.modifier,
    };

    for (let d = 1; d <= 31; d++) {
      const patch = patchByDayNum.get(d);
      if (patch) {
        payload[`Day${d}_ID`] = patch.id;
        payload[`Day${d}_Name`] = patch.name;
      } else if (base) {
        payload[`Day${d}_ID`] = String(base[`Day${d}_ID`] ?? '').trim() || ZERO_UUID;
        payload[`Day${d}_Name`] = String(base[`Day${d}_Name`] ?? '').trim();
      } else {
        payload[`Day${d}_ID`] = ZERO_UUID;
        payload[`Day${d}_Name`] = '';
      }
    }
    payloads.push(payload);
  }

  await saveDatasaveMulti([
    {
      tableName: 'att_lst_JobScheduling',
      primaryKey: 'FID',
      data: payloads,
      deleteRows: [],
    },
  ]);
}

/** StoneApi Condition.Value is string; JSON numbers fail to deserialize and yield 400. */
export function whereAnd(
  conditions: Array<{ Field: string; Operator: string; Value: unknown }>,
): WhereGroup {
  return {
    Logic: 'AND',
    Conditions: conditions.map((c) => ({
      Field: c.Field,
      Operator: c.Operator,
      Value: c.Value === null || c.Value === undefined ? '' : String(c.Value),
    })),
    Groups: [],
  };
}

export function whereOr(
  conditions: Array<{ Field: string; Operator: string; Value: unknown }>,
): WhereGroup {
  return {
    Logic: 'OR',
    Conditions: conditions.map((c) => ({
      Field: c.Field,
      Operator: c.Operator,
      Value: c.Value === null || c.Value === undefined ? '' : String(c.Value),
    })),
    Groups: [],
  };
}
