<script setup lang="ts">
import { onMounted, ref } from 'vue';

import { Page } from '@vben/common-ui';
import { Button, Card, Input, Modal, Space, Table, Tag, message } from 'ant-design-vue';
import { approveWorkflowTask, getWorkflowTodoTasks, rejectWorkflowTask } from '#/api/workflow';

interface TodoTaskItem {
  taskId: string;
  instanceId: string;
  node_name: string;
  assignee: string;
  created_at: string;
  process_code: string;
  process_name: string;
  business_key: string;
  status: string;
}

const loading = ref(false);
const tasks = ref<TodoTaskItem[]>([]);
const actionLoading = ref<string>('');
const comment = ref('');
const actionTask = ref<TodoTaskItem | null>(null);
const actionType = ref<'approve' | 'reject'>('approve');
const modalOpen = ref(false);

const columns = [
  { title: '流程编码', dataIndex: 'process_code', key: 'process_code', width: 160 },
  { title: '流程名称', dataIndex: 'process_name', key: 'process_name', width: 180 },
  { title: '业务Key', dataIndex: 'business_key', key: 'business_key', width: 160 },
  { title: '当前节点', dataIndex: 'node_name', key: 'node_name', width: 160 },
  { title: '处理人', dataIndex: 'assignee', key: 'assignee', width: 120 },
  { title: '创建时间', dataIndex: 'created_at', key: 'created_at', width: 180 },
];

async function loadTodos() {
  loading.value = true;
  try {
    const data = await getWorkflowTodoTasks();
    tasks.value = (data || []) as TodoTaskItem[];
  } finally {
    loading.value = false;
  }
}

function openAction(task: TodoTaskItem, type: 'approve' | 'reject') {
  actionTask.value = task;
  actionType.value = type;
  comment.value = '';
  modalOpen.value = true;
}

async function submitAction() {
  if (!actionTask.value) return;
  actionLoading.value = actionTask.value.taskId;
  try {
    const payload = {
      taskId: actionTask.value.taskId,
      comment: comment.value,
    };
    if (actionType.value === 'approve') {
      await approveWorkflowTask(payload);
      message.success('审批通过');
    } else {
      await rejectWorkflowTask(payload);
      message.success('已驳回');
    }
    modalOpen.value = false;
    await loadTodos();
  } finally {
    actionLoading.value = '';
  }
}

onMounted(() => {
  loadTodos();
});
</script>

<template>
  <Page title="流程待办中心" description="展示当前登录人待办任务，可直接同意/驳回">
    <div class="p-4">
      <Card size="small">
        <div class="mb-3 flex justify-end">
          <Button @click="loadTodos" :loading="loading">刷新</Button>
        </div>
        <Table
          :columns="columns"
          :data-source="tasks"
          :loading="loading"
          row-key="taskId"
          :pagination="{ pageSize: 20 }"
          :scroll="{ x: 1100 }"
          size="small"
        >
          <template #bodyCell="{ column, record }">
            <template v-if="column.key === 'process_name'">
              <Space>
                <span>{{ record.process_name }}</span>
                <Tag color="processing">{{ record.status }}</Tag>
              </Space>
            </template>
            <template v-else-if="column.key === 'created_at'">
              {{ new Date(record.created_at).toLocaleString() }}
            </template>
          </template>
          <template #expandedRowRender="{ record }">
            <div class="flex flex-wrap gap-2">
              <Button
                type="primary"
                size="small"
                :loading="actionLoading === record.taskId"
                @click="openAction(record, 'approve')"
              >
                同意
              </Button>
              <Button
                danger
                size="small"
                :loading="actionLoading === record.taskId"
                @click="openAction(record, 'reject')"
              >
                驳回
              </Button>
              <Tag color="blue">实例: {{ record.instanceId }}</Tag>
              <Tag color="purple">任务: {{ record.taskId }}</Tag>
            </div>
          </template>
        </Table>
      </Card>
    </div>

    <Modal
      v-model:open="modalOpen"
      :title="actionType === 'approve' ? '审批通过' : '驳回任务'"
      @ok="submitAction"
      :confirm-loading="!!actionLoading"
    >
      <Input.TextArea
        v-model:value="comment"
        :rows="4"
        :placeholder="actionType === 'approve' ? '审批意见（可选）' : '驳回原因（建议填写）'"
      />
    </Modal>
  </Page>
</template>
