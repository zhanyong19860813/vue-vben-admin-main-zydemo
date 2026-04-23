<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { Button, Card, Divider, Input, Modal, Spin, Tree, message } from 'ant-design-vue';
import type { DataNode } from 'ant-design-vue/es/tree';
import type { Key } from 'ant-design-vue/es/_util/type';

import { queryForVben, whereAnd } from './orgPickerQuery';
import type { OrgDeptManagerItem } from './types';

const props = withDefaults(
  defineProps<{
    open: boolean;
    title?: string;
    defaultCheckedDeptIds?: string[];
    onlyActive?: boolean;
    maxDepartments?: number;
  }>(),
  {
    title: '选择部门主管范围',
    defaultCheckedDeptIds: () => [],
    onlyActive: true,
    maxDepartments: 8000,
  },
);

const emit = defineEmits<{
  'update:open': [boolean];
  confirm: [items: OrgDeptManagerItem[]];
}>();

type FlatDept = {
  id: string;
  parentId: string | null;
  name: string;
  managerEmpIds: string[];
  managerNames: string[];
};

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
  const map = new Map<string, DataNode>();
  for (const n of nodes) {
    const mgr = n.managerNames.length ? n.managerNames.join('、') : '未维护主管';
    map.set(n.id, { key: n.id, title: `${n.name}（主管：${mgr}）`, children: [] });
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
      if (title.includes(k) || childFiltered.length) out.push({ ...n, children: childFiltered });
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
    body.TableName = 'v_t_base_department';
    body.QueryField = 'id,parent_id,name,manager,managerName,replacemanager,replacemanagerName';
    const rows = await queryForVben(body);
    flatList.value = (rows ?? []).map((r: any) => ({
      id: String(pick(r, 'id', 'ID') ?? ''),
      parentId: pick(r, 'parent_id', 'parent_ID') == null ? null : String(pick(r, 'parent_id', 'parent_ID')),
      name: String(pick(r, 'name', 'NAME') ?? ''),
      managerEmpIds: (() => {
        const mgr = String(pick(r, 'manager', 'Manager') ?? '').trim();
        const repl = String(pick(r, 'replacemanager', 'ReplaceManager') ?? '').trim();
        const src = mgr || repl;
        return src.split(',').map((x: string) => x.trim()).filter(Boolean);
      })(),
      managerNames: (() => {
        const mgr = String(pick(r, 'managerName', 'ManagerName') ?? '').trim();
        const repl = String(pick(r, 'replacemanagerName', 'ReplaceManagerName') ?? '').trim();
        const src = mgr || repl;
        return src.split(',').map((x: string) => x.trim()).filter(Boolean);
      })(),
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
  checkedKeys.value = Array.isArray(keys) ? keys.map(String) : (keys.checked ?? []).map(String);
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
  const items: OrgDeptManagerItem[] = flatList.value
    .filter((d) => set.has(d.id))
    .map((d) => ({
      deptId: d.id,
      deptName: d.name,
      parentId: d.parentId,
      managerEmpIds: d.managerEmpIds,
      managerNames: d.managerNames,
    }));
  emit('confirm', items);
  emit('update:open', false);
}

watch(
  () => props.open,
  (v) => {
    if (!v) return;
    nameKw.value = '';
    checkedKeys.value = [...props.defaultCheckedDeptIds];
    void loadDepartments();
  },
);
</script>

<template>
  <Modal :open="open" :title="title" width="560px" destroy-on-close :footer="null" @cancel="close">
    <Card size="small" :bordered="false" class="mb-3">
      <div class="flex items-center gap-2">
        <span class="text-xs text-muted-foreground">部门名称</span>
        <Input v-model:value="nameKw" allow-clear class="max-w-[280px]" />
        <Button size="small" type="primary" @click="expandFiltered">查询</Button>
      </div>
    </Card>
    <Card size="small">
      <template #extra>多选部门范围</template>
      <Spin :spinning="loading">
        <div class="max-h-[420px] overflow-auto">
          <Tree
            v-if="displayTree.length"
            v-model:expanded-keys="expandedKeys"
            checkable
            :check-strictly="true"
            :tree-data="displayTree"
            :checked-keys="checkedKeys"
            block-node
            show-line
            @check="onCheck"
          />
          <div v-else class="py-8 text-center text-sm text-muted-foreground">暂无部门</div>
        </div>
      </Spin>
    </Card>
    <Divider class="!my-4" />
    <div class="flex justify-end gap-3">
      <Button @click="close">取消</Button>
      <Button type="primary" @click="onConfirm">确定</Button>
    </div>
  </Modal>
</template>

