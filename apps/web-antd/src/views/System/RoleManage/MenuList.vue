<script setup lang="ts">
import { watch, nextTick } from 'vue';
import { Button, message } from 'ant-design-vue';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { requestClient } from '#/api/request';
import { useVbenModal } from '@vben/common-ui';

import formModelAddMenu from './form-model-AddMenu.vue';

// ================= props =================
const props = defineProps<{
  currentRoleId?: string;
}>();

// ================= 表格 =================
const [MenuGrid, gridMenuApi] = useVbenVxeGrid({
  gridOptions: {
    columns: [
      { type: 'checkbox', width: 60 },
      { type: 'seq', width: 50 },
      { field: 'id', title: 'ID' },
      { field: 'entity_name', title: '菜单名' },
      { field: 'meta', title: 'meta' },
      { field: 'url', title: '路径' },
      { field: 'bar_items', title: '按钮' },
    ],
    pagerConfig: {
      enabled: false,
    },
    proxyConfig: {
      // ✅ 明确告诉 vxe-grid：数据在哪
      props: {
        result: 'items',
        total: 'total',
      },
      ajax: {
        query: async () => {
          // role 未选中，返回空
          if (!props.currentRoleId) {
            return {
              items: [],
              total: 0,
            };
          }

          const res = await requestClient.get(
            'http://localhost:5155/api/DynamicQueryBeta/query',
            {
              params: {
                tableName: 'vben_v_role_menu',
                simpleWhere: {
                  role_id: props.currentRoleId,
                },
              },
            }
          );

          // 调试日志（可留）
          console.log('menu query res = ', res);

          // ⚠️ 关键：proxy 模式下，直接 return 后端结果
          return res;
        },
      },
    },
  },
});

// ================= 监听角色变化 =================
watch(
  () => props.currentRoleId,
  async (val) => {
    if (!val) return;

    // 等 Grid 完全就绪
    await nextTick();
    gridMenuApi.query();
  },
  { immediate: true }
);

// ================= 弹窗 =================
const [FormMenuModal, formMenuModalApi] = useVbenModal({
  connectedComponent: formModelAddMenu,
});

// 新增菜单
function openAddMenu() {
  if (!props.currentRoleId) {
    message.warning('请先选择一个角色');
    return;
  }

  formMenuModalApi
    .setData({
      values: {
        role_id: props.currentRoleId,
        onSuccess: () => {
          gridMenuApi.query();
        },
      },
    })
    .open();
}

// 删除菜单
async function deleteMenu() {
  const grid = gridMenuApi.grid;
  if (!grid) {
    message.error('表格未初始化');
    return;
  }

  const rows = grid.getCheckboxRecords();
  if (!rows.length) {
    message.warning('请先选择要删除的数据');
    return;
  }

  await requestClient.post(
    'http://localhost:5155/api/DataBatchDelete/BatchDelete',
    [
      {
        tablename: 'vben_t_sys_role_menus',
        key: 'id',
        Keys: rows.map((r: any) => r.id),
      },
    ],
    {
      headers: { 'Content-Type': 'application/json' },
    }
  );

  message.success('删除成功');
  gridMenuApi.query();
}
</script>

<template>
  <div class="p-2">
    <div class="mb-2 font-bold text-lg">
      <Button class="mr-1" type="primary" @click="openAddMenu">
        新增
      </Button>
      <Button danger @click="deleteMenu">
        删除
      </Button>
    </div>

    <MenuGrid />

    <FormMenuModal />
  </div>
</template>
