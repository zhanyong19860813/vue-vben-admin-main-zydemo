<script lang="ts" setup>
import type { VxeGridProps } from '#/adapter/vxe-table';
import type { VbenFormProps } from '#/adapter/form';

import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { Page } from '@vben/common-ui';
import { useUserStore } from '@vben/stores';
import { Button, Form, FormItem, Input, Modal, Radio, RadioGroup, Select, message } from 'ant-design-vue';
import { computed, onMounted, reactive, ref } from 'vue';
import { useRoute } from 'vue-router';

import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { useAuthStore } from '#/store';

interface RowType {
  id: string;
  SJID?: string;
  name?: string;
  groupname?: string;
  level_no?: string;
  is_manager?: string;
  description?: string;
  group_id?: string;
}

const ACTION = {
  add: 'add',
  edit: 'edit',
  deleteSelected: 'deleteSelected',
  reload: 'reload',
} as const;

const route = useRoute();
const userStore = useUserStore();
const authStore = useAuthStore();
const menuId = computed(() => {
  const q = route.meta?.query as Record<string, string> | undefined;
  const v = (q?.menuid ?? '').trim();
  return v || null;
});

const allowedActionKeys = ref<null | Set<string>>(null);
function showToolbarAction(actionKey: string) {
  const set = allowedActionKeys.value;
  if (set === null) return true;
  return set.has(actionKey);
}

async function loadToolbarPermissions() {
  const mid = menuId.value;
  if (!mid) {
    allowedActionKeys.value = null;
    return;
  }
  let userId = (userStore.userInfo as any)?.userId ?? (userStore.userInfo as any)?.id;
  if (!userId) {
    try {
      await authStore.fetchUserInfo();
    } catch {
      /* ignore */
    }
    const u = userStore.userInfo as any;
    userId = u?.userId ?? u?.id;
  }
  if (!userId) {
    allowedActionKeys.value = null;
    return;
  }
  try {
    const res = await requestClient.post<{ items: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: 'vben_v_user_role_menu_actions',
      Page: 1,
      PageSize: 500,
      Where: {
        Logic: 'AND',
        Conditions: [
          { Field: 'userid', Operator: 'eq', Value: String(userId) },
          { Field: 'menu_id', Operator: 'eq', Value: String(mid) },
        ],
        Groups: [],
      },
    });
    const raw = res?.items ?? [];
    const keys = new Set<string>();
    for (const r of raw) {
      const k = r.action_key ?? r.actionKey;
      if (k) keys.add(String(k));
    }
    allowedActionKeys.value = keys.size > 0 ? keys : null;
  } catch {
    allowedActionKeys.value = null;
  }
}

const groupOptions = ref<{ label: string; value: string }[]>([]);
const levelOptions = ref<{ label: string; value: string }[]>([]);

async function loadDictOptions() {
  const [groupRows, levelRows] = await Promise.all([
    requestClient.post<{ items: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: 'v_data_base_dictionary_detail',
      Page: 1,
      PageSize: 2000,
      SortBy: 'sort',
      SortOrder: 'asc',
      QueryField: 'id,name,code,type',
      Where: {
        Logic: 'AND',
        Conditions: [
          { Field: 'code', Operator: 'eq', Value: 'duty_group' },
          { Field: 'type', Operator: 'eq', Value: '1' },
        ],
        Groups: [],
      },
    }),
    requestClient.post<{ items: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), {
      TableName: 'v_data_base_dictionary_detail',
      Page: 1,
      PageSize: 2000,
      SortBy: 'sort',
      SortOrder: 'asc',
      QueryField: 'value,name,code',
      Where: {
        Logic: 'AND',
        Conditions: [{ Field: 'code', Operator: 'eq', Value: 'duty_level_no' }],
        Groups: [],
      },
    }),
  ]);
  groupOptions.value = (groupRows.items ?? []).map((x: any) => ({ value: String(x.id), label: String(x.name ?? '').trim() }));
  levelOptions.value = (levelRows.items ?? []).map((x: any) => ({ value: String(x.value ?? '').trim(), label: String(x.name ?? '').trim() }));
}

function buildWhere(formValues: Record<string, unknown>) {
  const conditions: Array<{ Field: string; Operator: string; Value: string }> = [];
  const name = String(formValues.name ?? '').trim();
  const groupId = String(formValues.group_id ?? '').trim();
  const level = String(formValues.level_no ?? '').trim();
  if (name) conditions.push({ Field: 'name', Operator: 'contains', Value: name });
  if (groupId) conditions.push({ Field: 'group_id', Operator: 'eq', Value: groupId });
  if (level) conditions.push({ Field: 'level_no', Operator: 'eq', Value: level });
  return { Logic: 'AND', Conditions: conditions, Groups: [] as any[] };
}

const formOptions: VbenFormProps = {
  collapsed: false,
  showCollapseButton: true,
  schema: [
    { component: 'Input', fieldName: 'name', label: '名称', componentProps: { allowClear: true } },
    {
      component: 'Select',
      fieldName: 'group_id',
      label: '分组',
      componentProps: () => ({ options: groupOptions.value, allowClear: true, showSearch: true }),
    },
    {
      component: 'Select',
      fieldName: 'level_no',
      label: '职级',
      componentProps: () => ({ options: levelOptions.value, allowClear: true, showSearch: true }),
    },
  ],
};

const gridOptions: VxeGridProps<RowType> = {
  columns: [
    { type: 'checkbox', width: 48, fixed: 'left' },
    { type: 'seq', width: 56, title: '#' },
    { field: 'id', title: 'id', width: 50, sortable: true, visible: false, showOverflow: true },
    { field: 'SJID', title: '岗位编码', width: 50, sortable: true, showOverflow: true },
    { field: 'name', title: '名称', width: 150, sortable: true, showOverflow: true },
    { field: 'code', title: '编码', width: 50, sortable: true, visible: false, showOverflow: true },
    { field: 'groupname', title: '分组', width: 50, sortable: true, showOverflow: true },
    { field: 'level_no', title: '职级', width: 50, sortable: true, showOverflow: true },
    {
      field: 'is_manager',
      title: '是否预设管理职',
      width: 50,
      showOverflow: true,
      formatter: ({ cellValue }) => (String(cellValue ?? '') === '1' ? '是' : '否'),
    },
    { field: 'description', title: '描述', width: 100, showOverflow: true },
  ],
  pagerConfig: { enabled: true, pageSize: 20, pageSizes: [20, 50, 100] },
  sortConfig: { remote: true, defaultSort: { field: 'id', order: 'asc' } },
  rowConfig: { isCurrent: true },
  gridEvents: {
    rowDblclick: ({ row }) => {
      if (row?.id) void openEditById(String(row.id));
    },
  },
  proxyConfig: {
    ajax: {
      query: async ({ page, sort }, formValues) => {
        const where = buildWhere(formValues || {});
        return requestClient.post<{ items: RowType[]; total: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
          TableName: 'v_t_base_duty_group',
          Page: page.currentPage,
          PageSize: page.pageSize,
          SortBy: sort?.field || 'id',
          SortOrder: (sort?.order || 'asc').toString().toLowerCase(),
          Where: where,
        });
      },
    },
  },
};

const [Grid, gridApi] = useVbenVxeGrid({ gridOptions, formOptions });

function getFirstSelected(): RowType | null {
  const rows = (gridApi.grid?.getCheckboxRecords?.() ?? []) as RowType[];
  if (rows.length < 1) return null;
  return rows[0] ?? null;
}

const editOpen = ref(false);
const mode = ref<'add' | 'edit'>('add');
const saving = ref(false);
const formState = reactive({
  id: '',
  name: '',
  SJID: '',
  level_no: undefined as string | undefined,
  is_manager: '0',
  group_id: undefined as string | undefined,
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

function resetForm() {
  Object.assign(formState, {
    id: '',
    name: '',
    SJID: '',
    level_no: undefined,
    is_manager: '0',
    group_id: undefined,
    description: '',
  });
}

async function calcNextSJID() {
  const res = await requestClient.post<{ items: Array<{ SJID?: string }>; total: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
    TableName: 't_base_duty',
    Page: 1,
    PageSize: 5000,
    QueryField: 'SJID',
    SortBy: 'SJID',
    SortOrder: 'desc',
    Where: { Logic: 'AND', Conditions: [], Groups: [] },
  });
  const max = (res.items ?? []).reduce((m, r) => Math.max(m, Number(String(r.SJID ?? '0').trim()) || 0), 0);
  return String(max + 1);
}

async function onAdd() {
  mode.value = 'add';
  resetForm();
  formState.id = newGuid();
  formState.SJID = await calcNextSJID();
  editOpen.value = true;
}

async function onEdit() {
  const row = getFirstSelected();
  if (!row) return message.warning('请选中一条记录');
  await openEditById(String(row.id));
}

async function openEditById(id: string) {
  mode.value = 'edit';
  resetForm();
  const res = await requestClient.post<{ items: any[]; total: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
    TableName: 'v_t_base_duty_group',
    Page: 1,
    PageSize: 1,
    QueryField: 'id,name,SJID,level_no,is_manager,group_id,description',
    Where: { Logic: 'AND', Conditions: [{ Field: 'id', Operator: 'eq', Value: id }], Groups: [] },
  });
  const d = (res.items ?? [])[0] ?? { id };
  formState.id = String(d.id ?? id);
  formState.name = String(d.name ?? '').trim();
  formState.SJID = String(d.SJID ?? '').trim();
  formState.level_no = d.level_no != null ? String(d.level_no) : undefined;
  formState.is_manager = String(d.is_manager ?? '0') === '1' ? '1' : '0';
  formState.group_id = d.group_id != null ? String(d.group_id) : undefined;
  formState.description = String(d.description ?? '').trim();
  editOpen.value = true;
}

async function saveDuty() {
  const name = formState.name.trim();
  if (!name) return message.warning('请输入职务名称');
  if (mode.value === 'add' && !formState.SJID.trim()) return message.warning('岗位编码不能为空');

  if (mode.value === 'add') {
    const [dupName, dupSJID] = await Promise.all([
      requestClient.post<{ items: any[]; total: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
        TableName: 't_base_duty',
        Page: 1,
        PageSize: 1,
        QueryField: 'id',
        Where: { Logic: 'AND', Conditions: [{ Field: 'name', Operator: 'eq', Value: name }], Groups: [] },
      }),
      requestClient.post<{ items: any[]; total: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
        TableName: 't_base_duty',
        Page: 1,
        PageSize: 1,
        QueryField: 'id',
        Where: { Logic: 'AND', Conditions: [{ Field: 'SJID', Operator: 'eq', Value: formState.SJID.trim() }], Groups: [] },
      }),
    ]);
    if ((dupName.total ?? 0) > 0) return message.warning('已存在当前岗位名称,请勿重复添加!');
    if ((dupSJID.total ?? 0) > 0) return message.warning('已存在当前岗位编码,请勿重复添加!');
  }

  saving.value = true;
  try {
    const row: Record<string, any> = {
      id: formState.id,
      name,
      code: 'SJ',
      level_no: formState.level_no ?? null,
      is_manager: formState.is_manager,
      group_id: formState.group_id ?? null,
      description: formState.description?.trim() || null,
    };
    if (mode.value === 'add') row.SJID = formState.SJID.trim();
    await requestClient.post(backendApi('DataSave/datasave-multi'), {
      tables: [{ tableName: 't_base_duty', primaryKey: 'id', data: [row] }],
    });
    message.success('保存成功');
    editOpen.value = false;
    await gridApi.reload();
  } catch (e: unknown) {
    message.error(e instanceof Error ? e.message : '保存失败');
  } finally {
    saving.value = false;
  }
}

function onDelete() {
  const row = getFirstSelected();
  if (!row) return message.warning('请选中一条记录');
  Modal.confirm({
    title: '删除',
    content: '确定删除选中记录？',
    async onOk() {
      try {
        const used = await requestClient.post<{ items: any[]; total: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
          TableName: 't_base_employee',
          Page: 1,
          PageSize: 1,
          QueryField: 'id',
          Where: { Logic: 'AND', Conditions: [{ Field: 'duty_id', Operator: 'eq', Value: String(row.id) }], Groups: [] },
        });
        if ((used.total ?? 0) > 0) {
          message.warning('当前岗位下有在职人员,不能进行删除操作!');
          return Promise.reject(new Error('used'));
        }
        await requestClient.post(backendApi('DataBatchDelete/BatchDelete'), {
          tableName: 't_base_duty',
          primaryKey: 'id',
          ids: [row.id],
        });
        message.success('删除成功');
        await gridApi.reload();
      } catch (e: unknown) {
        if (e instanceof Error && e.message === 'used') return Promise.reject(e);
        message.error(e instanceof Error ? e.message : '删除失败');
        return Promise.reject(e);
      }
    },
  });
}

function onReload() {
  gridApi.reload();
}

onMounted(async () => {
  await Promise.all([loadToolbarPermissions(), loadDictOptions()]);
});
</script>

<template>
  <Page>
    <Grid table-title="岗位管理" table-title-help="与老系统岗位管理对齐">
      <template #toolbar-tools>
        <Button v-if="showToolbarAction(ACTION.add)" class="mr-2" type="primary" @click="onAdd">
          新增
        </Button>
        <Button v-if="showToolbarAction(ACTION.edit)" class="mr-2" @click="onEdit">
          修改
        </Button>
        <Button v-if="showToolbarAction(ACTION.deleteSelected)" class="mr-2" danger @click="onDelete">
          删除
        </Button>
        <Button v-if="showToolbarAction(ACTION.reload)" @click="onReload">
          刷新
        </Button>
      </template>
    </Grid>

    <Modal
      v-model:open="editOpen"
      :title="mode === 'add' ? '新增' : '修改'"
      :confirm-loading="saving"
      :mask-closable="false"
      destroy-on-close
      @ok="saveDuty"
    >
      <Form layout="horizontal" :label-col="{ flex: '0 0 110px' }" :wrapper-col="{ flex: '1' }" :colon="false">
        <FormItem label="职务名称" required>
          <Input v-model:value="formState.name" allow-clear />
        </FormItem>
        <FormItem label="职务编码">
          <Input v-model:value="formState.SJID" :disabled="mode === 'edit'" />
        </FormItem>
        <FormItem label="职级">
          <Select v-model:value="formState.level_no" :options="levelOptions" allow-clear show-search />
        </FormItem>
        <FormItem label="预设为管理职务">
          <RadioGroup v-model:value="formState.is_manager">
            <Radio value="1">是</Radio>
            <Radio value="0">否</Radio>
          </RadioGroup>
        </FormItem>
        <FormItem label="分组">
          <Select v-model:value="formState.group_id" :options="groupOptions" allow-clear show-search />
        </FormItem>
        <FormItem label="说明">
          <Input.TextArea v-model:value="formState.description" :rows="4" />
        </FormItem>
      </Form>
    </Modal>
  </Page>
</template>
