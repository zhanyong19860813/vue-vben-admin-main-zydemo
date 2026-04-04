<script setup lang="ts">
/**
 * 通用「选择部门」：树多选 + 名称筛选（对齐老系统：名称 + 查询 + 确定/取消）
 */
import { computed, ref, watch } from 'vue';
import { Button, Card, Divider, Input, Modal, Spin, Tree, message } from 'ant-design-vue';
import type { DataNode } from 'ant-design-vue/es/tree';
import type { Key } from 'ant-design-vue/es/_util/type';

import { queryForVben, whereAnd } from './orgPickerQuery';
import type { OrgDeptItem } from './types';

const props = withDefaults(
  defineProps<{
    open: boolean;
    /** 进入时勾选的部门 id */
    defaultCheckedIds?: string[];
    title?: string;
    /** 仅未停用部门（t_base_department.is_stop = 0） */
    onlyActive?: boolean;
    /** 单次拉取上限 */
    maxDepartments?: number;
  }>(),
  {
    defaultCheckedIds: () => [],
    title: '选择部门',
    onlyActive: true,
    maxDepartments: 8000,
  },
);

const emit = defineEmits<{
  'update:open': [boolean];
  confirm: [items: OrgDeptItem[]];
}>();

type FlatDept = { id: string; parentId: string | null; name: string };

const loading = ref(false);
const nameKw = ref('');
const treeData = ref<DataNode[]>([]);
const flatList = ref<FlatDept[]>([]);
const checkedKeys = ref<string[]>([]);
const expandedKeys = ref<string[]>([]);

function pick(row: any, ...keys: string[]) {
  for (const k of keys) {
    if (row[k] !== undefined && row[k] !== null) return row[k];
  }
  return undefined;
}

function listToTree(nodes: FlatDept[]): DataNode[] {
  const map = new Map<string, DataNode & { rawParent?: string | null }>();
  for (const n of nodes) {
    map.set(n.id, {
      key: n.id,
      title: n.name,
      children: [],
      rawParent: n.parentId,
    });
  }
  const roots: DataNode[] = [];
  for (const n of nodes) {
    const node = map.get(n.id)!;
    const pid = n.parentId;
    if (pid && map.has(pid)) {
      (map.get(pid)!.children as DataNode[]).push(node);
    } else {
      roots.push(node);
    }
  }
  return roots;
}

function filterTree(nodes: DataNode[], kw: string): DataNode[] {
  const k = kw.trim().toLowerCase();
  if (!k) return nodes;
  const walk = (list: DataNode[]): DataNode[] => {
    const out: DataNode[] = [];
    for (const n of list) {
      const title = String(n.title ?? '').toLowerCase();
      const children = (n.children as DataNode[] | undefined) ?? [];
      const childFiltered = walk(children);
      const match = title.includes(k);
      if (match || childFiltered.length) {
        out.push({ ...n, children: childFiltered });
      }
    }
    return out;
  };
  return walk(nodes);
}

const displayTree = computed(() => filterTree(treeData.value, nameKw.value));

async function loadDepartments() {
  loading.value = true;
  try {
    const body: Record<string, any> = {
      TableName: 't_base_department',
      Page: 1,
      PageSize: props.maxDepartments,
      SortBy: 'sort',
      SortOrder: 'asc',
    };
    if (props.onlyActive) {
      body.Where = whereAnd([{ Field: 'is_stop', Operator: 'eq', Value: '0' }]);
    }
    const items = await queryForVben(body);
    const rows = items ?? [];
    flatList.value = rows.map((r: any) => ({
      id: String(pick(r, 'id', 'ID') ?? ''),
      parentId: pick(r, 'parent_id', 'parent_ID', 'Parent_id') == null ? null : String(pick(r, 'parent_id', 'parent_ID', 'Parent_id')),
      name: String(pick(r, 'name', 'NAME') ?? ''),
    }));
    treeData.value = listToTree(flatList.value);
    expandedKeys.value = flatList.value.slice(0, 30).map((x) => x.id);
  } catch (e: any) {
    message.error(e?.message || '加载部门失败');
    treeData.value = [];
    flatList.value = [];
  } finally {
    loading.value = false;
  }
}

function onCheck(keys: Key[] | { checked: Key[]; halfChecked?: Key[] }) {
  if (Array.isArray(keys)) checkedKeys.value = keys.map(String);
  else checkedKeys.value = (keys.checked ?? []).map(String);
}

function expandFiltered() {
  const acc: string[] = [];
  const walk = (nodes: DataNode[]) => {
    for (const n of nodes) {
      acc.push(String(n.key));
      if (n.children?.length) walk(n.children as DataNode[]);
    }
  };
  walk(displayTree.value);
  expandedKeys.value = acc;
}

function close() {
  emit('update:open', false);
}

function onConfirm() {
  const set = new Set(checkedKeys.value);
  const items: OrgDeptItem[] = flatList.value
    .filter((d) => set.has(d.id))
    .map((d) => ({ id: d.id, name: d.name, parentId: d.parentId }));
  emit('confirm', items);
  emit('update:open', false);
}

watch(
  () => props.open,
  (v) => {
    if (!v) return;
    nameKw.value = '';
    checkedKeys.value = [...(props.defaultCheckedIds ?? [])];
    void loadDepartments();
  },
);
</script>

<template>
  <Modal
    :open="open"
    :title="title"
    width="540px"
    destroy-on-close
    :footer="null"
    @cancel="close"
  >
    <Card size="small" :bordered="false" class="odm-filter mb-3">
      <div class="flex flex-wrap items-center gap-2">
        <span class="odm-label">名称</span>
        <Input v-model:value="nameKw" allow-clear class="odm-input" placeholder="筛选部门名称" />
        <Button type="primary" size="small" @click="expandFiltered">查询</Button>
      </div>
    </Card>
    <Card size="small" class="odm-tree-card" :bordered="true">
      <template #title>
        <span class="odm-card-title">部门结构</span>
      </template>
      <template #extra>
        <span class="odm-extra">多选</span>
      </template>
      <Spin :spinning="loading">
        <div class="odm-tree-wrap">
          <Tree
            v-if="displayTree.length"
            v-model:expanded-keys="expandedKeys"
            checkable
            class="odm-tree"
            :check-strictly="true"
            :tree-data="displayTree"
            :checked-keys="checkedKeys"
            block-node
            show-line
            @check="onCheck"
          />
          <div v-else class="odm-empty">暂无部门数据</div>
        </div>
      </Spin>
    </Card>
    <Divider class="!my-4" />
    <div class="flex justify-end gap-3">
      <Button @click="close">取消</Button>
      <Button type="primary" class="odm-ok" @click="onConfirm">确定</Button>
    </div>
  </Modal>
</template>

<style scoped>
.odm-filter {
  background: linear-gradient(135deg, hsl(var(--muted) / 0.4) 0%, hsl(var(--card)) 100%);
  border-radius: 8px;
  border: 1px solid hsl(var(--border)) !important;
}

.odm-filter :deep(.ant-card-body) {
  padding: 10px 12px;
}

.odm-label {
  font-size: 13px;
  font-weight: 500;
  color: hsl(var(--muted-foreground));
}

.odm-input {
  flex: 1;
  min-width: 180px;
  max-width: 280px;
}

.odm-tree-card {
  border-radius: 8px;
  box-shadow: 0 1px 2px hsl(var(--foreground) / 0.04);
}

.odm-tree-card :deep(.ant-card-head) {
  min-height: 40px;
  padding: 0 12px;
  background: hsl(var(--muted) / 0.35);
  border-bottom: 1px solid hsl(var(--border));
}

.odm-tree-card :deep(.ant-card-body) {
  padding: 10px;
}

.odm-card-title {
  font-weight: 600;
  font-size: 13px;
  color: hsl(var(--foreground));
}

.odm-extra {
  font-size: 12px;
  color: hsl(var(--muted-foreground));
}

.odm-tree-wrap {
  max-height: 400px;
  overflow: auto;
}

.odm-tree :deep(.ant-tree) {
  font-size: 13px;
}

.odm-empty {
  padding: 36px 8px;
  text-align: center;
  font-size: 13px;
  color: hsl(var(--muted-foreground));
}

.odm-ok {
  min-width: 88px;
}
</style>
