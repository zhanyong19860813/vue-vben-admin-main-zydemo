<template>
  <div class="p-4">
    <h2>简单表格示例</h2>
    <a-table :columns="columns" :data-source="data" row-key="id" />
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';

const columns = [
  { title: 'ID', dataIndex: 'id', key: 'id' },
  { title: '姓名', dataIndex: 'name', key: 'name' },
  { title: '年龄', dataIndex: 'age', key: 'age' },
];

const data = ref([
  { id: 1, name: '张三', age: 20 },
  { id: 2, name: '李四', age: 25 },
  { id: 3, name: '王五', age: 30 },
]);
</script>
