<script setup lang="ts">
import { watch, nextTick } from 'vue';
import { Button, message } from 'ant-design-vue';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

import DictionaryDetailModal from './DictionaryDetailModal.vue';
import { useVbenModal } from '@vben/common-ui';

const props = defineProps<{
  currentDictionaryId?: string;
}>();

interface DetailRow {
  id?: string;
  dictionary_id?: string;
  name: string;
  value: string;
  help_code?: string;
  description?: string;
  sort?: number;
}

const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    height: 550,
    columns: [
      { type: 'checkbox', width: 60 },
      { type: 'seq', width: 50, title: '序号' },
      { field: 'name', title: '值名称', minWidth: 120 },
      { field: 'value', title: '值', minWidth: 100 },
      { field: 'help_code', title: '辅助值', minWidth: 120 },
      { field: 'description', title: '说明', minWidth: 150 },
    ],
    pagerConfig: {
      enabled: true,
      pageSize: 500,
      pageSizes: [100, 200, 500],
    },
    proxyConfig: {
      props: { result: 'items', total: 'total' },
      ajax: {
        query: async () => {
          if (!props.currentDictionaryId) {
            return { items: [], total: 0 };
          }
          const res = await requestClient.post(backendApi('DynamicQueryBeta/queryforvben'), {
            TableName: 'vben_t_base_dictionary_detail',
            Page: 1,
            PageSize: 500,
            SortBy: 'sort',
            SortOrder: 'asc',
            SimpleWhere: { dictionary_id: props.currentDictionaryId },
          });
          const raw = res?.data ?? res;
          return {
            items: raw?.items ?? raw?.records ?? [],
            total: raw?.total ?? 0,
          };
        },
      },
    },
    toolbarConfig: {
      custom: true,
    },
  },
});

watch(
  () => props.currentDictionaryId,
  async (val) => {
    if (!val) return;
    await nextTick();
    gridApi.query();
  },
  { immediate: true }
);

const [DetailModal, detailModalApi] = useVbenModal({
  connectedComponent: DictionaryDetailModal,
});

function openAddDetail() {
  if (!props.currentDictionaryId) {
    message.warning('请先选择一个字典分类');
    return;
  }
  detailModalApi
    .setData({
      values: {
        dictionary_id: props.currentDictionaryId,
        onSuccess: () => gridApi.query(),
      },
    })
    .open();
}

function openEditDetail() {
  const grid = gridApi.grid;
  if (!grid) return;
  const rows = grid.getCheckboxRecords() as DetailRow[];
  if (rows.length !== 1) {
    message.warning('请选择一条记录进行编辑');
    return;
  }
  detailModalApi
    .setData({
      values: {
        ...rows[0],
        onSuccess: () => gridApi.query(),
      },
    })
    .open();
}

async function deleteDetail() {
  const grid = gridApi.grid;
  if (!grid) return;
  const rows = grid.getCheckboxRecords() as DetailRow[];
  if (!rows.length) {
    message.warning('请选择要删除的记录');
    return;
  }
  const ids = rows.map((r) => r.id).filter(Boolean);
  if (!ids.length) {
    message.warning('选中的记录无法删除');
    return;
  }
  try {
    await requestClient.post(
      backendApi('DataBatchDelete/BatchDelete'),
      [
        {
          tablename: 'vben_t_base_dictionary_detail',
          key: 'id',
          Keys: ids,
        },
      ],
      { headers: { 'Content-Type': 'application/json' } }
    );
    message.success('删除成功');
    gridApi.query();
  } catch (e) {
    message.error('删除失败');
  }
}
</script>

<template>
  <div>
    <Grid table-title="字典明细">
      <template #toolbar-tools>
        <Button type="primary" size="small" @click="openAddDetail">新增</Button>
        <Button size="small" @click="openEditDetail">编辑</Button>
        <Button danger size="small" @click="deleteDetail">删除</Button>
        <Button size="small" @click="gridApi.query()">刷新</Button>
      </template>
    </Grid>
    <DetailModal />
  </div>
</template>
