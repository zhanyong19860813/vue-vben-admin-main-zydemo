<script setup lang="ts">
import { ref, watch } from 'vue';
import { Button, Tabs, message } from 'ant-design-vue';
import { useVbenModal } from '@vben/common-ui';
import { useVbenForm } from '#/adapter/form';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import type { VxeGridProps } from '#/adapter/vxe-table';
import type { VbenFormSchema } from '#/adapter/form';
import type { TabTableItem } from './types';

export type { TabTableItem };

export interface FormTabsTableModalProps {
  /** 表单 schema */
  formSchema?: VbenFormSchema[];
  /** 页签配置，每个页签包含表格配置 */
  tabs?: TabTableItem[];
}

const props = withDefaults(defineProps<FormTabsTableModalProps>(), {
  formSchema: () => [],
  tabs: () => [],
});

const emit = defineEmits<{
  success: [values: Record<string, any>];
  cancel: [];
}>();

const activeKey = ref('');
const currentFormSchema = ref<VbenFormSchema[]>([]);
const currentTabs = ref<TabTableItem[]>([]);

/**
 * Modal
 */
const [Modal, modalApi] = useVbenModal({
  onOpenChange(isOpen) {
    if (!isOpen) return;

    const data = modalApi.getData() || {};
    if (data.title) modalApi.setState({ title: data.title });
    currentFormSchema.value = data.formSchema ?? props.formSchema;
    currentTabs.value = data.tabs ?? props.tabs;

    formApi.setState({ schema: currentFormSchema.value });

    if (currentTabs.value.length > 0) {
      activeKey.value = currentTabs.value[0].key;
      gridApi.setState({ gridOptions: currentTabs.value[0].gridOptions });
    }
  },
});

/**
 * 表单
 */
const [Form, formApi] = useVbenForm({
  showDefaultActions: false,
  schema: props.formSchema,
  wrapperClass: 'grid-cols-1 md:grid-cols-2',
  layout: 'horizontal',
  labelAlign: 'right',
  labelWidth: 100,
});

/**
 * 表格（随页签切换更新配置）
 */
const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    columns: [],
    data: [],
    pagerConfig: { enabled: true, pageSize: 10 },
  },
});

// 切换页签时更新表格配置
watch(activeKey, (key) => {
  const tab = currentTabs.value.find((t) => t.key === key);
  if (tab) {
    gridApi.setState({ gridOptions: tab.gridOptions });
  }
});

async function handleSubmit() {
  try {
    const values = await formApi.validate();
    emit('success', values);
    modalApi.close();
    message.success('提交成功');
  } catch {
    // 校验失败，不关闭
  }
}

function handleCancel() {
  emit('cancel');
  modalApi.close();
}

defineExpose({
  open: modalApi.open,
  close: modalApi.close,
  setData: modalApi.setData,
});
</script>

<template>
  <Modal class="w-[900px]" :fullscreen-button="false">
    <div class="form-tabs-table-modal p-5">
      <!-- 表单区域 -->
      <div v-if="currentFormSchema.length" class="mb-5">
        <Form />
      </div>

      <!-- 页签 + 表格 -->
      <div v-if="currentTabs.length">
        <Tabs v-model:activeKey="activeKey" type="card">
          <Tabs.TabPane
            v-for="tab in currentTabs"
            :key="tab.key"
            :tab="tab.tab"
          >
            <div class="py-3">
              <Grid />
            </div>
          </Tabs.TabPane>
        </Tabs>
      </div>

      <!-- 底部操作按钮 -->
      <div class="flex justify-end gap-2 mt-5 pt-4 border-t">
        <Button @click="handleCancel">取消</Button>
        <Button type="primary" @click="handleSubmit">确定</Button>
      </div>
    </div>
  </Modal>
</template>

<style scoped>
.form-tabs-table-modal {
  min-height: 200px;
}
</style>
