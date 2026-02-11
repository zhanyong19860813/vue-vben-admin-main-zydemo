<script setup lang="ts">
import { reactive, watch } from 'vue';
import { Form, Input, InputNumber, Select, Switch, Button } from 'ant-design-vue';
import type { FormSchema } from './form-types';

const props = defineProps<{
  schema: FormSchema;
}>();

const emit = defineEmits<{
  (e: 'submit', values: any): void;
}>();

// 表单数据
const formState = reactive<Record<string, any>>({});

// 初始化默认值
watch(
  () => props.schema,
  (schema) => {
    schema.fields.forEach((f) => {
      formState[f.field] = f.defaultValue ?? null;
    });
  },
  { immediate: true }
);

// 提交
function handleSubmit() {
  emit('submit', { ...formState });
}
</script>

<template>
  <Form layout="vertical">
    <Form.Item
      v-for="field in schema.fields"
      :key="field.field"
      :label="field.label"
      :required="field.required"
    >
      <!-- Input -->
      <Input
        v-if="field.component === 'Input'"
        v-model:value="formState[field.field]"
      />

      <!-- InputNumber -->
      <InputNumber
        v-else-if="field.component === 'InputNumber'"
        style="width: 100%"
        v-model:value="formState[field.field]"
      />

      <!-- Select -->
      <Select
        v-else-if="field.component === 'Select'"
        v-model:value="formState[field.field]"
        :options="field.options"
      />

      <!-- Switch -->
      <Switch
        v-else-if="field.component === 'Switch'"
        v-model:checked="formState[field.field]"
      />
    </Form.Item>

    <Button type="primary" @click="handleSubmit">
      提交
    </Button>
  </Form>
</template>
