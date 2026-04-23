<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { Button, Card, Divider, Input, Modal, Spin, Table, message } from 'ant-design-vue';
import type { Key } from 'ant-design-vue/es/_util/type';

import { queryForVbenPaged, whereAnd } from './orgPickerQuery';
import type { OrgRoleItem } from './types';

const props = withDefaults(
  defineProps<{
    open: boolean;
    title?: string;
    defaultSelectedIds?: string[];
    pageSize?: number;
  }>(),
  {
    title: '选择角色',
    defaultSelectedIds: () => [],
    pageSize: 50,
  },
);

const emit = defineEmits<{
  'update:open': [boolean];
  confirm: [items: OrgRoleItem[]];
}>();

const loading = ref(false);
const roleNameKw = ref('');
const rows = ref<any[]>([]);
const total = ref(0);
const page = ref(1);
const selectedKeys = ref<Key[]>([]);

const columns = [
  { title: '角色名称', dataIndex: 'name', key: 'name', ellipsis: true },
];

const selectedCount = computed(() => selectedKeys.value.length);

function close() {
  emit('update:open', false);
}

function buildWhere() {
  const conditions: Array<{ Field: string; Operator: string; Value: string }> = [];
  const kw = roleNameKw.value.trim();
  if (kw) conditions.push({ Field: 'name', Operator: 'contains', Value: kw });
  if (!conditions.length) return undefined;
  return whereAnd(conditions);
}

async function fetchRoles() {
  loading.value = true;
  try {
    const where = buildWhere();
    const { items, total: t } = await queryForVbenPaged({
      TableName: 'vben_role',
      Page: page.value,
      PageSize: props.pageSize,
      SortBy: 'name',
      SortOrder: 'asc',
      QueryField: 'id,name',
      ...(where ? { Where: where } : {}),
    });
    rows.value = items ?? [];
    total.value = t ?? 0;
  } catch (e: any) {
    message.error(e?.message || '加载角色失败');
    rows.value = [];
    total.value = 0;
  } finally {
    loading.value = false;
  }
}

function onSearch() {
  page.value = 1;
  void fetchRoles();
}

function onConfirm() {
  const set = new Set(selectedKeys.value.map(String));
  const items: OrgRoleItem[] = rows.value
    .filter((r: any) => set.has(String(r.id)))
    .map((r: any) => ({ id: String(r.id), name: String(r.name ?? '') }));
  emit('confirm', items);
  emit('update:open', false);
}

function onTablePageChange(p: number) {
  page.value = p;
  void fetchRoles();
}

function onRowSelectChange(keys: Key[]) {
  selectedKeys.value = keys;
}

watch(
  () => props.open,
  (v) => {
    if (!v) return;
    roleNameKw.value = '';
    page.value = 1;
    selectedKeys.value = [...props.defaultSelectedIds];
    void fetchRoles();
  },
);
</script>

<template>
  <Modal :open="open" :title="title" width="720px" destroy-on-close :footer="null" @cancel="close">
    <Card size="small" :bordered="false" class="mb-3">
      <div class="flex items-center gap-2">
        <span class="text-xs text-muted-foreground">角色名称</span>
        <Input v-model:value="roleNameKw" allow-clear class="max-w-[280px]" @press-enter="onSearch" />
        <Button size="small" type="primary" @click="onSearch">查询</Button>
      </div>
    </Card>
    <Card size="small">
      <template #extra>已选 {{ selectedCount }}</template>
      <Spin :spinning="loading">
        <Table
          size="small"
          :columns="columns"
          :data-source="rows"
          :pagination="{
            size: 'small',
            current: page,
            pageSize,
            total,
            showSizeChanger: false,
            showQuickJumper: true,
            onChange: onTablePageChange,
          }"
          :row-key="(r: any) => String(r.id)"
          :row-selection="{
            selectedRowKeys: selectedKeys,
            onChange: onRowSelectChange,
          }"
        />
      </Spin>
    </Card>
    <Divider class="!my-4" />
    <div class="flex justify-end gap-3">
      <Button @click="close">取消</Button>
      <Button type="primary" @click="onConfirm">确定</Button>
    </div>
  </Modal>
</template>

