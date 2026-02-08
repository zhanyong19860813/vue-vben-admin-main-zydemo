<script setup lang="ts">
import { watch } from 'vue';
import { Button, message } from 'ant-design-vue';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { requestClient } from '#/api/request';
import { useVbenModal } from '@vben/common-ui';

import formModelAddUser from './form-model-AddUser.vue';

const props = defineProps<{
  currentRoleId?: string;
}>();

const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    columns: [
      { type: 'checkbox', width: 100 },
      { type: 'seq', width: 50 },
      { field: 'id', title: 'id' },
      { field: 'user_name', title: '用户名' },
      { field: 'user_code', title: '工号' },
      { field: 'employee_id', title: '员工ID' },
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
                tableName: 'v_vben_t_sys_user_role',
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

watch(() => props.currentRoleId, () => gridApi.query());

// 弹窗
const [FormUserModal, formUserModalApi] = useVbenModal({
  connectedComponent: formModelAddUser,
});

function openAddUserFormModal() {
  if (!props.currentRoleId) {
    message.warning('请先选择一个角色');
    return;
  }
  formUserModalApi
    .setData({
      values: {
        role_id: props.currentRoleId,
        onSuccess: () => gridApi.query(),
      },
    })
    .open();
}
</script>

<template>
  <div>
    <Button type="primary" @click="openAddUserFormModal">新增</Button>
    <Button danger>删除</Button>
    <Grid />
    <FormUserModal />
  </div>
</template>
