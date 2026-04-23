<script setup lang="ts">
import { onMounted, ref } from 'vue';

import { Page } from '@vben/common-ui';
import { Button, Card, Input, Select, message } from 'ant-design-vue';
import {
  getPublishedWorkflowDefinitions,
  startWorkflowInstance,
} from '#/api/workflow';

const processCode = ref('WF_LEAVE_DEMO');
const businessKey = ref('');
const comment = ref('');
const formDataJson = ref(
  JSON.stringify(
    {
      amount: 1200,
      dept: '研发部',
      applicant: '张三',
      reason: '设备采购',
      /** 供流程出口条件 scope=initiator 使用（与流程设计器约定一致） */
      $initiator: {
        userId: '',
        departmentId: 'dept-demo-001',
        securityLevel: 2,
        roleCodes: ['R_STAFF'],
        positionIds: [],
      },
    },
    null,
    2,
  ),
);
const loading = ref(false);
const loadingDefinitions = ref(false);
const resultInstanceId = ref('');
const processOptions = ref<{ label: string; value: string }[]>([]);

async function loadPublishedDefinitions() {
  loadingDefinitions.value = true;
  try {
    const data = await getPublishedWorkflowDefinitions();
    processOptions.value = ((data || []) as any[]).map((item) => ({
      label: `${item.processName} (${item.processCode}) v${item.publishedVersion ?? '-'}`,
      value: item.processCode,
    }));
  } finally {
    loadingDefinitions.value = false;
  }
}

async function submitStart() {
  if (!processCode.value.trim()) {
    message.warning('请填写流程编码');
    return;
  }

  let normalizedFormData = '{}';
  try {
    const parsed = formDataJson.value?.trim()
      ? JSON.parse(formDataJson.value)
      : {};
    normalizedFormData = JSON.stringify(parsed);
  } catch {
    message.error('表单 JSON 格式不正确');
    return;
  }

  loading.value = true;
  try {
    const resp = await startWorkflowInstance({
      processCode: processCode.value.trim(),
      businessKey: businessKey.value.trim() || undefined,
      comment: comment.value.trim() || undefined,
      formDataJson: normalizedFormData,
    });
    resultInstanceId.value = resp?.instanceId || '';
    message.success('流程发起成功');
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  loadPublishedDefinitions();
});
</script>

<template>
  <Page
    title="发起流程"
    description="表单 JSON 可包含 $initiator（部门/角色/岗位/安全系数等），供设计器里「发起人上下文」类出口条件求值。"
  >
    <div class="p-4">
      <Card size="small" title="发起参数">
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
          <div>
            <div class="mb-1 text-xs text-muted-foreground">流程编码</div>
            <Select
              v-model:value="processCode"
              show-search
              allow-clear
              :options="processOptions"
              :loading="loadingDefinitions"
              placeholder="选择已发布流程（也可手输）"
              class="w-full"
            />
            <Input
              v-model:value="processCode"
              class="mt-2"
              placeholder="可手输流程编码，例如：WF_LEAVE_DEMO"
            />
          </div>
          <div>
            <div class="mb-1 text-xs text-muted-foreground">业务 Key（可选）</div>
            <Input v-model:value="businessKey" placeholder="例如：ORDER-20260401-001" />
          </div>
          <div class="lg:col-span-2">
            <div class="mb-1 text-xs text-muted-foreground">备注（可选）</div>
            <Input v-model:value="comment" placeholder="发起说明" />
          </div>
          <div class="lg:col-span-2">
            <div class="mb-1 text-xs text-muted-foreground">表单 JSON</div>
            <Input.TextArea
              v-model:value="formDataJson"
              :rows="12"
              placeholder='例如：{"amount":1200,"dept":"研发部"}'
            />
          </div>
        </div>

        <div class="mt-4 flex flex-wrap items-center gap-2">
          <Button type="primary" :loading="loading" @click="submitStart">
            发起流程
          </Button>
          <span v-if="resultInstanceId" class="text-sm text-green-600">
            instanceId: {{ resultInstanceId }}
          </span>
        </div>
      </Card>
    </div>
  </Page>
</template>
