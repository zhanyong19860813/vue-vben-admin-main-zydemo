<script setup lang="ts">
import { Button, message } from 'ant-design-vue';
import QueryTable from '#/components/QueryTable/index.vue';
import { companySchema } from './company.schema';

const handleAdd = () => {
  message.success('新增按钮点击');
};

const handleCustom = (gridApi: any) => {
  const rows = gridApi.grid?.getCheckboxRecords();
  message.success(`选中 ${rows.length} 条`);
};
</script>

<template>
  <QueryTable :schema="companySchema">
    <template #toolbar-extra="{ gridApi }">
      <Button class="ml-2" @click="handleAdd">
        新增
      </Button>

      <Button class="ml-2" @click="handleCustom(gridApi)">
        自定义操作
      </Button>
    </template>
  </QueryTable>
</template>
