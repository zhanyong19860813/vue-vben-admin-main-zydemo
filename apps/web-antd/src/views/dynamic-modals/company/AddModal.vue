<script setup lang="ts">
import { defineEmits, defineProps } from 'vue';
import { Button } from 'ant-design-vue';

const props = defineProps<{
  title: string;
  mode: string;
  typestr: string;
  testnum: string;
  aabb: string;
  demonum: Number;
  selectedRows: any[];
}>();

const emit = defineEmits(['success', 'cancel']);

function handleOk() {
  // 传递 success  可以刷新父窗口的列表
  emit('success', { message: '新增成功', data: "测试传递给父窗口的数据" });
}

function handleCancel() {
  emit('cancel');
}
</script>

<template>
  <div class="modal-content">
    <p>模式：{{ props.mode }}</p>
    <p>类型：{{ props.typestr }}</p>
    <p>测试数字：{{ props.testnum }}</p>
    <p>测试aabb：{{ props.aabb }}</p>
    <p>测试demonum：{{ props.demonum }}</p>
    <p>选中的行数：{{ props.selectedRows.length }}</p>

    <div class="button-container">
      <Button type="primary" @click="handleOk">保存</Button>
      <Button style="margin-left: 10px" @click="handleCancel">取消</Button>
    </div>
  </div>
</template>

<style scoped>
.modal-content {
  display: flex;
  flex-direction: column;
  gap: 10px;
  position: relative; /* 保证内部内容可以相对于这个容器定位 */
  min-height: 300px; /* 确保容器有足够的高度，可以调整 */
}

.button-container {
  display: flex;
  justify-content: flex-end; /* 右对齐 */
  gap: 10px;
  position: absolute;
  bottom: 20px; /* 距离底部20px */
  right: 20px;  /* 距离右边20px */
}
</style>
