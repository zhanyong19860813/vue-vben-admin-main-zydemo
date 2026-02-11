<script setup lang="ts">
// Make sure the path is correct; update if needed, for example:
import SchemaForm from '#/components/schema-form/SchemaForm.vue';

 
// or, if the file should be created, create 'src/components/schema-form/SchemaForm.vue'
import { menuFormSchema } from './menu-form-schema';

function handleSubmit(values: any) {
  console.log('提交的数据：', values);
}
</script>

<template>
  <SchemaForm
    :schema="menuFormSchema"
    @submit="handleSubmit"
  />
</template>
