<script setup lang="ts">
import { watch } from 'vue';
import { Button, message } from 'ant-design-vue';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { requestClient } from '#/api/request';
import { useVbenModal } from '@vben/common-ui';

import formModelAddMenu from './form-model-AddMenu.vue';

const props = defineProps<{
  currentRoleId?: string;
}>();

const [MenuGrid, gridMenuApi] = useVbenVxeGrid({
  gridOptions: {
    columns: [
      { type: 'checkbox', width: 100 },
      { type: 'seq', width: 50 },
      { field: 'id', title: 'ID' },
      { field: 'entity_name', title: '菜单名' },
      { field: 'meta', title: 'meta' },
      { field: 'url', title: '路径' },
      { field: 'bar_items', title: '按钮' },
    ],
    pagerConfig: { enabled: false },
    proxyConfig: {
      ajax: {
        query: async () => {
          if (!props.currentRoleId) {
            return { records: [], total: 0 };
          }
          return requestClient.get(
            'http://localhost:5155/api/DynamicQueryBeta/query',
            {
              params: {
                tableName: 'vben_v_role_menu',
                page: 1,
                pageSize: 20,
                simpleWhere: { role_id: props.currentRoleId },
              },
            }
          );
        },
      },
    },
  },
});

watch(() => props.currentRoleId, () => gridMenuApi.query());

// 弹窗
const [FormMenuModal, formMenuModalApi] = useVbenModal({
  connectedComponent: formModelAddMenu,
});
</script>

<template>
  <div>
    <Button type="primary">新增</Button>
    <Button danger>删除</Button>
    <MenuGrid />
    <FormMenuModal />
  </div>
</template>
