<script setup lang="ts">
import { computed, ref, onMounted } from 'vue';
import { Button, Modal, message } from 'ant-design-vue';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import type { QueryTableSchema } from './types';

const props = defineProps<{
  schema: QueryTableSchema;
}>();



const modalModules = import.meta.glob(
  '/src/views/dynamic-modals/**/*.vue'
);
// 模态框栈（示例，实际使用中可根据需要实现更复杂的模态管理）
const modalStack = ref<any[]>([]);

// 打开模态框（示例函数，实际使用中可根据需要传入更多参数）
// function openModal(options: any) {
//   modalStack.value.push({
//     id: Date.now() + Math.random(),
//     ...options,
//   });
// }
// 打开模态框（示例函数，实际使用中可根据需要传入更多参数）
async function openModal(options: any) {
  const fullPath = `/src/views/dynamic-modals/${options.component}.vue`;

  const loader = modalModules[fullPath];
  if (!loader) {
    console.error('未找到弹框组件:', fullPath);
    return;
  }

  const mod: any = await loader();

  modalStack.value.push({
    id: Date.now() + Math.random(),
    component: mod.default,
    props: options.props || {},
  });
}

// 关闭模态框 （示例函数，实际使用中可根据需要实现更复杂的关闭逻辑）
function closeModal(id: string) {
  modalStack.value = modalStack.value.filter(m => m.id !== id);
}

/**
 * 1️⃣ 初始化 Grid
 */
const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    ...props.schema.grid,
    proxyConfig: props.schema.grid?.proxyConfig,
  },
  formOptions: props.schema.form,
});

/**
 * 2️⃣ schema 中定义的 toolbar actions
 */
const toolbarActions = computed(() => {
  return props.schema.toolbar?.actions ?? [];
});

/**
 * 3️⃣ 动态 action handlers（来自 schema.actionModule）
 */
const actionHandlers = ref<Record<string, Function>>({});

onMounted(async () => {
  if (!props.schema.actionModule) return;

  try {
    const mod = await import(
      /* @vite-ignore */ props.schema.actionModule
    );
    actionHandlers.value = mod.default || {};
  } catch (err) {
    console.error('加载 actionModule 失败:', err);
  }
});

/**
 * 4️⃣ 构建 action 上下文
 */
const buildActionContext = () => ({
  gridApi,
  schema: props.schema,
  openModal,
});

/**
 * 5️⃣ toolbar 点击分发
 */
const handleToolbarClick = async (btn: any) => {
  const ctx = buildActionContext();

  // 1️⃣ 优先执行 schema.actionModule 中定义的 action
  const customAction = actionHandlers.value?.[btn.action];
  if (customAction) {
    await customAction(ctx);
    return;
  }

  // 2️⃣ 内置兜底 action
  switch (btn.action) {
    case 'add':
      message.info('内置新增（未定义自定义 add）');
      return;

    case 'reload':
      gridApi.reload();
      return;

    case 'deleteSelected': {
      const rows = gridApi.grid?.getCheckboxRecords?.() || [];
      if (!rows.length) {
        message.warning('请选择数据');
        return;
      }

      if (btn.confirm) {
        Modal.confirm({
          title: btn.confirm,
          onOk: () => {
            message.success(`删除 ${rows.length} 条（内置示例）`);
            gridApi.reload();
          },
        });
      }
      return;
    }
  }

  // 3️⃣ 仍然没找到
  console.warn(`未找到 action 处理器: ${btn.action}`);
};

/**
 * 向外暴露 gridApi（给 slot / 父组件）
 */
defineExpose({
  gridApi,
});
</script>

<template>

   <component
  v-for="modal in modalStack"
  :key="modal.id"
  :is="modal.component"
  v-bind="modal.props"
  @close="closeModal(modal.id)"
/>

  <Grid :table-title="schema.title">
    <!-- 🔥 ① schema 配置的 toolbar 按钮 -->
    <template #toolbar-tools>
      <div class="query-table-toolbar">
        <!-- 左侧：schema 定义的按钮 -->
        <div class="toolbar-left">
          <Button
            v-for="btn in toolbarActions"
            :key="btn.key"
            :type="btn.type || 'default'"
            class="mr-2"
            @click="handleToolbarClick(btn)"
          >
            {{ btn.label }}
          </Button>
        </div>

        <!-- 右侧：页面 / 外部 slot -->
        <div class="toolbar-right">
          <slot name="toolbar-tools" :gridApi="gridApi" />
        </div>
      </div>
    </template>
  </Grid>
</template>

<style scoped>
.query-table-toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.toolbar-left,
.toolbar-right {
  display: flex;
  align-items: center;
}
</style>
