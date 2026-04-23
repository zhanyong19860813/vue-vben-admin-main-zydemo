<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';

import { Page } from '@vben/common-ui';
import { useUserStore } from '@vben/stores';
import { Button, Card, Form, Modal, Select, Space, Table, Tabs, Tag, message } from 'ant-design-vue';

import { queryForVbenPaged } from '#/components/org-picker/orgPickerQuery';
import {
  type WfEngineRuntimeTodoItem,
  wfEngineRuntimeDeleteTasks,
  wfEngineRuntimeTodoAll,
} from '#/api/workflowEngine';

const router = useRouter();
const userStore = useUserStore();

const loading = ref(false);
const rows = ref<WfEngineRuntimeTodoItem[]>([]);
const page = ref(1);
const pageSize = ref(20);
const total = ref(0);
const activeTab = ref<'cc' | 'done' | 'todo'>('todo');

const deleteLoading = ref(false);
const selectedRowKeys = ref<string[]>([]);

function onTodoSelectionChange(keys: Array<number | string>) {
  selectedRowKeys.value = keys.map((x) => String(x));
}

/** 查看流程：选人后以该身份模拟办理人打开 runtime-viewer（依赖 X-Workflow-Mock-User-Id） */
const viewerOpen = ref(false);
const viewerRow = ref<WfEngineRuntimeTodoItem | null>(null);
const viewerIdentity = ref<string | undefined>(undefined);
type ViewerIdentityOption = {
  empNo?: string;
  label: string;
  name?: string;
  value: string;
};
const viewerOptions = ref<ViewerIdentityOption[]>([]);
const viewerSearchLoading = ref(false);
let viewerSearchTimer: ReturnType<typeof setTimeout> | null = null;

const loginUserId = computed(() =>
  String((userStore.userInfo as { userId?: string } | null)?.userId || '').trim(),
);

const columns = [
  { title: '流程', dataIndex: 'processName', key: 'processName', width: 160 },
  { title: '流程编号', dataIndex: 'instanceNo', key: 'flowNo', width: 190 },
  { title: '当前节点', dataIndex: 'nodeName', key: 'nodeName', width: 140 },
  { title: '处理人工号', key: 'assigneeWorkNo', width: 150 },
  { title: '处理人姓名', key: 'assigneeDisplayName', width: 140 },
  { title: '状态', key: 'statusText', width: 110 },
  { title: '接收时间', dataIndex: 'receivedAt', key: 'receivedAt', width: 170 },
  { title: '操作', key: 'action', fixed: 'right' as const, width: 250 },
];

function pickFirstNonEmpty(obj: Record<string, any>, keys: string[]): string {
  for (const k of keys) {
    const v = obj[k];
    if (v !== undefined && v !== null && String(v).trim()) return String(v).trim();
  }
  return '';
}

function resolveAssigneeWorkNo(row: WfEngineRuntimeTodoItem): string {
  const r = row as unknown as Record<string, any>;
  return (
    pickFirstNonEmpty(r, [
      'assigneeWorkNo',
      'assignee_work_no',
      'assigneeEmpId',
      'assignee_emp_id',
      'assigneeNo',
      'assignee_no',
      'assigneeEmployeeNo',
      'assignee_employee_no',
      'employeeNo',
      'employee_no',
      'EMP_ID',
      'emp_id',
      'code',
      'assigneeUserCode',
      'assignee_user_code',
    ]) || '—'
  );
}

function resolveAssigneeDisplayName(row: WfEngineRuntimeTodoItem): string {
  const r = row as unknown as Record<string, any>;
  const v = pickFirstNonEmpty(r, [
    'assigneeDisplayName',
    'assignee_display_name',
    'assigneeUserName',
    'assignee_user_name',
    'assigneeName',
    'assignee_name',
  ]);
  const t = String(v || '').trim();
  if (!t) return '—';
  if (/负责人|经理|审批|发起|角色/.test(t)) return '—';
  return t;
}

function resolveFlowNo(row: WfEngineRuntimeTodoItem): string {
  const r = row as unknown as Record<string, any>;
  const v = pickFirstNonEmpty(r, [
    'businessKey',
    'business_key',
    'BusinessKey',
    'instanceNo',
    'instance_no',
    'InstanceNo',
  ]);
  return v || '—';
}

function normalizeStatusText(row: WfEngineRuntimeTodoItem): string {
  const s = Number((row as unknown as Record<string, any>).status ?? 0);
  if (s === 2) return '已完成';
  if (s === 3) return '已驳回';
  if (s === 4) return '已删除';
  return '运行中';
}

const visibleColumns = computed(() => {
  if (activeTab.value === 'done') {
    return columns.map((c) =>
      c.key === 'receivedAt' ? { ...c, title: '处理时间', dataIndex: 'completedAt', key: 'completedAt' } : c,
    );
  }
  return columns;
});

async function load() {
  loading.value = true;
  try {
    const data = await wfEngineRuntimeTodoAll({
      box: activeTab.value,
      page: page.value,
      pageSize: pageSize.value,
    });
    rows.value = data.items || [];
    total.value = Number(data.total || 0);
  } catch {
    message.error('加载失败');
  } finally {
    loading.value = false;
  }
}

async function deleteSelectedTodos() {
  const ids = (selectedRowKeys.value || []).filter(Boolean);
  if (!ids.length) {
    message.warning('请先勾选要删除的待办');
    return;
  }
  deleteLoading.value = true;
  try {
    await wfEngineRuntimeDeleteTasks({ taskIds: ids });
    message.success(`已删除 ${ids.length} 条待办`);
    selectedRowKeys.value = [];
    await load();
  } catch (e: unknown) {
    message.error((e as Error)?.message || '删除失败');
  } finally {
    deleteLoading.value = false;
  }
}

function buildViewerQuery(row: WfEngineRuntimeTodoItem): Record<string, string> | null {
  const anyRow = row as unknown as Record<string, any>;
  function pick(...keys: string[]) {
    for (const k of keys) {
      const v = anyRow[k];
      if (v !== undefined && v !== null && String(v).trim()) return String(v).trim();
    }
    return '';
  }
  const instanceId = pick('instanceId', 'instance_id', 'InstanceId', 'INSTANCE_ID', 'instanceID', 'InstanceID');
  if (!instanceId) return null;
  const query: Record<string, string> = { instanceId };
  const processDefId = pick('processDefId', 'process_def_id', 'ProcessDefId', 'PROCESS_DEF_ID');
  const processCode = pick('processCode', 'process_code', 'ProcessCode', 'PROCESS_CODE');
  if (processDefId) query.processDefId = processDefId;
  if (processCode) query.processCode = processCode;
  return query;
}

function pickEmpField(row: Record<string, any>, keys: string[]): string {
  for (const k of keys) {
    const v = row[k];
    if (v !== undefined && v !== null && String(v).trim()) return String(v).trim();
  }
  return '';
}

function openViewerPicker(row: WfEngineRuntimeTodoItem) {
  const q = buildViewerQuery(row);
  if (!q) {
    const anyRow = row as unknown as Record<string, any>;
    const instanceNo = pickEmpField(anyRow, ['instanceNo', 'instance_no', 'InstanceNo', 'INSTANCE_NO']);
    message.warning(`该待办缺少实例ID（instanceId），无法打开查看页${instanceNo ? `：${instanceNo}` : ''}`);
    return;
  }
  viewerRow.value = row;
  const r = row as unknown as Record<string, any>;
  const uid = pickEmpField(r, ['assigneeUserId', 'assignee_user_id', 'AssigneeUserId']);
  const name = resolveAssigneeDisplayName(row);
  const code = resolveAssigneeWorkNo(row);
  viewerOptions.value = [];
  if (uid) {
    const label =
      [name !== '—' ? name : '', code !== '—' ? code : ''].filter(Boolean).join(' ') || uid;
    viewerOptions.value = [
      {
        value: uid,
        label: `${label}（本行待办人）`,
        name: name !== '—' ? name : undefined,
        empNo: code !== '—' ? code : undefined,
      },
    ];
    viewerIdentity.value = uid;
  } else {
    viewerIdentity.value = undefined;
  }
  viewerOpen.value = true;
}

function onViewerSearch(kw: string) {
  if (viewerSearchTimer) clearTimeout(viewerSearchTimer);
  viewerSearchTimer = setTimeout(() => void runViewerEmployeeSearch(kw), 320);
}

async function runViewerEmployeeSearch(keyword: string) {
  const kw = String(keyword || '').trim();
  if (!kw) return;
  viewerSearchLoading.value = true;
  try {
    const where = {
      Logic: 'AND',
      Conditions: [{ Field: 'leave_status', Operator: 'eq', Value: '0' }],
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
    const { items } = await queryForVbenPaged({
      TableName: 'v_t_base_employee',
      Page: 1,
      PageSize: 30,
      SortBy: 'EMP_ID',
      SortOrder: 'asc',
      Where: where,
    });
    viewerOptions.value = (items || [])
      .map((rec: Record<string, any>) => {
        const id = pickEmpField(rec, ['id', 'ID']);
        if (!id) return null;
        const empNo = pickEmpField(rec, ['EMP_ID', 'emp_id', 'code']);
        const nm = pickEmpField(rec, ['name', 'NAME', 'first_name']);
        return {
          value: id,
          label: `${nm || '—'} · ${empNo || id}`,
          name: nm || undefined,
          empNo: empNo || undefined,
        };
      })
      .filter((x): x is ViewerIdentityOption => !!x);
  } catch {
    message.error('搜索员工失败');
  } finally {
    viewerSearchLoading.value = false;
  }
}

function confirmViewerOpen() {
  const row = viewerRow.value;
  if (!row) return;
  const id = String(viewerIdentity.value || '').trim();
  if (!id) {
    message.warning('请选择要以谁的身份进入流程查看');
    return;
  }
  const base = buildViewerQuery(row);
  if (!base) {
    message.warning('缺少实例信息');
    return;
  }
  base.mockAssigneeUserId = id;
  const picked = viewerOptions.value.find((x) => String(x.value || '').trim() === id);
  if (picked?.name) base.mockAssigneeName = picked.name;
  if (picked?.empNo) base.mockAssigneeEmpNo = picked.empNo;
  const href = router.resolve({
    path: '/workflow/runtime-viewer',
    query: base,
  }).href;
  window.open(href, '_blank', 'noopener,noreferrer,width=1320,height=920');
  viewerOpen.value = false;
}

function openViewerMobilePreview(row: WfEngineRuntimeTodoItem) {
  const base = buildViewerQuery(row);
  if (!base) {
    const anyRow = row as unknown as Record<string, any>;
    const flowNo = resolveFlowNo(row);
    const instanceNo = pickEmpField(anyRow, ['instanceNo', 'instance_no', 'InstanceNo', 'INSTANCE_NO']);
    message.warning(
      `该待办缺少实例ID（instanceId），无法打开移动端预览${
        flowNo ? `：${flowNo}` : instanceNo ? `：${instanceNo}` : ''
      }`,
    );
    return;
  }
  const r = row as unknown as Record<string, any>;
  const uid = pickEmpField(r, ['assigneeUserId', 'assignee_user_id', 'AssigneeUserId']);
  if (!uid) {
    message.warning('该待办缺少办理人身份，无法打开移动端预览');
    return;
  }
  const query: Record<string, string> = {
    ...base,
    mockAssigneeUserId: uid,
    mode: 'mobile',
  };
  const href = router.resolve({
    path: '/workflow/runtime-viewer',
    query,
  }).href;
  window.open(href, '_blank', 'noopener,noreferrer,width=430,height=900');
}

function onTodoPageChange(p: number, ps: number) {
  page.value = p;
  pageSize.value = ps;
  load();
}

function onTabChange(key: string) {
  activeTab.value = (key as 'cc' | 'done' | 'todo') || 'todo';
  page.value = 1;
  selectedRowKeys.value = [];
  void load();
}

onMounted(() => {
  load();
});
</script>

<template>
  <Page>
    <Card size="small">
      <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
        <Tabs v-model:activeKey="activeTab" @change="onTabChange">
          <Tabs.TabPane key="todo" tab="待办" />
          <Tabs.TabPane key="cc" tab="抄送" />
          <Tabs.TabPane key="done" tab="已办" />
        </Tabs>
        <Button
          v-if="activeTab === 'todo'"
          danger
          :loading="deleteLoading"
          @click="deleteSelectedTodos"
        >
          删除
        </Button>
        <Button :loading="loading" @click="load">刷新</Button>
      </div>
      <Table
          :columns="visibleColumns"
          :data-source="rows"
          :loading="loading"
          row-key="taskId"
          :row-selection="
            activeTab === 'todo'
              ? {
                  selectedRowKeys,
                  onChange: onTodoSelectionChange,
                }
              : undefined
          "
          :pagination="{
            current: page,
            pageSize: pageSize,
            total: total,
            showSizeChanger: true,
            showTotal: (t: number) => `共 ${t} 条`,
            onChange: onTodoPageChange,
          }"
          :scroll="{ x: 1120 }"
          size="small"
      >
        <template #bodyCell="{ column, record }">
            <template v-if="column.key === 'receivedAt'">
              {{
                record.receivedAt ? new Date(record.receivedAt).toLocaleString() : '—'
              }}
            </template>
            <template v-else-if="column.key === 'completedAt'">
              {{
                (record as any).completedAt
                  ? new Date((record as any).completedAt).toLocaleString()
                  : '—'
              }}
            </template>
            <template v-else-if="column.key === 'flowNo'">
              <Button
                type="link"
                size="small"
                class="!px-0"
                @click="openViewerPicker(record as WfEngineRuntimeTodoItem)"
              >
                {{ resolveFlowNo(record as WfEngineRuntimeTodoItem) }}
              </Button>
            </template>
            <template v-else-if="column.key === 'assigneeWorkNo'">
              {{ resolveAssigneeWorkNo(record as WfEngineRuntimeTodoItem) }}
            </template>
            <template v-else-if="column.key === 'assigneeDisplayName'">
              {{ resolveAssigneeDisplayName(record as WfEngineRuntimeTodoItem) }}
            </template>
            <template v-else-if="column.key === 'statusText'">
              <Tag
                :color="
                  normalizeStatusText(record as WfEngineRuntimeTodoItem) === '已完成'
                    ? 'success'
                    : normalizeStatusText(record as WfEngineRuntimeTodoItem) === '已驳回'
                      ? 'error'
                      : 'processing'
                "
              >
                {{ normalizeStatusText(record as WfEngineRuntimeTodoItem) }}
              </Tag>
            </template>
            <template v-else-if="column.key === 'action'">
              <Space wrap>
                <Button
                  size="small"
                  @click="openViewerMobilePreview(record as WfEngineRuntimeTodoItem)"
                >
                  移动端预览
                </Button>
              </Space>
            </template>
        </template>
      </Table>
    </Card>

    <Modal
      v-model:open="viewerOpen"
      title="以指定身份查看流程"
      ok-text="打开查看页"
      cancel-text="取消"
      width="520px"
      destroy-on-close
      @ok="confirmViewerOpen"
    >
      <p class="mb-3 text-xs text-muted-foreground">
        选择员工后，将以该员工身份请求流程运行台（需后端开启 WorkflowEngine:AllowRuntimeMockUser）。
        默认带出本行待办人，可输入姓名或工号搜索其他在职员工。
      </p>
      <Form layout="vertical">
        <Form.Item label="查看身份（员工主键 id，与待办接口一致）" required>
          <Select
            v-model:value="viewerIdentity"
            show-search
            :filter-option="false"
            :options="viewerOptions"
            :loading="viewerSearchLoading"
            placeholder="输入姓名或工号搜索"
            allow-clear
            class="w-full"
            @search="onViewerSearch"
          />
        </Form.Item>
      </Form>
    </Modal>
  </Page>
</template>
