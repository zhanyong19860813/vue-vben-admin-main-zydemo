<script setup lang="ts">
import { Alert } from 'ant-design-vue';

import QueryTable from '#/components/QueryTable/index.vue';

import { hrmBlacklistSchema } from './hrmBlacklist.schema';
</script>

<template>
  <div class="p-4">
    <Alert
      class="mb-4"
      message="老系统迁移联调"
      type="info"
      show-icon
    >
      <template #description>
        对应老系统菜单「人事管理应用黑名单」，实体
        <code>v_HRMBlacklist</code>
        ；列配置来自库表
        <code>t_set_datagrid</code>
        。若列表无数据或报错，请确认 StoneApi 已开放该视图查询。
      </template>
    </Alert>
    <QueryTable :schema="hrmBlacklistSchema" />
  </div>
</template>
