<script setup lang="ts">
/**
 * 纯内容组件，供 Modal.confirm 等动态弹窗使用
 * 不包含 useVbenModal，避免与路由/keep-alive 冲突
 * 支持数据字典：将 dataSourceType=dictionary 的字段解析为 options/treeData
 */
import { ref, watch } from 'vue';
import { Button, Tabs, message } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { resolveDictionaryInSchema } from '#/views/demos/form-designer/resolveDictionarySchema';
import type { TabTableItem } from './types';

const props = defineProps<{
  formSchema: any[];
  tabs: TabTableItem[];
}>();

const emit = defineEmits<{
  success: [values: Record<string, any>];
  cancel: [];
}>();

const activeKey = ref(props.tabs[0]?.key ?? '');
const resolvedFormSchema = ref<any[]>([]);

const [Form, formApi] = useVbenForm({
  showDefaultActions: false,
  schema: [],
  wrapperClass: 'grid-cols-1 md:grid-cols-2',
  layout: 'horizontal',
  labelAlign: 'right',
  labelWidth: 100,
});

watch(
  () => props.formSchema,
  async (schema) => {
    const raw = Array.isArray(schema) ? schema : [];
    const resolved = await resolveDictionaryInSchema(raw);
    resolvedFormSchema.value = resolved;
    formApi.setState({ schema: resolved });
  },
  { immediate: true, deep: true },
);

const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: props.tabs[0]?.gridOptions ?? {
    columns: [],
    data: [],
    pagerConfig: { enabled: true, pageSize: 10 },
  },
});

watch(activeKey, (key) => {
  const tab = props.tabs.find((t) => t.key === key);
  if (tab) {
    gridApi.setState({ gridOptions: tab.gridOptions });
  }
});

async function handleSubmit() {
  try {
    const values = await formApi.validate();
    emit('success', values);
    message.success('提交成功');
  } catch {
    // 校验失败
  }
}

function handleCancel() {
  emit('cancel');
}
</script>

<template>
  <div class="form-tabs-table-content p-5">
    <div v-if="formSchema.length" class="mb-5">
      <Form />
    </div>

    <div v-if="tabs.length">
      <Tabs v-model:activeKey="activeKey" type="card">
        <Tabs.TabPane v-for="tab in tabs" :key="tab.key" :tab="tab.tab">
          <div class="py-3">
            <Grid />
          </div>
        </Tabs.TabPane>
      </Tabs>
    </div>

    <div class="flex justify-end gap-2 mt-5 pt-4 border-t">
      <Button @click="handleCancel">取消</Button>
      <Button type="primary" @click="handleSubmit">确定</Button>
    </div>
  </div>
</template>

<style scoped>
.form-tabs-table-content {
  min-height: 200px;
}
</style>
