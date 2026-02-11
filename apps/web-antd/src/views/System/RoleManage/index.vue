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
  <ColPage v-bind="props">
    <template #left>
      <RoleTree @change="handleRoleChange" />
    </template>

    <Card class="ml-1" title="用户信息">
      <Tabs>
        <Tabs.TabPane key="user" tab="用户列表">
          <UserList
            :currentRoleId="currentRoleId"
            :currentRoleName="currentRoleName"
          />
        </Tabs.TabPane>

        <Tabs.TabPane key="menu" tab="菜单权限"   force-render>
          <MenuList :currentRoleId="currentRoleId" />
        </Tabs.TabPane>
      </Tabs>
    </Card>
  </ColPage>
</template>
