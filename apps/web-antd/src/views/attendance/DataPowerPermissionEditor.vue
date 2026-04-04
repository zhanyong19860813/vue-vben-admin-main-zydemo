<script setup lang="ts">
/**
 * 数据权限：按管理员批量维护 att_lst_Power（部门行 dept_id / 人员行 emp_id）
 * 由 QueryTable openModal 挂载；须 emit success / cancel 关闭外层 Modal.confirm（与 FormFromDesignerModal 一致）
 */
import { computed, h, onMounted, ref } from 'vue';
import { Button, Card, Divider, Modal, Space, Table, Tag, Tooltip, message } from 'ant-design-vue';
import type { Key } from 'ant-design-vue/es/_util/type';

import { SelectDepartmentModal, SelectPersonnelModal } from '#/components/org-picker';
import type { OrgDeptItem, OrgPersonnelItem } from '#/components/org-picker';
import { queryForVben, whereAnd } from '#/components/org-picker/orgPickerQuery';
import { batchDelete, saveDatasaveMulti } from '#/views/attendance/shiftBcSettingApi';

const props = withDefaults(
  defineProps<{
    /** 与库内 manager_id 一致（可含空格填充）；新增模式可为空 */
    managerKeyRaw?: string;
    managerKey?: string;
    managerName?: string;
  }>(),
  {
    managerKeyRaw: '',
    managerKey: '',
    managerName: '',
  },
);

const emit = defineEmits<{
  success: [];
  cancel: [];
}>();

function pick(row: any, ...keys: string[]) {
  for (const k of keys) {
    if (row[k] !== undefined && row[k] !== null) return row[k];
  }
  return undefined;
}

type DeptRow = OrgDeptItem;
type EmpRow = { empId: string; name: string };

const loading = ref(false);
const saving = ref(false);
const deptRows = ref<DeptRow[]>([]);
const empRows = ref<EmpRow[]>([]);
const deptSelected = ref<Key[]>([]);
const empSelected = ref<Key[]>([]);

const deptPickerOpen = ref(false);
const empPickerOpen = ref(false);
const managerPickerOpen = ref(false);

/** 当前管理员（列表带入或弹窗内「选择管理员」） */
const mgrRaw = ref('');
const mgrKey = ref('');
const mgrName = ref('');

const hasManager = computed(() => !!mgrKey.value.trim());

function syncManagerFromProps() {
  mgrRaw.value = props.managerKeyRaw ?? '';
  mgrKey.value = (props.managerKey ?? '').trim();
  mgrName.value = (props.managerName ?? '').trim();
}

function normalizeManagerIdForSave(): string {
  return mgrKey.value.replace(/\s+/g, '').slice(0, 10);
}

function shortGuid(id: string): string {
  const s = String(id || '').trim();
  if (s.length <= 16) return s;
  return `${s.slice(0, 8)}…${s.slice(-4)}`;
}

const deptCount = computed(() => deptRows.value.length);
const empCount = computed(() => empRows.value.length);

async function loadExisting() {
  if (!mgrKey.value.trim()) {
    deptRows.value = [];
    empRows.value = [];
    return;
  }
  loading.value = true;
  try {
    const tryKeys = [mgrRaw.value, mgrKey.value].filter((v, i, a) => v && a.indexOf(v) === i);
    let items: any[] = [];
    for (const mk of tryKeys) {
      items = await queryForVben({
        TableName: 'v_att_lst_Power',
        Page: 1,
        PageSize: 2000,
        SortBy: 'type',
        SortOrder: 'asc',
        Where: whereAnd([{ Field: 'manager_id', Operator: 'eq', Value: mk }]),
      });
      if (items.length) break;
    }

    const depts = new Map<string, DeptRow>();
    const emps = new Map<string, EmpRow>();

    for (const r of items ?? []) {
      const type = String(pick(r, 'type', 'Type') ?? '');
      const qdept = pick(r, 'q_dept_id', 'Q_dept_id');
      const em = pick(r, 'emp_id', 'Emp_id');

      if (qdept && type === '部门') {
        const id = String(qdept);
        depts.set(id, {
          id,
          name: String(pick(r, 'dept_name', 'Dept_name') ?? ''),
          parentId: null,
        });
      } else if (em != null && String(em).trim() !== '') {
        const empId = String(em).trim().slice(0, 10);
        const rawName = String(pick(r, 'emp_name', 'Emp_name') ?? '');
        const name = rawName.includes('|') ? rawName.split('|').slice(1).join('|').trim() : rawName.trim();
        emps.set(empId, { empId, name: name || empId });
      }
    }

    deptRows.value = [...depts.values()];
    empRows.value = [...emps.values()];
  } catch (e: any) {
    message.error(e?.message || '加载权限失败');
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  syncManagerFromProps();
  void loadExisting();
});

function onManagerPicked(items: OrgPersonnelItem[]) {
  if (!items.length) return;
  if (items.length > 1) {
    message.info('已使用第一位人员作为管理员');
  }
  const p = items[0]!;
  const id = (p.empId || '').trim().slice(0, 10);
  if (!id) {
    message.warning('该人员工号无效');
    return;
  }
  mgrRaw.value = p.empId != null ? String(p.empId).trim() : id;
  mgrKey.value = id;
  mgrName.value = ((p.name || id).trim() || id);
  deptSelected.value = [];
  empSelected.value = [];
  void loadExisting();
}

function removeDeptSelected() {
  const rm = new Set(deptSelected.value.map(String));
  deptRows.value = deptRows.value.filter((d) => !rm.has(d.id));
  deptSelected.value = [];
}

function removeEmpSelected() {
  const rm = new Set(empSelected.value.map(String));
  empRows.value = empRows.value.filter((e) => !rm.has(e.empId));
  empSelected.value = [];
}

function onDeptPicked(items: OrgDeptItem[]) {
  const map = new Map(deptRows.value.map((d) => [d.id, d]));
  for (const d of items) map.set(d.id, { id: d.id, name: d.name, parentId: d.parentId });
  deptRows.value = [...map.values()];
}

function onEmpPicked(items: OrgPersonnelItem[]) {
  const map = new Map(empRows.value.map((e) => [e.empId, e]));
  for (const p of items) {
    const id = (p.empId || '').trim().slice(0, 10);
    if (!id) continue;
    map.set(id, { empId: id, name: (p.name || id).trim() });
  }
  empRows.value = [...map.values()];
}

async function onSave() {
  const mgr = normalizeManagerIdForSave();
  if (!mgr) {
    message.warning('管理员工号无效');
    return;
  }
  saving.value = true;
  try {
    const existing = await queryForVben({
      TableName: 'v_att_lst_Power',
      Page: 1,
      PageSize: 2000,
      SortBy: 'FID',
      SortOrder: 'asc',
      Where: whereAnd([{ Field: 'manager_id', Operator: 'eq', Value: mgrRaw.value || mgrKey.value }]),
    });
    let fids = (existing ?? []).map((r: any) => String(pick(r, 'FID', 'fid') ?? '')).filter(Boolean);
    if (!fids.length && mgrRaw.value !== mgrKey.value) {
      const again = await queryForVben({
        TableName: 'v_att_lst_Power',
        Page: 1,
        PageSize: 2000,
        SortBy: 'FID',
        SortOrder: 'asc',
        Where: whereAnd([{ Field: 'manager_id', Operator: 'eq', Value: mgrKey.value }]),
      });
      fids = (again ?? []).map((r: any) => String(pick(r, 'FID', 'fid') ?? '')).filter(Boolean);
    }

    const data: Record<string, any>[] = [];
    for (const d of deptRows.value) {
      data.push({
        FID: crypto.randomUUID(),
        manager_id: mgr,
        dept_id: d.id,
        emp_id: null,
      });
    }
    for (const e of empRows.value) {
      data.push({
        FID: crypto.randomUUID(),
        manager_id: mgr,
        dept_id: null,
        emp_id: e.empId,
      });
    }

    if (!data.length && !fids.length) {
      message.warning('请添加至少一个部门或人员后再保存');
      return;
    }

    if (fids.length) {
      await batchDelete([
        {
          tablename: 'att_lst_Power',
          key: 'FID',
          Keys: fids.map((id) => id.toUpperCase()),
        },
      ]);
    }

    if (data.length) {
      await saveDatasaveMulti([
        {
          tableName: 'att_lst_Power',
          primaryKey: 'FID',
          data,
          deleteRows: [],
        },
      ]);
    }

    message.success('保存成功');
    emit('success');
  } catch (e: any) {
    message.error(e?.message || '保存失败');
  } finally {
    saving.value = false;
  }
}

function onCancel() {
  emit('cancel');
}

function confirmRemoveLine() {
  if (!deptSelected.value.length && !empSelected.value.length) {
    message.warning('请在左侧或右侧表格勾选要删除的行');
    return;
  }
  Modal.confirm({
    title: '确认删除',
    content: '从列表中移除选中的部门或人员？（保存后才会写入数据库）',
    onOk() {
      removeDeptSelected();
      removeEmpSelected();
    },
  });
}

const deptColumns = [
  { title: '部门名称', dataIndex: 'name', key: 'name', ellipsis: true },
  {
    title: '部门 ID',
    dataIndex: 'id',
    key: 'id',
    width: 128,
    customRender: ({ record }: { record: DeptRow }) =>
      h(
        Tooltip,
        { title: record.id, placement: 'topLeft' },
        () => h('span', { class: 'dpe-mono-id' }, shortGuid(record.id)),
      ),
  },
];

const empColumns = [
  { title: '工号', dataIndex: 'empId', key: 'empId', width: 96 },
  { title: '姓名', dataIndex: 'name', key: 'name', ellipsis: true },
];

function onDeptTableSelectChange(keys: Key[]) {
  deptSelected.value = keys;
}

function onEmpTableSelectChange(keys: Key[]) {
  empSelected.value = keys;
}
</script>

<template>
  <div class="data-power-editor">
    <Card size="small" :bordered="false" class="dpe-hero mb-4">
      <div v-if="!hasManager" class="dpe-hero-row dpe-hero-add">
        <div class="dpe-hero-hint">新增：请先选择要配置数据权限的<strong>管理员</strong>（被授权查看部门/人员范围的人）。</div>
        <Button type="primary" @click="managerPickerOpen = true">选择管理员</Button>
      </div>
      <div v-else class="dpe-hero-row">
        <div class="dpe-hero-label">管理员姓名</div>
        <div class="dpe-hero-name">{{ mgrName }}</div>
        <Tag color="processing" class="dpe-hero-tag">工号 {{ mgrKey }}</Tag>
        <Button type="link" size="small" class="!px-1" @click="managerPickerOpen = true">更换管理员</Button>
      </div>
    </Card>

    <div class="dpe-toolbar mb-4">
      <Space wrap :size="10">
        <Button type="primary" :disabled="!hasManager" @click="deptPickerOpen = true">
          <span class="dpe-btn-plus">+</span>
          增加部门
        </Button>
        <Button type="primary" ghost :disabled="!hasManager" @click="empPickerOpen = true">
          <span class="dpe-btn-plus">+</span>
          增加人员
        </Button>
        <Button
          danger
          type="default"
          class="dpe-btn-remove"
          :disabled="!hasManager"
          @click="confirmRemoveLine"
        >
          移除选中
        </Button>
      </Space>
    </div>

    <div class="dpe-panels flex flex-col gap-4 lg:flex-row">
      <Card size="small" class="dpe-panel min-w-0 flex-1" :bordered="true">
        <template #title>
          <span class="dpe-panel-title">管理部门</span>
          <Tag class="ml-2" color="blue">{{ deptCount }}</Tag>
        </template>
        <Table
          class="dpe-table"
          size="small"
          :columns="deptColumns"
          :data-source="deptRows"
          row-key="id"
          :loading="loading"
          :pagination="false"
          :scroll="{ y: 280 }"
          :row-selection="{
            selectedRowKeys: deptSelected,
            onChange: onDeptTableSelectChange,
          }"
        />
      </Card>

      <Card size="small" class="dpe-panel min-w-0 flex-1" :bordered="true">
        <template #title>
          <span class="dpe-panel-title">管理人员</span>
          <Tag class="ml-2" color="green">{{ empCount }}</Tag>
        </template>
        <Table
          class="dpe-table"
          size="small"
          :columns="empColumns"
          :data-source="empRows"
          row-key="empId"
          :loading="loading"
          :pagination="false"
          :scroll="{ y: 280 }"
          :row-selection="{
            selectedRowKeys: empSelected,
            onChange: onEmpTableSelectChange,
          }"
        />
      </Card>
    </div>

    <Divider class="!my-4" />

    <div class="dpe-footer flex justify-end gap-3">
      <Button @click="onCancel">取消</Button>
      <Button type="primary" :loading="saving" :disabled="!hasManager" @click="onSave">保存</Button>
    </div>

    <SelectDepartmentModal
      v-model:open="deptPickerOpen"
      title="选择部门"
      @confirm="onDeptPicked"
    />
    <SelectPersonnelModal
      v-model:open="managerPickerOpen"
      title="选择管理员"
      @confirm="onManagerPicked"
    />
    <SelectPersonnelModal v-model:open="empPickerOpen" title="选择人员" @confirm="onEmpPicked" />
  </div>
</template>

<style scoped>
.data-power-editor {
  padding: 4px 4px 0;
}

.dpe-hero {
  background: linear-gradient(135deg, hsl(var(--muted) / 0.45) 0%, hsl(var(--card)) 100%);
  border-radius: 8px;
  border: 1px solid hsl(var(--border));
}

.dpe-hero :deep(.ant-card-body) {
  padding: 14px 16px;
}

.dpe-hero-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px 14px;
}

.dpe-hero-label {
  font-size: 13px;
  color: hsl(var(--muted-foreground));
  font-weight: 500;
}

.dpe-hero-name {
  font-size: 16px;
  font-weight: 600;
  color: hsl(var(--foreground));
  letter-spacing: 0.02em;
}

.dpe-hero-tag {
  margin-inline-end: 0;
}

.dpe-hero-add {
  flex-direction: column;
  align-items: flex-start;
  gap: 12px;
}

.dpe-hero-hint {
  font-size: 13px;
  line-height: 1.5;
  color: hsl(var(--muted-foreground));
}

.dpe-btn-plus {
  margin-inline-end: 4px;
  font-weight: 600;
  opacity: 0.95;
}

.dpe-btn-remove {
  border-style: solid;
}

.dpe-panel :deep(.ant-card-head) {
  min-height: 42px;
  padding: 0 14px;
  background: hsl(var(--muted) / 0.35);
  border-bottom: 1px solid hsl(var(--border));
  border-radius: 8px 8px 0 0;
}

.dpe-panel :deep(.ant-card-head-title) {
  padding: 10px 0;
}

.dpe-panel :deep(.ant-card-body) {
  padding: 12px;
}

.dpe-panel {
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 1px 2px hsl(var(--foreground) / 0.04);
}

.dpe-panel-title {
  font-size: 14px;
  font-weight: 600;
  color: hsl(var(--foreground));
}

.dpe-table :deep(.ant-table-thead > tr > th) {
  background: hsl(var(--muted) / 0.25) !important;
  font-weight: 600;
  font-size: 12px;
  color: hsl(var(--muted-foreground));
}

.dpe-table :deep(.ant-table-tbody > tr > td) {
  font-size: 13px;
}

.dpe-table :deep(.ant-table-tbody > tr:hover > td) {
  background: hsl(var(--accent) / 0.35) !important;
}

.dpe-mono-id {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 12px;
  color: hsl(var(--muted-foreground));
  cursor: default;
}

.dpe-footer :deep(.ant-btn-primary) {
  min-width: 88px;
}
</style>
