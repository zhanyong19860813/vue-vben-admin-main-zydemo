<script setup lang="ts">
import { reactive, ref } from 'vue';
import { ColPage } from '@vben/common-ui';
import { Card, Tabs } from 'ant-design-vue';

import RoleTree from './RoleTree.vue';
import UserList from './UserList.vue';
import MenuList from './MenuList.vue';

const props = reactive({
  leftCollapsedWidth: 5,
  leftCollapsible: true,
  leftMaxWidth: 50,
  leftMinWidth: 20,
  leftWidth: 30,
  resizable: true,
  rightWidth: 70,
  splitHandle: true,
  splitLine: true,
});

const currentRoleId = ref<string>();
const currentRoleName = ref<string>();

function handleRoleChange(id: string, name: string) {
  currentRoleId.value = id;
  currentRoleName.value = name;
}
</script>

<template>
  <ColPage v-bind="props" auto-content-height>
    <template #left>
      <RoleTree @change="handleRoleChange" />
    </template>

    <div class="ml-1 flex h-full flex-col">
      <Card
        class="h-full flex flex-1 flex-col !border-border"
        :body-style="{
          flex: 1,
          minHeight: 0,
          display: 'flex',
          flexDirection: 'column',
        }"
      >
        <Tabs
          class="flex flex-1 flex-col [&_.ant-tabs-content]:flex-1 [&_.ant-tabs-tabpane]:h-full"
        >
        <Tabs.TabPane key="user" tab="用户列表">
          <UserList
            :currentRoleId="currentRoleId"
            :currentRoleName="currentRoleName"
          />
        </Tabs.TabPane>

        <Tabs.TabPane key="menu" tab="菜单权限" force-render>
          <MenuList :currentRoleId="currentRoleId" />
        </Tabs.TabPane>
      </Tabs>
    </Card>
    </div>
  </ColPage>
</template>
