<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { Tree as ATree, Button, message } from 'ant-design-vue';
import { requestClient } from '#/api/request';
import { useVbenModal } from '@vben/common-ui';

import AddRoleFormModel from './AddRole.vue';

const emit = defineEmits<{
  (e: 'change', id: string, name: string): void;
}>();

// ================== 树数据 ==================
const roleTreeDatas = ref<any[]>([]);
const expandedKeys = ref<string[]>([]);

const currentRoleId = ref<string>();
const currentRoleName = ref<string>();

// ================== 加载树 ==================
const loadTree = async () => {
  const res = await requestClient.get(
    'http://localhost:5155/api/QueryTreeData/tree'
  );
  roleTreeDatas.value = res;
  expandedKeys.value = res.map((n: any) => n.key);
};

onMounted(loadTree);

// ================== 展开事件（保持原样） ==================
const handleExpand = (keys: string[]) => {
  expandedKeys.value = keys;
};

// ================== 选中节点事件（⚠️完全保持原结构） ==================
const handleSelect = async (selectedKeys: string[], info: any) => {
  if (!selectedKeys || !selectedKeys.length) return;

  currentRoleId.value = selectedKeys[0];
  currentRoleName.value = info.node.title;

  // 原来这里是 gridApi.query()
  // 拆分后改为通知父组件
  emit('change', currentRoleId.value, currentRoleName.value);
};

// ================== 新增角色 ==================
const [FormModal, formModalApi] = useVbenModal({
  connectedComponent: AddRoleFormModel,
});

function openAddRoleFormModal() {
  if (!currentRoleId.value) {
    message.warning('请先选择一个角色');
    return;
  }

  formModalApi
    .setData({
      values: {
        parent_id: currentRoleId.value,
        ParentName: currentRoleName.value,
        onSuccess: loadTree,
      },
    })
    .open();
}

// ================== 删除角色 ==================
async function roleDelete() {
  if (!currentRoleId.value) {
    message.error('请先选择一个角色');
    return;
  }

  await requestClient.post(
    'http://localhost:5155/api/DataBatchDelete/BatchDelete',
    [
      {
        tablename: 'vben_role',
        key: 'id',
        Keys: [currentRoleId.value],
      },
    ],
    { headers: { 'Content-Type': 'application/json' } }
  );

  message.success('删除成功');
  currentRoleId.value = undefined;
  currentRoleName.value = undefined;
  await loadTree();
}
</script>

<template>
  <div
    class="mr-2 rounded-[var(--radius)] border border-border bg-card p-2"
    style="min-width: 250px; height: 600px"
  >
    <!-- 操作按钮 -->
    <div class="mb-2 font-bold text-lg">
      <Button class="mr-1" type="primary" @click="openAddRoleFormModal">
        新增
      </Button>
      <Button danger @click="roleDelete">删除</Button>
    </div>

    <!-- 角色树（事件参数与原来一致） -->
    <ATree
      :tree-data="roleTreeDatas"
      default-expand-all
      :expanded-keys="expandedKeys"
      @expand="handleExpand"
      @select="handleSelect"
    />

    <FormModal />
  </div>
</template>
