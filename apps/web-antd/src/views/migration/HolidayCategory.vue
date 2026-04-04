<script setup lang="ts">
import { Alert } from 'ant-design-vue';

import QueryTable from '#/components/QueryTable/index.vue';

import { holidayCategorySchema } from './holidayCategory.schema';
</script>

<template>
  <div class="p-4">
    <Alert
      class="mb-4"
      message="老系统：考勤管理 → 考勤基础资料 → 假别设定"
      type="info"
      show-icon
    >
      <template #description>
        实体
        <code>v_att_lst_HolidayCategory</code>
        ；列表列来自
        <code>t_set_datagrid</code>
        。老系统按钮：新增、删除、保存（行内编辑）；当前页仅做列表查询联调，后续可接
        <code>actionModule</code>
        。
      </template>
    </Alert>
    <QueryTable :schema="holidayCategorySchema" />
  </div>
</template>
