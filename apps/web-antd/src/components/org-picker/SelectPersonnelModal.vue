<script setup lang="ts">
/**
 * 通用「选择人员」：左侧部门树 + 中间候选表 + 右侧已选 + 穿梭（对齐老系统交互）
 */
import { computed, ref, watch } from 'vue';
import type { TablePaginationConfig } from 'ant-design-vue';
import {
  Button,
  Card,
  Checkbox,
  Divider,
  Input,
  Modal,
  Spin,
  Table,
  Tag,
  Tree,
  message,
} from 'ant-design-vue';
import type { DataNode } from 'ant-design-vue/es/tree';
import type { Key } from 'ant-design-vue/es/_util/type';

import { queryForVben, queryForVbenPaged, whereAnd } from './orgPickerQuery';
import type { OrgPersonnelItem } from './types';

const OUTBOUND_TYPES = new Set(['派遣工', '业务外包', '承运商']);

const props = withDefaults(
  defineProps<{
    open: boolean;
    title?: string;
    /** 进入时已选人员 */
    defaultSelected?: OrgPersonnelItem[];
    onlyActiveDepartments?: boolean;
    candidatePageSize?: number;
  }>(),
  {
    title: '选择人员',
    defaultSelected: () => [],
    onlyActiveDepartments: true,
    candidatePageSize: 50,
  },
);

const emit = defineEmits<{
  'update:open': [boolean];
  confirm: [items: OrgPersonnelItem[]];
}>();

type FlatDept = { id: string; parentId: string | null; name: string };

function pick(row: any, ...keys: string[]) {
  for (const k of keys) {
    if (row[k] !== undefined && row[k] !== null) return row[k];
  }
  return undefined;
}

function listToTree(nodes: FlatDept[]): DataNode[] {
  const map = new Map<string, DataNode>();
  for (const n of nodes) {
    map.set(n.id, { key: n.id, title: n.name, children: [] });
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

function filterDeptTree(nodes: DataNode[], kw: string): DataNode[] {
  const k = kw.trim().toLowerCase();
  if (!k) return nodes;
  const walk = (list: DataNode[]): DataNode[] => {
    const out: DataNode[] = [];
    for (const n of list) {
      const title = String(n.title ?? '').toLowerCase();
      const children = (n.children as DataNode[] | undefined) ?? [];
      const cf = walk(children);
      if (title.includes(k) || cf.length) out.push({ ...n, children: cf });
    }
    return out;
  };
  return walk(nodes);
}

function rowToPerson(r: any): OrgPersonnelItem {
  const id = String(pick(r, 'id', 'ID') ?? '');
  const empId = String(pick(r, 'EMP_ID', 'emp_id', 'code') ?? '').trim();
  const name = String(pick(r, 'name', 'NAME') ?? '');
  return {
    id,
    empId,
    name,
    deptName: pick(r, 'longdeptname', 'Longdeptname') == null ? undefined : String(pick(r, 'longdeptname', 'Longdeptname')),
    dutyName: pick(r, 'dutyName', 'DutyName') == null ? undefined : String(pick(r, 'dutyName', 'DutyName')),
  };
}

const deptLoading = ref(false);
const deptNameKw = ref('');
const deptTreeRaw = ref<DataNode[]>([]);
const deptFlat = ref<FlatDept[]>([]);
const selectedDeptKeys = ref<string[]>([]);
const expandedDeptKeys = ref<string[]>([]);

const deptDisplayTree = ref<DataNode[]>([]);
watch([deptTreeRaw, deptNameKw], () => {
  deptDisplayTree.value = filterDeptTree(deptTreeRaw.value, deptNameKw.value);
});

const excludeResigned = ref(true);
const excludeOutbound = ref(false);
const personKw = ref('');

const listLoading = ref(false);
const candidateRows = ref<any[]>([]);
const candidateTotal = ref(0);
const candidatePage = ref(1);
const middleSelectedKeys = ref<Key[]>([]);

const chosen = ref<OrgPersonnelItem[]>([]);
const chosenSelectedKeys = ref<Key[]>([]);

const chosenCount = computed(() => chosen.value.length);

const selectedDeptLabel = computed(() => {
  const id = selectedDeptKeys.value[0];
  if (!id) return '未选';
  const d = deptFlat.value.find((x) => x.id === id);
  return d?.name?.trim() || '—';
});

async function loadDeptTree() {
  deptLoading.value = true;
  try {
    const body: Record<string, any> = {
      TableName: 't_base_department',
      Page: 1,
      PageSize: 8000,
      SortBy: 'sort',
      SortOrder: 'asc',
    };
    if (props.onlyActiveDepartments) {
      body.Where = whereAnd([{ Field: 'is_stop', Operator: 'eq', Value: '0' }]);
    }
    const items = await queryForVben(body);
    deptFlat.value = (items ?? []).map((r: any) => ({
      id: String(pick(r, 'id', 'ID') ?? ''),
      parentId: pick(r, 'parent_id', 'parent_ID') == null ? null : String(pick(r, 'parent_id', 'parent_ID')),
      name: String(pick(r, 'name', 'NAME') ?? ''),
    }));
    deptTreeRaw.value = listToTree(deptFlat.value);
    expandedDeptKeys.value = deptFlat.value.slice(0, 25).map((x) => x.id);
  } catch (e: any) {
    message.error(e?.message || '加载部门树失败');
    deptTreeRaw.value = [];
  } finally {
    deptLoading.value = false;
  }
}

function expandDeptFiltered() {
  const acc: string[] = [];
  const walk = (nodes: DataNode[]) => {
    for (const n of nodes) {
      acc.push(String(n.key));
      if (n.children?.length) walk(n.children as DataNode[]);
    }
  };
  walk(deptDisplayTree.value);
  expandedDeptKeys.value = acc;
}

function buildEmployeeWhere(): Record<string, any> | undefined {
  const deptId = selectedDeptKeys.value[0] ?? null;
  const kw = personKw.value.trim();
  /** 避免仅「在职」条件拉全库 */
  if (!deptId && !kw) return undefined;
  const parts: any[] = [];
  if (excludeResigned.value) {
    parts.push({ Field: 'leave_status', Operator: 'eq', Value: '0' });
  }
  if (deptId) {
    parts.push({ Field: 'dept_id', Operator: 'eq', Value: deptId });
  }
  if (kw) {
    return {
      Logic: 'AND',
      Conditions: parts,
      Groups: [
        {
          Logic: 'OR',
          Conditions: [
            { Field: 'name', Operator: 'contains', Value: kw },
            { Field: 'first_name', Operator: 'contains', Value: kw },
            { Field: 'EMP_ID', Operator: 'contains', Value: kw },
            { Field: 'code', Operator: 'contains', Value: kw },
          ],
          Groups: [],
        },
      ],
    };
  }
  if (!parts.length) return undefined;
  return { Logic: 'AND', Conditions: parts, Groups: [] };
}

async function fetchCandidates() {
  const w = buildEmployeeWhere();
  if (!w) {
    candidateRows.value = [];
    candidateTotal.value = 0;
    return;
  }
  listLoading.value = true;
  try {
    const { items, total } = await queryForVbenPaged({
      TableName: 'v_t_base_employee',
      Page: candidatePage.value,
      PageSize: props.candidatePageSize,
      SortBy: 'EMP_ID',
      SortOrder: 'asc',
      Where: w,
    });
    let rows = items ?? [];
    if (excludeOutbound.value) {
      rows = rows.filter((r: any) => !OUTBOUND_TYPES.has(String(pick(r, 'type', 'Type') ?? '')));
    }
    candidateRows.value = rows;
    candidateTotal.value = total;
  } catch (e: any) {
    message.error(e?.message || '加载人员失败');
    candidateRows.value = [];
    candidateTotal.value = 0;
  } finally {
    listLoading.value = false;
  }
}

function runPersonSearch() {
  candidatePage.value = 1;
  void fetchCandidates();
}

function onCandidatePaginationChange(pag: TablePaginationConfig) {
  if (pag.current) candidatePage.value = pag.current;
  void fetchCandidates();
}

function onMiddleSelectChange(keys: Key[]) {
  middleSelectedKeys.value = keys;
}

function onChosenSelectChange(keys: Key[]) {
  chosenSelectedKeys.value = keys;
}

function onDeptSelect(keys: Key[]) {
  selectedDeptKeys.value = keys.length ? [String(keys[0])] : [];
  candidatePage.value = 1;
  void fetchCandidates();
}

watch([excludeResigned, excludeOutbound], () => {
  if (!props.open) return;
  candidatePage.value = 1;
  void fetchCandidates();
});

function addToChosen() {
  const set = new Set(middleSelectedKeys.value.map(String));
  const add = candidateRows.value
    .filter((r) => set.has(String(pick(r, 'id', 'ID'))))
    .map(rowToPerson);
  const byId = new Map(chosen.value.map((p) => [p.id, p]));
  for (const p of add) {
    if (p.id) byId.set(p.id, p);
  }
  chosen.value = [...byId.values()];
  middleSelectedKeys.value = [];
}

function removeFromChosen() {
  const rm = new Set(chosenSelectedKeys.value.map(String));
  chosen.value = chosen.value.filter((p) => !rm.has(p.id));
  chosenSelectedKeys.value = [];
}

function clearChosen() {
  chosen.value = [];
  chosenSelectedKeys.value = [];
}

function close() {
  emit('update:open', false);
}

function onConfirm() {
  emit('confirm', [...chosen.value]);
  emit('update:open', false);
}

watch(
  () => props.open,
  (v) => {
    if (!v) return;
    deptNameKw.value = '';
    personKw.value = '';
    selectedDeptKeys.value = [];
    candidatePage.value = 1;
    candidateRows.value = [];
    candidateTotal.value = 0;
    middleSelectedKeys.value = [];
    chosen.value = (props.defaultSelected ?? []).map((x) => ({ ...x }));
    chosenSelectedKeys.value = [];
    void loadDeptTree();
  },
);

const middleColumns = [
  { title: '工号', dataIndex: 'EMP_ID', key: 'EMP_ID', width: 88, ellipsis: true },
  { title: '姓名', dataIndex: 'name', key: 'name', width: 90, ellipsis: true },
  { title: '部门', dataIndex: 'longdeptname', key: 'longdeptname', ellipsis: true },
  { title: '岗位', dataIndex: 'dutyName', key: 'dutyName', width: 100, ellipsis: true },
];

const chosenColumns = [
  { title: '工号', dataIndex: 'empId', key: 'empId', width: 88 },
  { title: '姓名', dataIndex: 'name', key: 'name', width: 90 },
];
</script>

<template>
  <Modal
    :open="open"
    :title="title"
    width="1120px"
    destroy-on-close
    :footer="null"
    @cancel="close"
  >
    <Card size="small" :bordered="false" class="opm-filter-card mb-3">
      <div class="opm-filter-rows flex flex-col gap-3">
        <div class="flex flex-wrap items-center gap-3">
          <span class="opm-field-label">部门名称</span>
          <Input
            v-model:value="deptNameKw"
            allow-clear
            class="opm-input-dept"
            placeholder="筛选组织树"
          />
          <Button type="primary" size="small" @click="expandDeptFiltered">查询</Button>
        </div>
        <div class="flex flex-wrap items-center justify-between gap-3">
          <Space wrap :size="16">
            <Checkbox v-model:checked="excludeResigned">排除离职</Checkbox>
            <Checkbox v-model:checked="excludeOutbound">排除外派</Checkbox>
          </Space>
          <div class="flex flex-wrap items-center gap-2">
            <span class="opm-field-label">姓名或工号</span>
            <Input
              v-model:value="personKw"
              allow-clear
              class="opm-input-person"
              placeholder="支持模糊查询"
              @press-enter="runPersonSearch"
            />
            <Button type="primary" ghost size="small" @click="runPersonSearch">查询</Button>
          </div>
        </div>
      </div>
    </Card>

    <div class="opm-body flex flex-col gap-3 lg:flex-row lg:items-stretch">
      <Card size="small" class="opm-panel opm-panel-tree shrink-0 lg:w-[248px]" :bordered="true">
        <template #title>
          <span class="opm-panel-title">组织架构</span>
        </template>
        <template #extra>
          <Tag class="opm-tag-dept" color="processing">{{ selectedDeptLabel }}</Tag>
        </template>
        <Spin :spinning="deptLoading">
          <div class="opm-tree-scroll">
            <Tree
              v-if="deptDisplayTree.length"
              v-model:expanded-keys="expandedDeptKeys"
              class="opm-tree"
              :tree-data="deptDisplayTree"
              :selected-keys="selectedDeptKeys"
              block-node
              show-line
              @select="onDeptSelect"
            />
            <div v-else class="opm-empty">暂无部门</div>
          </div>
        </Spin>
      </Card>

      <Card size="small" class="opm-panel opm-panel-mid min-w-0 flex-1" :bordered="true">
        <template #title>
          <span class="opm-panel-title">待选人员</span>
        </template>
        <template #extra>
          <Tag color="blue">共 {{ candidateTotal }} 条</Tag>
        </template>
        <Spin :spinning="listLoading">
          <Table
            class="opm-table"
            size="small"
            :columns="middleColumns"
            :data-source="candidateRows"
            :row-key="(r: any) => String(pick(r, 'id', 'ID'))"
            :pagination="{
              size: 'small',
              current: candidatePage,
              pageSize: candidatePageSize,
              total: candidateTotal,
              showSizeChanger: false,
              showQuickJumper: true,
            }"
            :scroll="{ y: 308 }"
            :row-selection="{
              selectedRowKeys: middleSelectedKeys,
              onChange: onMiddleSelectChange,
            }"
            @change="(pag) => onCandidatePaginationChange(pag)"
          />
        </Spin>
      </Card>

      <div class="opm-transfer flex shrink-0 items-center justify-center lg:w-[112px]">
        <div class="opm-transfer-stack">
          <Button type="primary" block size="small" @click="addToChosen">加入已选</Button>
          <Button danger type="default" block size="small" class="opm-tbtn-remove" @click="removeFromChosen">
            移除
          </Button>
          <Button block size="small" type="dashed" @click="clearChosen">清空</Button>
        </div>
      </div>

      <Card size="small" class="opm-panel opm-panel-chosen shrink-0 lg:w-[260px]" :bordered="true">
        <template #title>
          <span class="opm-panel-title">已选人员</span>
        </template>
        <template #extra>
          <Tag color="success">{{ chosenCount }}</Tag>
        </template>
        <Table
          class="opm-table"
          size="small"
          :columns="chosenColumns"
          :data-source="chosen"
          row-key="id"
          :pagination="false"
          :scroll="{ y: 308 }"
          :row-selection="{
            selectedRowKeys: chosenSelectedKeys,
            onChange: onChosenSelectChange,
          }"
        />
      </Card>
    </div>

    <Divider class="!my-4" />

    <div class="opm-footer flex justify-end gap-3">
      <Button @click="close">取消</Button>
      <Button type="primary" class="opm-btn-ok" @click="onConfirm">确定</Button>
    </div>
  </Modal>
</template>

<style scoped>
.opm-filter-card {
  background: linear-gradient(135deg, hsl(var(--muted) / 0.4) 0%, hsl(var(--card)) 100%);
  border-radius: 8px;
  border: 1px solid hsl(var(--border)) !important;
}

.opm-filter-card :deep(.ant-card-body) {
  padding: 12px 14px;
}

.opm-field-label {
  font-size: 13px;
  font-weight: 500;
  color: hsl(var(--muted-foreground));
  white-space: nowrap;
}

.opm-input-dept {
  width: 160px;
  max-width: 100%;
}

.opm-input-person {
  width: 176px;
  max-width: 100%;
}

.opm-panel {
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 1px 2px hsl(var(--foreground) / 0.04);
}

.opm-panel :deep(.ant-card-head) {
  min-height: 40px;
  padding: 0 12px;
  background: hsl(var(--muted) / 0.35);
  border-bottom: 1px solid hsl(var(--border));
}

.opm-panel :deep(.ant-card-head-title) {
  padding: 8px 0;
  font-size: 13px;
}

.opm-panel :deep(.ant-card-extra) {
  padding: 8px 0;
}

.opm-panel :deep(.ant-card-body) {
  padding: 10px;
}

.opm-panel-title {
  font-weight: 600;
  color: hsl(var(--foreground));
}

.opm-tag-dept {
  max-width: 112px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  margin-inline-end: 0;
}

.opm-tree-scroll {
  max-height: 360px;
  overflow: auto;
}

.opm-tree :deep(.ant-tree) {
  font-size: 13px;
}

.opm-empty {
  padding: 32px 8px;
  text-align: center;
  font-size: 12px;
  color: hsl(var(--muted-foreground));
}

.opm-table :deep(.ant-table-thead > tr > th) {
  background: hsl(var(--muted) / 0.22) !important;
  font-weight: 600;
  font-size: 12px;
  color: hsl(var(--muted-foreground));
}

.opm-table :deep(.ant-table-tbody > tr > td) {
  font-size: 13px;
}

.opm-table :deep(.ant-table-tbody > tr:hover > td) {
  background: hsl(var(--accent) / 0.35) !important;
}

.opm-transfer-stack {
  display: flex;
  width: 100%;
  max-width: 96px;
  flex-direction: column;
  gap: 10px;
  padding: 8px 4px;
}

.opm-tbtn-remove {
  border-width: 1px;
}

.opm-btn-ok {
  min-width: 88px;
}
</style>
