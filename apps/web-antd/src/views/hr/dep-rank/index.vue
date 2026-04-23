<script setup lang="ts">
import type { VbenFormProps } from '#/adapter/form';
import type { VxeGridProps } from '#/adapter/vxe-table';

import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { Page } from '@vben/common-ui';
import { useUserStore } from '@vben/stores';
import { Button, Form, FormItem, InputNumber, Modal, Select, Tree, message } from 'ant-design-vue';
import { computed, onMounted, reactive, ref } from 'vue';
import { useRoute } from 'vue-router';

import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { useAuthStore } from '#/store';

type RowType = {
  id: string;
  department_id?: string;
  department_name?: string;
  duty_id?: string;
  duty_name?: string;
  Establishment?: number;
  is_manager?: string;
  sort?: number;
  onjob_count?: number;
  overcount?: number;
  normalTerm?: number;
  ylz?: number;
  sjxq?: number;
  EstablishmentCtl?: number | boolean | string;
  description?: string;
};

const ACTION = {
  add: 'add',
  edit: 'edit',
  deleteSelected: 'deleteSelected',
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
const depOptions = ref<{ label: string; value: string }[]>([]);
const depTree = ref<any[]>([]);
const selectedDeptId = ref<string>('');
const expandedKeys = ref<string[]>([]);

async function loadOptions() {
  const [ranks, deps] = await Promise.all([
    requestClient.post<{ items: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: 'v_t_base_duty_group',
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
  }));
  depOptions.value = depRows.map((x: any) => ({ value: x.id, label: x.name }));
  depTree.value = listToTree(depRows);
  expandedKeys.value = depTree.value.map((n: any) => String(n.key));
  if (!selectedDeptId.value && depRows.length > 0) {
    selectedDeptId.value = depRows[0].id;
  }
}

function listToTree(list: Array<{ id: string; name: string; parent_id: null | string }>) {
  const map = new Map<string, any>();
  const roots: any[] = [];
  for (const item of list) {
    map.set(item.id, { key: item.id, title: item.name, parent_id: item.parent_id, children: [] });
  }
  for (const item of list) {
    const node = map.get(item.id)!;
    if (item.parent_id && map.has(item.parent_id)) map.get(item.parent_id).children.push(node);
    else roots.push(node);
  }
  return roots;
}

const formOptions: VbenFormProps = {
  collapsed: false,
  showCollapseButton: true,
  schema: [{ component: 'Input', fieldName: 'duty_name', label: '职务', componentProps: { allowClear: true } }],
};

const gridOptions: VxeGridProps<RowType> = {
  columns: [
    { type: 'checkbox', width: 50 },
    { type: 'seq', width: 50 },
    { field: 'id', title: 'id', width: 50, visible: false, showOverflow: true },
    { field: 'department_id', title: 'department_id', width: 50, visible: false, showOverflow: true },
    { field: 'department_name', title: '部门', width: 100, sortable: true, showOverflow: true },
    { field: 'duty_id', title: 'duty_id', width: 50, visible: false, showOverflow: true },
    { field: 'duty_name', title: '职务', width: 100, sortable: true, showOverflow: true },
    { field: 'Establishment', title: '岗位编制', width: 60, sortable: true, showOverflow: true },
    { field: 'is_manager', title: '是否主管岗位', width: 100, sortable: true, showOverflow: true },
    { field: 'sort', title: '排序', width: 50, sortable: true, showOverflow: true },
    { field: 'onjob_count', title: '当前在岗人数', width: 60, sortable: true, showOverflow: true },
    { field: 'overcount', title: '超缺编人数', width: 60, sortable: true, showOverflow: true },
    { field: 'normalTerm', title: '默认转正月份', width: 60, sortable: true, showOverflow: true },
    { field: 'ylz', title: '预离职人数', width: 60, sortable: true, showOverflow: true },
    { field: 'sjxq', title: '实际需求人数', width: 60, sortable: true, showOverflow: true },
    { field: 'EstablishmentCtl', title: '超编控制', width: 50, sortable: true, showOverflow: true },
    { field: 'description', title: '说明', width: 100, visible: false, showOverflow: true },
  ],
  pagerConfig: { enabled: true, pageSize: 20 },
  sortConfig: { remote: true, defaultSort: { field: 'id', order: 'asc' } },
  proxyConfig: {
    ajax: {
      query: ({ page, sort }, formValues) =>
        requestClient.post<{ items: RowType[]; total: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
          TableName: 'v_t_base_post',
          Page: page.currentPage,
          PageSize: page.pageSize,
          SortBy: sort?.field || 'id',
          SortOrder: ((sort?.order as string) || 'asc').toLowerCase(),
          Where: {
            Logic: 'AND',
            Conditions: [
              ...(selectedDeptId.value
                ? [{ Field: 'department_id', Operator: 'eq', Value: selectedDeptId.value }]
                : []),
              ...(String((formValues as any)?.duty_name ?? '').trim()
                ? [{ Field: 'duty_name', Operator: 'contains', Value: String((formValues as any)?.duty_name ?? '').trim() }]
                : []),
            ],
            Groups: [],
          },
        }),
    },
  },
};

const [Grid, gridApi] = useVbenVxeGrid({ gridOptions, formOptions });

const editOpen = ref(false);
const mode = ref<'add' | 'edit'>('add');
const saving = ref(false);
const editForm = reactive({
  id: '',
  department_id: undefined as string | undefined,
  rank_id: undefined as string | undefined,
  duty_name: '',
  sort: 1,
  operator: '',
  operationTime: '',
  is_manager: '0',
  Establishment: 1,
  normalTerm: 0,
  EstablishmentCtl: 0,
  description: '',
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

function setEditDefaults() {
  const user = (userStore.userInfo as any) || {};
  const op = String(user.realName ?? user.username ?? user.name ?? '').trim();
  editForm.operator = op;
  editForm.operationTime = new Date().toLocaleString();
}

function onAdd() {
  mode.value = 'add';
  editOpen.value = true;
  editForm.id = newGuid();
  editForm.department_id = selectedDeptId.value || undefined;
  editForm.rank_id = undefined;
  editForm.duty_name = '';
  editForm.sort = 1;
  editForm.is_manager = '0';
  editForm.Establishment = 1;
  editForm.normalTerm = 0;
  editForm.EstablishmentCtl = 0;
  editForm.description = '';
  setEditDefaults();
}

function onEdit() {
  const rows = getSelectedRows();
  if (rows.length !== 1) return message.warning('请选中一条记录');
  const r = rows[0]!;
  mode.value = 'edit';
  editOpen.value = true;
  editForm.id = String(r.id);
  editForm.department_id = r.department_id ? String(r.department_id) : undefined;
  editForm.rank_id = r.duty_id ? String(r.duty_id) : undefined;
  editForm.duty_name = String(r.duty_name ?? '');
  editForm.sort = Number(r.sort ?? 1);
  editForm.is_manager = String(r.is_manager ?? '0');
  editForm.Establishment = Number(r.Establishment ?? 1);
  editForm.normalTerm = Number(r.normalTerm ?? 0);
  editForm.EstablishmentCtl = Number(r.EstablishmentCtl ?? 0);
  editForm.description = String(r.description ?? '');
  setEditDefaults();
}

async function saveEdit() {
  if (!editForm.department_id) return message.warning('请选择部门');
  if (!editForm.rank_id) return message.warning('请输入职级名称');
  const dup = await requestClient.post<{ total: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
    TableName: 'v_t_base_post',
    Page: 1,
    PageSize: 50,
    QueryField: 'id,department_id,duty_id',
    Where: {
      Logic: 'AND',
      Conditions: [
        { Field: 'department_id', Operator: 'eq', Value: editForm.department_id },
        { Field: 'duty_id', Operator: 'eq', Value: editForm.rank_id },
      ],
      Groups: [],
    },
  } as any);
  const duplicated = ((dup as any).items ?? []).some((x: any) => String(x.id) !== editForm.id);
  if (duplicated) return message.warning('该部门下职务已经存在!');

  saving.value = true;
  try {
    const selectedDutyName =
      rankOptions.value.find((x) => String(x.value).toLowerCase() === String(editForm.rank_id ?? '').toLowerCase())?.label
      ?? editForm.duty_name
      ?? '';
    if (!selectedDutyName.trim()) {
      message.warning('请选择有效职务');
      return;
    }
    await requestClient.post(backendApi('DataSave/datasave-multi'), {
      tables: [
        {
          tableName: 't_base_post',
          primaryKey: 'id',
          data: [
            {
              id: editForm.id,
              department_id: editForm.department_id,
              duty_id: editForm.rank_id,
              name: selectedDutyName.trim(),
              is_manager: editForm.is_manager,
              Establishment: editForm.Establishment,
              sort: editForm.sort,
              normalTerm: editForm.normalTerm,
              EstablishmentCtl: editForm.EstablishmentCtl,
              description: editForm.description || null,
            },
          ],
          deleteRows: [],
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
      const first = rows[0]!;
      const used = await requestClient.post<{ items: any[]; total: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
        TableName: 'v_t_base_employee',
        Page: 1,
        PageSize: 1,
        QueryField: 'long_name,dutyName',
        Where: {
          Logic: 'AND',
          Conditions: [
            { Field: 'dutyId', Operator: 'eq', Value: String(first.duty_id ?? '') },
            { Field: 'dept_id', Operator: 'eq', Value: String(first.department_id ?? '') },
            { Field: 'status', Operator: 'eq', Value: '0' },
          ],
          Groups: [],
        },
      });
      if ((used.total ?? 0) > 0) {
        const u = (used.items ?? [])[0] ?? {};
        message.warning(`${String(u.long_name ?? '')} ${String(u.dutyName ?? '')} 职务有在职人员,不能进行删除操作!`);
        return;
      }
      await requestClient.post(backendApi('DataBatchDelete/BatchDelete'), [
        {
          tableName: 't_base_post',
          key: 'id',
          keys: rows.map((x) => String(x.id)),
        },
      ]);
      message.success('删除数据成功！');
      gridApi.reload();
    },
  });
}

onMounted(async () => {
  await Promise.all([loadToolbarPermissions(), loadOptions()]);
  await gridApi.reload();
});

function onTreeSelect(keys: any) {
  const v = Array.isArray(keys) && keys.length > 0 ? String(keys[0]) : '';
  selectedDeptId.value = v;
  gridApi.reload();
}

function onTreeExpand(keys: any) {
  expandedKeys.value = (keys ?? []).map((k: any) => String(k));
}
</script>

<template>
  <Page>
    <div class="dep-rank-layout">
      <div class="dep-tree">
        <div class="dep-tree-title">组织结构树</div>
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
        <Grid table-title="部门岗位关联">
          <template #toolbar-tools>
            <Button v-if="showToolbarAction(ACTION.add)" class="mr-2" type="primary" @click="onAdd">新增</Button>
            <Button v-if="showToolbarAction(ACTION.edit)" class="mr-2" @click="onEdit">修改</Button>
            <Button v-if="showToolbarAction(ACTION.deleteSelected)" class="mr-2" danger @click="onDelete">删除</Button>
            <Button v-if="showToolbarAction(ACTION.reload)" @click="gridApi.reload()">刷新</Button>
          </template>
        </Grid>
      </div>
    </div>

    <Modal
      v-model:open="editOpen"
      :title="mode === 'add' ? '新增' : '修改'"
      :confirm-loading="saving"
      :mask-closable="false"
      @ok="saveEdit"
    >
      <Form layout="horizontal" :label-col="{ flex: '0 0 100px' }" :wrapper-col="{ flex: '1' }" :colon="false">
        <FormItem label="部门">
          <Select v-model:value="editForm.department_id" :options="depOptions" show-search />
        </FormItem>
        <FormItem label="职务">
          <Select v-model:value="editForm.rank_id" :options="rankOptions" show-search />
        </FormItem>
        <FormItem label="岗位编制">
          <InputNumber v-model:value="editForm.Establishment" :min="0" style="width: 100%" />
        </FormItem>
        <FormItem label="是否主管岗位">
          <Select
            v-model:value="editForm.is_manager"
            :options="[
              { label: '是', value: '1' },
              { label: '否', value: '0' },
            ]"
          />
        </FormItem>
        <FormItem label="排序">
          <InputNumber v-model:value="editForm.sort" :min="1" :max="50" style="width: 100%" />
        </FormItem>
        <FormItem label="默认转正月份">
          <InputNumber v-model:value="editForm.normalTerm" :min="0" style="width: 100%" />
        </FormItem>
        <FormItem label="超编控制">
          <Select
            v-model:value="editForm.EstablishmentCtl"
            :options="[
              { label: '否', value: 0 },
              { label: '是', value: 1 },
            ]"
          />
        </FormItem>
        <FormItem label="说明">
          <textarea v-model="editForm.description" class="ant-input" rows="3" />
        </FormItem>
      </Form>
    </Modal>
  </Page>
</template>

<style scoped>
.dep-rank-layout { display: flex; height: 100%; min-height: 0; }
.dep-tree { width: 260px; border-right: 1px solid #eee; padding: 8px; overflow: auto; }
.dep-tree-title { font-weight: 600; margin-bottom: 8px; }
.dep-grid { flex: 1; min-width: 0; padding-left: 8px; }
</style>

