<script setup lang="ts">
import { Button, message } from 'ant-design-vue';
import QueryTable from '#/components/QueryTable/index.vue';
import { companySchema } from './company.schema';

import { employeeSchema } from './employee.schema';
import { useRoute } from 'vue-router';
 import { computed } from 'vue';
const handleAdd = () => {
  message.success('新增按钮点击');
};

const handleCustom = (gridApi: any) => {
  const rows = gridApi.grid?.getCheckboxRecords();
  message.success(`选中 ${rows.length} 条`);
};


const route = useRoute();
//const entityName = route.query.entityname as string;

//console.log('当前实体:route', route);
//const entityName = route.meta.entityname as string
const entityName = computed(() => {
  // 你现在是从 meta.query 拿，这是对的
  return route.meta.query?.entityname as string;
});

const currentSchema = computed(() => {

  console.log('当前实体:entityName', entityName.value);
  switch (entityName.value) {
    case 'company':
      return companySchema;
    case 'user':
      return companySchema;
    case 'car':
      return employeeSchema;
    default:
      return employeeSchema; // 兜底
  }
});

 
console.log('当前实体:route.meta', route.meta);
console.log('当前实体 参数:', route.meta.query?.entityname);
</script>

<template>
  <QueryTable :schema="currentSchema">
    <template #toolbar-extra="{ gridApi }">
      <Button class="ml-2" @click="handleAdd">
        新增code
      </Button>
      <Button class="ml-2" @click="handleCustom(gridApi)">
        自定义code
      </Button>
    </template>
  </QueryTable>
</template>
