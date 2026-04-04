import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

export type WhereGroup = {
  Logic: string;
  Conditions: Array<{ Field: string; Operator: string; Value: string }>;
  Groups: any[];
};

/** StoneApi Condition.Value 为 string，数字会导致整包 400 */
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

export async function queryForVben(body: Record<string, any>): Promise<any[]> {
  const res = await requestClient.post<{ items?: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), body);
  return res?.items ?? [];
}

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
