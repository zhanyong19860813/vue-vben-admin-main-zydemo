  <script setup lang="ts">
import { ref } from 'vue';
import { Tabs, Card } from 'ant-design-vue';

const activeKey = ref('user');
</script>

<template>
  <Card title="页面内多页签示例">
    <Tabs v-model:activeKey="activeKey">
      <!-- Tab 1 -->
      <Tabs.TabPane key="user" tab="用户列表">
        <div class="p-2">
          这里是【用户列表】内容
        </div>
      </Tabs.TabPane>

      <!-- Tab 2 -->
      <Tabs.TabPane key="role" tab="角色列表">
        <div class="p-2">
          这里是【角色列表】内容
        </div>
      </Tabs.TabPane>
    </Tabs>
  </Card>
</template>
