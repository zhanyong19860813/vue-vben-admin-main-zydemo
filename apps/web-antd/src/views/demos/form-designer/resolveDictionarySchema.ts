/**
 * 将 schema 中的数据字典 ID 解析为实际的 options / treeData
 * 用于表单设计器配置了 dataSourceType='dictionary' 的控件
 */
import type { VbenFormSchema } from '#/adapter/form';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

const COMPONENTS_WITH_OPTIONS = [
  'Select',
  'RadioGroup',
  'CheckboxGroup',
  'AutoComplete',
  'Cascader',
];
const COMPONENTS_WITH_TREEDATA = ['TreeSelect'];

function needsOptions(comp: string) {
  return COMPONENTS_WITH_OPTIONS.includes(comp);
}
function needsTreeData(comp: string) {
  return COMPONENTS_WITH_TREEDATA.includes(comp);
}

async function fetchDictionaryDetails(dictionaryId: string): Promise<Array<{ name: string; value: string }>> {
  const res = await requestClient.post<{ items?: any[]; records?: any[] }>(
    backendApi('DynamicQueryBeta/queryforvben'),
    {
      TableName: 'vben_t_base_dictionary_detail',
      Page: 1,
      PageSize: 2000,
      SortBy: 'sort',
      SortOrder: 'asc',
      SimpleWhere: { dictionary_id: dictionaryId },
    },
  );
  const raw = res?.data ?? res;
  const list = raw?.items ?? raw?.records ?? [];
  return list.map((r: any) => ({
    name: r.name ?? r.label ?? '',
    value: String(r.value ?? r.name ?? ''),
  }));
}

/**
 * 解析 schema 中所有使用数据字典的字段，将 dictionaryId 转为 options / treeData
 */
export async function resolveDictionaryInSchema(
  schema: VbenFormSchema[],
): Promise<VbenFormSchema[]> {
  if (!schema?.length) return schema;

  const dictIds = new Set<string>();
  for (const item of schema) {
    const cp = (item as any).componentProps;
    const comp = (item as any).component;
    if (!cp?.dictionaryId || (!needsOptions(comp) && !needsTreeData(comp))) continue;
    dictIds.add(cp.dictionaryId);
  }

  const dictMap = new Map<string, Array<{ name: string; value: string }>>();
  await Promise.all(
    Array.from(dictIds).map(async (id) => {
      try {
        const details = await fetchDictionaryDetails(id);
        dictMap.set(id, details);
      } catch {
        dictMap.set(id, []);
      }
    }),
  );

  return schema.map((item) => {
    const cp = (item as any).componentProps;
    const comp = (item as any).component;
    if (!cp?.dictionaryId) return { ...item };

    const details = dictMap.get(cp.dictionaryId) ?? [];
    const next = { ...item, componentProps: { ...cp } };
    const nextCp = (next as any).componentProps;

    if (needsOptions(comp)) {
      nextCp.options = details.map((d) => ({
        label: d.name,
        value: d.value,
      }));
    } else if (needsTreeData(comp)) {
      nextCp.treeData = details.map((d) => ({
        title: d.name,
        value: d.value,
        key: d.value,
      }));
    }
    return next;
  });
}
