<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import { Button, message } from 'ant-design-vue';
import QueryTable from '#/components/QueryTable/index.vue';
import { companySchema } from './company.schema';
import { employeeSchema } from './employee.schema';
import { useRoute } from 'vue-router';
import { requestClient } from '#/api/request';
 

// 按钮事件
const handleAdd = () => {
  message.success('新增按钮点击');
};
const handleCustom = (gridApi: any) => {
  const rows = gridApi.grid?.getCheckboxRecords();
  message.success(`选中 ${rows.length} 条`);
};

// 路由相关
const route = useRoute();

// 1. 计算属性获取实体名称
const entityName = computed(() => {
  return route.meta.query?.entityname as string;
});

// 2. 定义响应式变量存储后端返回的 schema
const remoteSchema = ref(null);
// 可选：添加加载状态，方便UI显示
const isLoading = ref(false);
// 可选：添加错误状态
const error = ref(null);


// 3. 监听 entityName 变化，请求后端接口
watch(
  () => entityName.value,
  async (newEntityName) => {
    // 如果没有实体名称，清空远程 schema
    if (!newEntityName) {
      remoteSchema.value = null;
      return;
    }
    // 开始请求，设置加载状态
    isLoading.value = true;
    error.value = null;
    
    try {
      console.log('正在请求 schema，实体名称:', newEntityName);
      const res = await requestClient.get(
        'http://localhost:5155/api/VbenSchema/GetSchema',
        {
          params: { entityName: newEntityName }
        }
      );
      console.log('1请求到的 schema:', res);
      remoteSchema.value = res;
    } catch (err) {
      console.error('2请求 schema 失败:', err);
      //error.value = err;
      remoteSchema.value = null; // 请求失败时清空
      message.error(`获取 schema 失败`);
    } finally {
      isLoading.value = false;
    }
  },
  { 
    immediate: true // 立即执行一次，获取初始数据
  }
);
// 4. 最终的 schema：优先使用远程的，否则用本地兜底
const currentSchema = computed(() => {
  // 如果有远程 schema，直接返回
  if (remoteSchema.value) {
    console.log('3使用远程 schema:', remoteSchema.value);
     
    console.log('4使用远程 schema.grid:', remoteSchema.grid);

    return remoteSchema.value;
  }
  // 否则根据实体名称返回本地兜底 schema
  console.log('5使用本地兜底 schema，实体名称:', entityName.value);
  switch (entityName.value) {
    case 'company':
      return companySchema;
    case 'user':
      return companySchema; // user 也使用 companySchema
    case 'car':
      return employeeSchema;
    default:
      return employeeSchema; // 默认使用 employeeSchema
  }
});
</script>
<template>
 <div v-if="isLoading" style="padding: 20px; text-align: center;">
    正在加载 Schema...
  </div>
  <div v-else-if="error" style="padding: 20px; text-align: center; color: #ff4d4f;">
    加载失败：{{ error.message || '未知错误' }}
  </div>  
    <QueryTable     :schema="currentSchema">
     <template #toolbar-tools="{ gridApi }">
      <Button @click="handleAdd">新增 code</Button>
      <Button @click="handleCustom(gridApi)">自定义 code</Button>
    </template>  
  </QueryTable> 
</template>
