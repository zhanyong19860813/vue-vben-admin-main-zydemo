<script setup lang="ts">
import { h, ref } from 'vue';
import { AutoComplete, Card, Input, Tag } from 'ant-design-vue';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

/**
 * 静态演示页：AutoComplete 远程查询 + 选中后回填其它列
 *
 * SQL 等价于：
 *  select id,code ,name,brith_date,dept_id,long_name
 *  from  v_t_base_employee
 *
 *  - 展示：name
 *  - 输入/存储：code（可按需改 valueField）
 *  - 搜索：code/name（OR 模糊）
 *  - 回填：brith_date / dept_id / long_name（字段名默认与列名一致）
 */

const TABLE_NAME = 'v_t_base_employee';
const QUERY_FIELDS = 'id,code,name,brith_date,dept_id,long_name';

// 展示与写入（默认与列名一致）
const LABEL_FIELD = 'name';
const VALUE_FIELD = 'code';

// 模糊搜索字段（支持多个列，OR）
const SEARCH_FIELDS = ['code', 'name'];

type Row = Record<string, any>;

const loading = ref(false);
const autoValue = ref<string>('');
const options = ref<Array<{ value: any; label: string; _raw: Row }>>([]);
const selectedRaw = ref<Row | null>(null);
const dropdownOpen = ref(false);

function getRawField(raw: Row | undefined | null, key: string) {
  if (!raw || !key) return undefined;
  const target = String(key).toLowerCase().trim().replace(/\s+/g, '');
  for (const k of Object.keys(raw)) {
    const kk = String(k).toLowerCase().trim().replace(/\s+/g, '');
    if (kk === target) return raw[k];
  }
  // 兜底兼容：有些视图/导出可能用中文别名（如 姓名）
  if (target === 'name') {
    const zh = ['姓名', 'Name', 'NAME'].find((x) => {
      const t = String(x).toLowerCase().trim().replace(/\s+/g, '');
      return t;
    });
    if (zh) {
      const zhKey = String(zh).toLowerCase().trim().replace(/\s+/g, '');
      for (const k of Object.keys(raw)) {
        const kk = String(k).toLowerCase().trim().replace(/\s+/g, '');
        if (kk === zhKey) return raw[k];
      }
    }
  }
  return undefined;
}

function formatDateValue(v: any) {
  if (v === null || v === undefined) return '';
  if (v instanceof Date) {
    return v.toISOString().slice(0, 10);
  }
  const s = String(v).trim();
  if (!s) return '';
  // ISO: 2019-02-27T16:56:06 => 2019-02-27
  if (s.includes('T')) return s.split('T')[0] ?? '';
  // 常见：yyyy-MM-dd
  return s.slice(0, 10);
}

// 回填到页面上的输入框（先按“列名=fieldName”做最小演示）
const idValue = ref<string>('');
const codeValue = ref<string>('');
const nameValue = ref<string>('');
const brithDateValue = ref<string>('');
const deptIdValue = ref<string>('');
const longNameValue = ref<string>('');

// AutoComplete 下拉用 dropdownRender 自定义渲染多列
function dropdownRender() {
  const nodes: any[] = [];

  nodes.push(
    h(
      'div',
      {
        style:
          'display:flex; gap:10px; align-items:center; justify-content:flex-start; padding:4px 2px; background:#fafafa; border-bottom:1px solid #f0f0f0; font-weight:600; font-size:12px; color:#666;',
      },
      [
        h('span', { style: 'width:70px; overflow:hidden; text-overflow:ellipsis;' }, '工号'),
        h('span', { style: 'flex:1; overflow:hidden; text-overflow:ellipsis;' }, '姓名'),
        h('span', { style: 'width:120px; overflow:hidden; text-overflow:ellipsis;' }, '生日'),
        h('span', { style: 'width:140px; overflow:hidden; text-overflow:ellipsis;' }, '部门'),
      ],
    ),
  );

  if (options.value.length) {
    for (const opt of options.value) {
      nodes.push(
        h(
          'div',
          {
            style:
                  'display:flex; gap:10px; align-items:center; justify-content:flex-start; padding:6px 2px; cursor:pointer; border-bottom:1px solid #f5f5f5; font-size:12px;',
            onClick: () => {
              autoValue.value = opt.value;
              fillFromRaw(opt._raw);
              dropdownOpen.value = false;
            },
          },
          [
            h(
              'span',
              { style: 'width:70px; overflow:hidden; text-overflow:ellipsis;' },
              String(getRawField(opt._raw, 'code') ?? ''),
            ),
            h(
              'span',
              { style: 'flex:1; overflow:hidden; text-overflow:ellipsis;' },
              String(getRawField(opt._raw, 'name') ?? ''),
            ),
            h(
              'span',
              { style: 'width:120px; overflow:hidden; text-overflow:ellipsis;' },
              formatDateValue(getRawField(opt._raw, 'brith_date')),
            ),
            h(
              'span',
              { style: 'width:140px; overflow:hidden; text-overflow:ellipsis;' },
              String(getRawField(opt._raw, 'long_name') ?? ''),
            ),
          ],
        ),
      );
    }
  } else {
    nodes.push(
      h(
        'div',
        { style: 'color:#999; padding: 8px 0; font-size:12px;' },
        '暂无数据',
      ),
    );
  }

  return h(
    'div',
    {
      style:
        'padding: 6px 8px; min-width: 520px; max-height: 300px; overflow:auto; background:#fff; border:1px solid #f0f0f0; border-radius:6px;',
    },
    nodes,
  );
}

async function query(keyword: string) {
  const kw = String(keyword ?? '').trim();
  if (!kw) {
    options.value = [];
    return;
  }

  loading.value = true;
  try {
    const res = await requestClient.post<any>(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: TABLE_NAME,
      Page: 1,
      PageSize: 10,
      QueryField: QUERY_FIELDS,
      SortBy: SEARCH_FIELDS[0] ?? LABEL_FIELD,
      SortOrder: 'asc',
      Where: {
        Logic: 'OR',
        Conditions: SEARCH_FIELDS.map((f) => ({
          Field: f,
          Operator: 'contains',
          Value: kw,
        })),
        Groups: [],
      },
    });

    const items: Row[] = res?.items ?? [];
    options.value = items.map((row) => ({
      value: row?.[VALUE_FIELD],
      label: String(row?.[LABEL_FIELD] ?? ''),
      _raw: row,
    }));
  } finally {
    loading.value = false;
  }
}

function fillFromRaw(row: Row | null) {
  selectedRaw.value = row;
  idValue.value = String(getRawField(row, 'id') ?? '');
  codeValue.value = String(getRawField(row, 'code') ?? '');
  nameValue.value = String(getRawField(row, 'name') ?? '');
  brithDateValue.value = formatDateValue(getRawField(row, 'brith_date'));
  deptIdValue.value = String(getRawField(row, 'dept_id') ?? '');
  longNameValue.value = String(getRawField(row, 'long_name') ?? '');
}

async function onSearch(v: string) {
  await query(v);
}

function onSelect(_value: any, option: any) {
  const raw: Row | null = option?._raw ?? option?.raw ?? null;
  if (!raw) return;

  // AutoComplete 的 valueField 写入 code（当前 demo 默认）
  autoValue.value = raw?.[VALUE_FIELD] ?? '';
  fillFromRaw(raw);
}

function formatJson(v: any) {
  try {
    return JSON.stringify(v ?? {}, null, 2);
  } catch {
    return String(v);
  }
}
</script>

<template>
  <div class="p-4">
    <Card title="AutoComplete 远程查询 Demo（静态页面）">
      <div class="grid gap-4 md:grid-cols-2">
        <div class="space-y-3">
          <div class="text-sm font-medium">搜索 & 选中</div>

          <AutoComplete
            v-model:value="autoValue"
            :options="options"
            :loading="loading"
            placeholder="输入 code 或 name"
            style="width: 320px"
            :filter-option="false"
            @search="onSearch"
            @select="onSelect"
            :dropdownRender="dropdownRender"
            :open="dropdownOpen"
            @dropdownVisibleChange="(o) => (dropdownOpen = o)"
          >
          </AutoComplete>

          <div class="text-xs text-muted-foreground">
            搜索字段：<span class="font-mono">{{ SEARCH_FIELDS.join(',') }}</span>
            &nbsp;|&nbsp; 展示：<span class="font-mono">{{ LABEL_FIELD }}</span>
            &nbsp;|&nbsp; 回填：brith_date/dept_id/long_name
          </div>
        </div>

        <div class="space-y-3">
          <div class="text-sm font-medium">回填结果（按列名=fieldName）</div>

          <div class="flex items-center gap-3">
            <div class="w-20 text-xs text-muted-foreground">id</div>
            <Input v-model:value="idValue" />
          </div>

          <div class="flex items-center gap-3">
            <div class="w-20 text-xs text-muted-foreground">code</div>
            <Input v-model:value="codeValue" />
            <Tag color="blue">已选</Tag>
          </div>

          <div class="flex items-center gap-3">
            <div class="w-20 text-xs text-muted-foreground">name</div>
            <Input v-model:value="nameValue" />
          </div>

          <div class="flex items-center gap-3">
            <div class="w-20 text-xs text-muted-foreground">brith_date</div>
            <Input v-model:value="brithDateValue" />
          </div>

          <div class="flex items-center gap-3">
            <div class="w-20 text-xs text-muted-foreground">dept_id</div>
            <Input v-model:value="deptIdValue" />
          </div>

          <div class="flex items-center gap-3">
            <div class="w-20 text-xs text-muted-foreground">long_name</div>
            <Input v-model:value="longNameValue" />
          </div>
        </div>
      </div>

      <div class="mt-4">
        <div class="mb-2 text-sm font-medium">调试：选中行 raw</div>
        <pre class="max-h-72 overflow-auto rounded border bg-neutral-50 p-3 text-xs font-mono">
{{ formatJson(selectedRaw) }}
        </pre>
      </div>
    </Card>
  </div>
</template>

