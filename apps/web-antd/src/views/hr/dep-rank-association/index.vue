<script setup lang="ts">
import type { VxeGridProps } from '#/adapter/vxe-table';

import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { Page } from '@vben/common-ui';
import { useUserStore } from '@vben/stores';
import { Button, Checkbox, Form, FormItem, Input, InputNumber, Modal, Select, Tree, message } from 'ant-design-vue';
import { computed, onMounted, reactive, ref } from 'vue';
import { useRoute } from 'vue-router';

import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { useAuthStore } from '#/store';

/** 与老系统 v_base_dep_rank + BaseDepRank 一致 */
type RowType = {
  id: string;
  department_id?: string;
  department_name?: string;
  path?: string;
  rank_id?: string;
  rank_name?: string;
  sort?: number;
  operator?: string;
  operationTime?: string;
};

const ACTION = {
  add: 'add',
  edit: 'edit',
  deleteSelected: 'deleteSelected',
  inherit: 'inherit',
  reload: 'reload',
} as const;

const route = useRoute();
const userStore = useUserStore();
const authStore = useAuthStore();
const menuId = computed(() => ((route.meta?.query as any)?.menuid as string) || null);
const allowedActionKeys = ref<null | Set<string>>(null);

function showToolbarAction(actionKey: string) {
  const set = allowedActionKeys.value;
  if (set === null) return true;
  return set.has(actionKey);
}

async function loadToolbarPermissions() {
  if (!menuId.value) return;
  let userId = (userStore.userInfo as any)?.userId ?? (userStore.userInfo as any)?.id;
  if (!userId) {
    await authStore.fetchUserInfo();
    userId = (userStore.userInfo as any)?.userId ?? (userStore.userInfo as any)?.id;
  }
  if (!userId) return;
  const res = await requestClient.post<{ items: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), {
    TableName: 'vben_v_user_role_menu_actions',
    Page: 1,
    PageSize: 500,
    Where: {
      Logic: 'AND',
      Conditions: [
        { Field: 'userid', Operator: 'eq', Value: String(userId) },
        { Field: 'menu_id', Operator: 'eq', Value: String(menuId.value) },
      ],
      Groups: [],
    },
  });
  const keys = new Set<string>();
  for (const r of res.items ?? []) {
    const k = r.action_key ?? r.actionKey;
    if (k) keys.add(String(k));
  }
  allowedActionKeys.value = keys.size > 0 ? keys : null;
}

const rankOptions = ref<{ label: string; value: string }[]>([]);
const depTree = ref<any[]>([]);
const depPathById = ref<Map<string, string>>(new Map());
const selectedDeptId = ref<string>('');
const selectedDeptPath = ref<string>('');
const expandedKeys = ref<string[]>([]);

/** 与老界面：职级名称模糊 + 并集（含子部门 path 前缀） */
const searchRankName = ref('');
const unionSubDepts = ref(false);

async function loadOptions() {
  const [ranks, deps] = await Promise.all([
    requestClient.post<{ items: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: 'v_t_base_rank',
      Page: 1,
      PageSize: 2000,
      QueryField: 'id,name',
      SortBy: 'name',
      SortOrder: 'asc',
      Where: { Logic: 'AND', Conditions: [], Groups: [] },
    }),
    requestClient.post<{ items: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: 'v_t_base_department',
      Page: 1,
      PageSize: 5000,
      QueryField: 'id,name,parent_id,path',
      SortBy: 'path',
      SortOrder: 'asc',
      Where: { Logic: 'AND', Conditions: [], Groups: [] },
    }),
  ]);
  rankOptions.value = (ranks.items ?? []).map((x: any) => ({ value: String(x.id), label: String(x.name ?? '') }));

  const depRows = (deps.items ?? []).map((x: any) => ({
    id: String(x.id),
    name: String(x.name ?? ''),
    parent_id: x.parent_id ? String(x.parent_id) : null,
    path: String(x.path ?? '').trim(),
  }));
  const m = new Map<string, string>();
  for (const r of depRows) m.set(r.id, r.path);
  depPathById.value = m;
  depTree.value = listToTree(depRows);
  expandedKeys.value = depTree.value.map((n: any) => String(n.key));
  if (!selectedDeptId.value && depRows.length > 0) {
    selectedDeptId.value = depRows[0]!.id;
    selectedDeptPath.value = depRows[0]!.path;
  }
}

function listToTree(list: Array<{ id: string; name: string; parent_id: null | string; path: string }>) {
  const map = new Map<string, any>();
  const roots: any[] = [];
  for (const item of list) {
    map.set(item.id, {
      key: item.id,
      title: item.name,
      path: item.path,
      parent_id: item.parent_id,
      children: [],
    });
  }
  for (const item of list) {
    const node = map.get(item.id)!;
    if (item.parent_id && map.has(item.parent_id)) map.get(item.parent_id).children.push(node);
    else roots.push(node);
  }
  return roots;
}

function buildWhereConditions(): Array<{ Field: string; Operator: string; Value: string }> {
  const cond: Array<{ Field: string; Operator: string; Value: string }> = [];
  const kw = searchRankName.value.trim();
  if (kw) cond.push({ Field: 'rank_name', Operator: 'contains', Value: kw });

  if (!selectedDeptId.value) return cond;

  /** 并集仅在有 path 时用前缀；否则与单部门一致，避免 path 为空时条件过宽 */
  if (unionSubDepts.value && selectedDeptPath.value.trim()) {
    cond.push({ Field: 'path', Operator: 'startswith', Value: selectedDeptPath.value.trim() });
  } else {
    cond.push({ Field: 'department_id', Operator: 'eq', Value: selectedDeptId.value });
  }
  return cond;
}

const gridOptions: VxeGridProps<RowType> = {
  /** 关闭横向虚拟滚动，让表体按容器宽度铺满；列用 minWidth + 百分比分配剩余空间 */
  scrollX: { enabled: false },
  columns: [
    { type: 'checkbox', width: 48 },
    { type: 'seq', width: 56, title: '序号' },
    { field: 'id', title: 'id', width: 50, visible: false, showOverflow: true },
    { field: 'department_id', title: 'department_id', width: 50, visible: false, showOverflow: true },
    { field: 'department_name', title: 'department_name', width: 100, visible: false, showOverflow: true },
    { field: 'path', title: 'path', width: 50, visible: false, showOverflow: true },
    { field: 'rank_id', title: 'rank_id', width: 50, visible: false, showOverflow: true },
    {
      field: 'rank_name',
      title: '职级名称',
      minWidth: 200,
      width: '46%',
      sortable: true,
      showOverflow: true,
      align: 'left',
    },
    { field: 'sort', title: '排序', width: '10%', minWidth: 72, sortable: true, showOverflow: true },
    {
      field: 'operator',
      title: '操作人',
      minWidth: 120,
      width: '44%',
      sortable: true,
      showOverflow: true,
      align: 'left',
    },
    { field: 'operationTime', title: 'operationTime', width: 50, visible: false, sortable: true, showOverflow: true },
  ],
  pagerConfig: { enabled: true, pageSize: 500, pageSizes: [20, 50, 100, 500] },
  sortConfig: { remote: true, defaultSort: { field: 'sort', order: 'asc' } },
  proxyConfig: {
    ajax: {
      query: ({ page, sort }) =>
        requestClient.post<{ items: RowType[]; total: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
          TableName: 'v_base_dep_rank',
          Page: page.currentPage,
          PageSize: page.pageSize,
          SortBy: sort?.field || 'sort',
          SortOrder: ((sort?.order as string) || 'asc').toLowerCase(),
          Where: { Logic: 'AND', Conditions: buildWhereConditions(), Groups: [] },
        }),
    },
  },
};

const [Grid, gridApi] = useVbenVxeGrid({ gridOptions, formOptions: undefined as any });

const editOpen = ref(false);
const mode = ref<'add' | 'edit'>('add');
const saving = ref(false);
const editForm = reactive({
  id: '',
  department_id: '' as string,
  rank_id: undefined as string | undefined,
  rank_name: '',
  sort: 1,
  operator: '',
  operationTime: '',
});

function newGuid() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function getSelectedRows() {
  return (gridApi.grid?.getCheckboxRecords?.() ?? []) as RowType[];
}

function setEditMeta() {
  const u = (userStore.userInfo as any) || {};
  editForm.operator = String(u.realName ?? u.username ?? u.name ?? '').trim();
  editForm.operationTime = new Date().toLocaleString('zh-CN', { hour12: false });
}

function onAdd() {
  if (!selectedDeptId.value) return message.warning('请先在左侧选择部门');
  mode.value = 'add';
  editForm.id = newGuid();
  editForm.department_id = selectedDeptId.value;
  editForm.rank_id = undefined;
  editForm.rank_name = '';
  editForm.sort = 1;
  setEditMeta();
  editOpen.value = true;
}

function onEdit() {
  const rows = getSelectedRows();
  if (rows.length !== 1) return message.warning('请选中一条记录');
  const r = rows[0]!;
  mode.value = 'edit';
  editForm.id = String(r.id);
  editForm.department_id = String(r.department_id ?? '');
  editForm.rank_id = r.rank_id ? String(r.rank_id) : undefined;
  editForm.rank_name = String(r.rank_name ?? '');
  editForm.sort = Number(r.sort ?? 1);
  setEditMeta();
  editOpen.value = true;
}

async function saveEdit() {
  if (!editForm.department_id) return message.warning('部门无效');
  if (!editForm.rank_id) return message.warning('请输入职级名称');
  const rankLabel =
    rankOptions.value.find((x) => String(x.value).toLowerCase() === String(editForm.rank_id).toLowerCase())?.label
    ?? editForm.rank_name
    ?? '';
  if (!rankLabel.trim()) return message.warning('请选择有效职级');

  const dup = await requestClient.post<{ items: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), {
    TableName: 'v_base_dep_rank',
    Page: 1,
    PageSize: 50,
    QueryField: 'id',
    Where: {
      Logic: 'AND',
      Conditions: [
        { Field: 'department_id', Operator: 'eq', Value: editForm.department_id },
        { Field: 'rank_id', Operator: 'eq', Value: editForm.rank_id },
      ],
      Groups: [],
    },
  } as any);
  const duplicated = ((dup as any).items ?? []).some((x: any) => String(x.id) !== editForm.id);
  if (duplicated) return message.warning(`[${rankLabel}]职级已经存在!`);

  saving.value = true;
  try {
    await requestClient.post(backendApi('DataSave/datasave-multi'), {
      tables: [
        {
          tableName: 't_base_dep_rank',
          primaryKey: 'id',
          deleteRows: [],
          data: [
            {
              id: editForm.id,
              department_id: editForm.department_id,
              rank_id: editForm.rank_id,
              sort: editForm.sort,
              operator: editForm.operator,
              operationTime: new Date().toISOString(),
            },
          ],
        },
      ],
    });
    message.success('保存成功');
    editOpen.value = false;
    gridApi.reload();
  } catch (e: any) {
    const msg =
      e?.response?.data?.message
      || e?.response?.data?.error
      || (typeof e?.response?.data === 'string' ? e.response.data : '')
      || e?.message
      || '保存失败';
    message.error(msg);
  } finally {
    saving.value = false;
  }
}

function onDelete() {
  const rows = getSelectedRows();
  if (rows.length === 0) return message.warning('请选择记录');
  Modal.confirm({
    title: '请确认',
    content: `已选择${rows.length}条记录,确认删除?`,
    async onOk() {
      await requestClient.post(backendApi('DataBatchDelete/BatchDelete'), [
        {
          tableName: 't_base_dep_rank',
          key: 'id',
          keys: rows.map((x) => String(x.id)),
        },
      ]);
      message.success('删除数据成功！');
      gridApi.reload();
    },
  });
}

function onInherit() {
  const rows = getSelectedRows();
  if (rows.length === 0) return message.warning('请选择记录');
  const items = rows.map((r) => ({ dep_id: r.department_id, rank_id: r.rank_id }));
  Modal.confirm({
    title: '提示',
    content: `已选择${items.length}条记录,确认子部门继承?`,
    async onOk() {
      await requestClient.post(backendApi('DepRank/inherit'), { items });
      message.success('操作成功！');
      gridApi.reload();
    },
  });
}

function onQuery() {
  gridApi.reload();
}

function onTreeSelect(keys: any) {
  const v = Array.isArray(keys) && keys.length > 0 ? String(keys[0]) : '';
  selectedDeptId.value = v;
  selectedDeptPath.value = depPathById.value.get(v) ?? '';
  gridApi.reload();
}

function onTreeExpand(keys: any) {
  expandedKeys.value = (keys ?? []).map((k: any) => String(k));
}

onMounted(async () => {
  await Promise.all([loadToolbarPermissions(), loadOptions()]);
  await gridApi.reload();
});
</script>

<template>
  <Page>
    <div class="dep-rank-layout">
      <div class="dep-tree">
        <div class="dep-tree-title">组织结构</div>
        <Tree
          :tree-data="depTree"
          :expanded-keys="expandedKeys"
          :selected-keys="selectedDeptId ? [selectedDeptId] : []"
          :auto-expand-parent="false"
          @select="onTreeSelect"
          @expand="onTreeExpand"
        />
      </div>
      <div class="dep-grid">
        <div class="toolbar-extra">
          <Input
            v-model:value="searchRankName"
            allow-clear
            placeholder="职级名称"
            style="width: 200px"
            @press-enter="onQuery"
          />
          <Checkbox v-model:checked="unionSubDepts" class="ml-2">并集</Checkbox>
          <Button type="primary" class="ml-2" @click="onQuery">查询</Button>
        </div>
        <Grid class="dep-rank-assoc-grid-wrap" grid-class="dep-rank-assoc-vxe" table-title="部门职级关联">
          <template #toolbar-tools>
            <Button v-if="showToolbarAction(ACTION.add)" class="mr-2" type="primary" @click="onAdd">新增</Button>
            <Button v-if="showToolbarAction(ACTION.edit)" class="mr-2" @click="onEdit">修改</Button>
            <Button v-if="showToolbarAction(ACTION.deleteSelected)" class="mr-2" danger @click="onDelete">删除</Button>
            <Button v-if="showToolbarAction(ACTION.inherit)" class="mr-2" @click="onInherit">子部门继承</Button>
            <Button v-if="showToolbarAction(ACTION.reload)" @click="gridApi.reload()">刷新</Button>
          </template>
        </Grid>
      </div>
    </div>

    <Modal
      v-model:open="editOpen"
      :title="mode === 'add' ? '新增' : '修改'"
      width="600px"
      :mask-closable="false"
      destroy-on-close
    >
      <Form layout="horizontal" :label-col="{ flex: '0 0 72px' }" :wrapper-col="{ flex: '1' }" :colon="false">
        <FormItem label="职级" required>
          <Select
            v-model:value="editForm.rank_id"
            show-search
            :filter-option="
              (input, option) =>
                String(option?.label ?? '')
                  .toLowerCase()
                  .includes(input.toLowerCase())
            "
            :options="rankOptions"
            placeholder="请选择职级"
            :disabled="mode === 'edit'"
          />
        </FormItem>
        <FormItem label="排序" required>
          <InputNumber v-model:value="editForm.sort" :min="1" :max="50" style="width: 100%" />
        </FormItem>
        <FormItem label="操作人">
          <Input :value="editForm.operator" disabled />
        </FormItem>
        <FormItem label="操作时间">
          <Input :value="editForm.operationTime" disabled />
        </FormItem>
      </Form>
      <template #footer>
        <Button @click="editOpen = false">取消</Button>
        <Button type="primary" :loading="saving" @click="saveEdit">保存</Button>
      </template>
    </Modal>
  </Page>
</template>

<style scoped>
.dep-rank-layout {
  display: flex;
  height: 100%;
  min-height: 0;
}
.dep-tree {
  width: 260px;
  border-right: 1px solid #eee;
  padding: 8px;
  overflow: auto;
}
.dep-tree-title {
  font-weight: 600;
  margin-bottom: 8px;
}
.dep-grid {
  flex: 1;
  min-width: 0;
  padding-left: 8px;
  display: flex;
  flex-direction: column;
  min-height: 0;
}
.toolbar-extra {
  display: flex;
  align-items: center;
  margin-bottom: 8px;
}
.ml-2 {
  margin-left: 8px;
}

/* 右侧表格区域占满宽度，避免列总宽小于容器时出现大块空白 */
/* class 与 Vben VxeGrid 外层 div（含 bg-card）合并在同一节点上 */
.dep-rank-assoc-grid-wrap {
  flex: 1 1 0%;
  min-height: 0;
  min-width: 0;
  width: 100%;
  display: flex;
  flex-direction: column;
}

.dep-rank-assoc-vxe {
  flex: 1 1 0%;
  min-height: 0;
  min-width: 0;
  width: 100% !important;
}

.dep-rank-assoc-vxe :deep(.vxe-grid--layout-body-content-wrapper) {
  flex: 1;
  min-height: 0;
  min-width: 0;
}

.dep-rank-assoc-vxe :deep(.vxe-table--main-wrapper),
.dep-rank-assoc-vxe :deep(.vxe-table--render-wrapper) {
  width: 100% !important;
}

.dep-rank-assoc-vxe :deep(.vxe-table--body-wrapper),
.dep-rank-assoc-vxe :deep(.vxe-table--header-wrapper) {
  width: 100% !important;
}

.dep-rank-assoc-vxe :deep(table.vxe-table--body),
.dep-rank-assoc-vxe :deep(table.vxe-table--header) {
  width: 100% !important;
  table-layout: fixed;
}
</style>
