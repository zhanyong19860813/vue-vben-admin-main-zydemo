<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';

import { Page } from '@vben/common-ui';
import { useUserStore } from '@vben/stores';
import { Button, Card, Input, Select, Table, Tabs, Tag, message } from 'ant-design-vue';
import LogicFlow from '@logicflow/core';
import { useVbenForm } from '#/adapter/form';

import { buildWorkflowBuiltinValuesFromUser } from '#/views/demos/form-designer/workflowFormRuntime';

import {
  getAllWorkflowDefinitions,
  getWorkflowDefinition,
  getWorkflowFormBinding,
  getWorkflowFormSchemaList,
  saveWorkflowFormBinding,
} from '#/api/workflow';
import '@logicflow/core/es/style/index.css';

type WorkflowVer = {
  processCode: string;
  processName: string;
  version: number;
  status?: string;
};

type FormRec = {
  id: string;
  code: string;
  title?: string;
  schemaJson?: string;
};

const workflowRows = ref<WorkflowVer[]>([]);
const workflowCode = ref('');
const workflowVersion = ref<number | null>(null);
const workflowJson = ref('');
const workflowGraphData = ref<any>(null);
const workflowCanvasRef = ref<HTMLElement | null>(null);
const workflowPreviewTab = ref<'graph' | 'list'>('graph');
let lf: LogicFlow | null = null;

const formRows = ref<FormRec[]>([]);
const formCode = ref('');
const formJson = ref('');
const formSchemaPreview = ref<any[]>([]);

const userStore = useUserStore();

const saving = ref(false);
const loadingWorkflows = ref(false);
const loadingForms = ref(false);
const flowListColumns = [
  { title: '序号', dataIndex: 'index', width: 68 },
  { title: '节点', dataIndex: 'nodeName', width: 140 },
  { title: '类型', dataIndex: 'actionType', width: 96 },
  { title: '审批人/抄送', dataIndex: 'actor', width: 180 },
  { title: '状态', dataIndex: 'status', width: 110 },
  { title: '时间', dataIndex: 'time', width: 170 },
  { title: '备注', dataIndex: 'remark' },
];

const workflowCodeOptions = computed(() => {
  const map = new Map<string, string>();
  for (const r of workflowRows.value) {
    if (!map.has(r.processCode)) map.set(r.processCode, r.processName || r.processCode);
  }
  return Array.from(map.entries()).map(([value, label]) => ({ value, label }));
});

const workflowVersionOptions = computed(() =>
  workflowRows.value
    .filter((x) => x.processCode === workflowCode.value)
    .sort((a, b) => b.version - a.version)
    .map((x) => ({
      value: x.version,
      label: `v${x.version} · ${x.status || 'draft'}`,
    })),
);

const formOptions = computed(() =>
  formRows.value.map((x) => ({
    value: x.code,
    label: `${x.code}${x.title ? ` - ${x.title}` : ''}`,
  })),
);

const flowListRows = computed(() => {
  const graph = workflowGraphData.value;
  const nodes: any[] = Array.isArray(graph?.nodes) ? graph.nodes : [];
  if (!nodes.length) return [];
  const sorted = [...nodes].sort((a, b) => {
    const ay = Number(a?.y ?? 0);
    const by = Number(b?.y ?? 0);
    if (ay !== by) return ay - by;
    return Number(a?.x ?? 0) - Number(b?.x ?? 0);
  });
  return sorted.map((n, idx) => {
    const bizType = String(n?.properties?.bizType ?? '').toLowerCase();
    const assignee = String(n?.properties?.assignee ?? '').trim();
    const isStart = bizType === 'start';
    const isEnd = bizType === 'end';
    const actionType = isStart ? '发起' : isEnd ? '结束' : '审批';
    return {
      key: n?.id ?? `${idx + 1}`,
      index: idx + 1,
      nodeName: n?.text?.value || n?.properties?.title || n?.id || `节点${idx + 1}`,
      actionType,
      actor: assignee || (isStart ? '发起人' : '--'),
      status: isStart ? '已完成' : isEnd ? '未到达' : '待处理',
      time: '--',
      remark: isEnd ? '流程结束节点' : '',
    };
  });
});

const [PreviewForm, previewFormApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as any[],
  wrapperClass: 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
  layout: 'horizontal',
  formItemGapPx: 2 as any,
  commonConfig: { labelWidth: 110 } as any,
});

async function loadWorkflows() {
  loadingWorkflows.value = true;
  try {
    const data = (await getAllWorkflowDefinitions()) as WorkflowVer[];
    workflowRows.value = Array.isArray(data) ? data : [];
  } finally {
    loadingWorkflows.value = false;
  }
}

async function loadForms() {
  loadingForms.value = true;
  try {
    const data = (await getWorkflowFormSchemaList()) as FormRec[];
    formRows.value = Array.isArray(data) ? data : [];
  } finally {
    loadingForms.value = false;
  }
}

async function refreshWorkflowPreview() {
  if (!workflowCode.value || !workflowVersion.value) {
    workflowJson.value = '';
    return;
  }
  const data = (await getWorkflowDefinition({
    processCode: workflowCode.value,
    version: workflowVersion.value,
  })) as any;
  const raw = data?.definition_json ?? '';
  if (!raw) {
    workflowJson.value = '';
    workflowGraphData.value = null;
    return;
  }
  const parsed = JSON.parse(raw);
  workflowJson.value = JSON.stringify(parsed, null, 2);
  workflowGraphData.value = parsed?.graphData ?? parsed ?? null;
}

async function refreshFormPreview() {
  const f = formRows.value.find((x) => x.code === formCode.value);
  const raw = f?.schemaJson ?? '';
  try {
    const parsed = raw ? JSON.parse(raw) : null;
    formJson.value = parsed ? JSON.stringify(parsed, null, 2) : '';
    const srcSchema = Array.isArray(parsed?.schema) ? parsed.schema : [];
    // 多行文本在双列布局里跨整行，避免右侧空洞造成“间隔很大”的观感
    formSchemaPreview.value = srcSchema.map((s: any) => {
      const cp = s?.componentProps ?? {};
      const isTextarea =
        String(s?.component ?? '').toLowerCase().includes('textarea') ||
        String(cp?.type ?? '').toLowerCase() === 'textarea' ||
        typeof cp?.rows === 'number';
      if (!isTextarea) return s;
      return {
        ...s,
        componentProps: {
          ...cp,
          rows: 1,
          autoSize: false,
          showCount: false,
        },
        formItemClass: [s?.formItemClass, 'md:col-span-2'].filter(Boolean).join(' '),
      };
    });
    previewFormApi.setState({ schema: formSchemaPreview.value as any });
    await nextTick();
    /** 流程表单内置字段：预览区与列表弹窗一致，从当前登录用户与时间填充 */
    const wf = buildWorkflowBuiltinValuesFromUser(formSchemaPreview.value as any, {
      userInfo: userStore.userInfo as any,
      workflowNoPrefix: parsed?.workflowNoPrefix,
    });
    await previewFormApi.setValues(wf);
  } catch {
    formJson.value = raw;
    formSchemaPreview.value = [];
    previewFormApi.setState({ schema: [] as any[] });
    await nextTick();
    await previewFormApi.setValues({});
  }
}

function renderWorkflowGraph() {
  if (!workflowCanvasRef.value) return;
  if (!lf) {
    lf = new LogicFlow({
      container: workflowCanvasRef.value,
      grid: false,
      stopMoveGraph: false,
      stopZoomGraph: false,
      keyboard: { enabled: false },
      edgeTextDraggable: false,
    });
  }
  const data = workflowGraphData.value;
  lf.render(
    data && data.nodes && data.edges ? data : { nodes: [], edges: [] },
  );
  lf.translateCenter();
}

async function tryLoadBinding() {
  if (!workflowCode.value || !workflowVersion.value) return;
  try {
    const row = (await getWorkflowFormBinding({
      processCode: workflowCode.value,
      processVersion: workflowVersion.value,
    })) as any;
    const fc = String(row?.formCode ?? '').trim();
    if (fc) {
      formCode.value = fc;
      refreshFormPreview();
    }
  } catch {
    // ignore when not bound
  }
}

watch(workflowCode, (v) => {
  if (!v) {
    workflowVersion.value = null;
    workflowJson.value = '';
    return;
  }
  const first = workflowVersionOptions.value[0];
  workflowVersion.value = first ? Number(first.value) : null;
});

watch([workflowCode, workflowVersion], async () => {
  await refreshWorkflowPreview();
  await tryLoadBinding();
  await nextTick();
  if (workflowPreviewTab.value === 'graph') renderWorkflowGraph();
});

watch(formCode, () => refreshFormPreview());
watch(workflowPreviewTab, async (v) => {
  if (v !== 'graph') return;
  await nextTick();
  renderWorkflowGraph();
});

async function saveBinding() {
  if (!workflowCode.value || !workflowVersion.value || !formCode.value) {
    message.warning('请先选择流程版本和表单');
    return;
  }
  const form = formRows.value.find((x) => x.code === formCode.value);
  saving.value = true;
  try {
    await saveWorkflowFormBinding({
      processCode: workflowCode.value,
      processVersion: Number(workflowVersion.value),
      formCode: formCode.value,
      formRecordId: form?.id,
    });
    message.success('绑定已保存');
  } finally {
    saving.value = false;
  }
}

onMounted(async () => {
  await Promise.all([loadWorkflows(), loadForms()]);
  await nextTick();
  renderWorkflowGraph();
});

onBeforeUnmount(() => {
  lf?.destroy();
  lf = null;
});
</script>

<template>
  <Page title="流程-表单绑定" description="选择已设计的流程 schema 与表单 schema，保存绑定并即时预览。">
    <div class="workflow-binding-page flex flex-col gap-[2px] p-[6px]">
      <Card size="small" title="绑定配置">
        <div class="grid grid-cols-1 gap-[2px] md:grid-cols-3">
          <Select
            v-model:value="workflowCode"
            :loading="loadingWorkflows"
            :options="workflowCodeOptions"
            class="w-full"
            allow-clear
            placeholder="选择流程编码"
          />
          <Select
            v-model:value="workflowVersion"
            :options="workflowVersionOptions"
            :disabled="!workflowCode"
            class="w-full"
            allow-clear
            placeholder="选择流程版本"
          />
          <Select
            v-model:value="formCode"
            :loading="loadingForms"
            :options="formOptions"
            class="w-full"
            allow-clear
            placeholder="选择表单编码"
          />
        </div>
        <div class="mt-[2px]">
          <Button type="primary" :loading="saving" @click="saveBinding">保存绑定</Button>
        </div>
      </Card>

      <Card size="small" title="一体化预览">
        <div class="preview-stack">
          <div v-if="formSchemaPreview.length" class="compact-form-preview rounded border border-border p-[2px]">
            <div class="form-scroll-area">
              <PreviewForm />
            </div>
          </div>
          <div v-else class="rounded border border-dashed border-border p-4 text-center text-sm text-muted-foreground form-scroll-area">
            请选择表单后预览界面
          </div>

          <div class="preview-divider"></div>
          <div class="workflow-tabs-wrap">
            <Tabs v-model:active-key="workflowPreviewTab" size="small">
              <Tabs.TabPane key="list" tab="流程列表">
                <Table
                  :columns="flowListColumns"
                  :data-source="flowListRows"
                  :pagination="false"
                  size="small"
                  row-key="key"
                  :scroll="{ y: 300 }"
                >
                  <template #bodyCell="{ column, record }">
                    <template v-if="column.dataIndex === 'status'">
                      <Tag
                        :color="record.status === '已完成' ? 'success' : record.status === '待处理' ? 'processing' : 'default'"
                      >
                        {{ record.status }}
                      </Tag>
                    </template>
                  </template>
                </Table>
              </Tabs.TabPane>
              <Tabs.TabPane key="graph" tab="流程图">
                <div ref="workflowCanvasRef" class="workflow-preview-canvas"></div>
              </Tabs.TabPane>
            </Tabs>
          </div>
        </div>
      </Card>

      <div class="grid grid-cols-1 gap-[2px] xl:grid-cols-2">
        <Card size="small" title="流程 Schema JSON">
          <Input.TextArea :value="workflowJson" :rows="12" readonly placeholder="选择流程后显示 JSON" />
        </Card>
        <Card size="small" title="表单 Schema JSON">
          <Input.TextArea :value="formJson" :rows="12" readonly placeholder="选择表单后显示 JSON" />
        </Card>
      </div>
    </div>
  </Page>
</template>

<style scoped>
.workflow-binding-page {
  background: linear-gradient(180deg, #eef3f9 0%, #f5f7fb 100%);
  --wb-control-height: 34px;
  border-radius: 6px;
}

.workflow-preview-canvas {
  height: 360px;
  border: 1px solid #d7e0ea;
  border-radius: 2px;
  background: #ffffff;
  margin-top: -1px;
}

.form-scroll-area {
  height: 360px;
  overflow: auto;
  padding-right: 0;
}

.preview-divider {
  height: 12px;
  margin: 0;
  border-top: 1px solid #e6edf5;
  border-bottom: 1px solid #eef3f9;
  background: linear-gradient(180deg, #f8fbff 0%, #f2f6fb 100%);
  box-shadow: inset 0 1px 0 rgb(255 255 255 / 70%);
}

.workflow-tabs-wrap {
  background: #fff;
}

:deep(.workflow-tabs-wrap .ant-tabs-nav) {
  margin-bottom: 2px;
}

:deep(.ant-card .ant-card-body) {
  padding: 8px 10px;
}

:deep(.ant-card) {
  border-radius: 4px;
  border: 1px solid #d7e0ea;
  background: #fff;
  box-shadow: 0 1px 2px rgb(15 23 42 / 4%);
}

:deep(.ant-card .ant-card-head) {
  min-height: 34px;
  padding: 0 10px;
  border-bottom: 1px solid #e3eaf2;
  background: #f6f9fc;
}

:deep(.ant-card .ant-card-head-title) {
  padding: 6px 0;
  font-size: 13px;
  font-weight: 600;
  color: #274c77;
}

:deep(.ant-select-selector),
:deep(.ant-input),
:deep(.ant-input-number),
:deep(.ant-picker) {
  border-radius: 2px !important;
  border-color: #cfd8e3 !important;
  background: #fff !important;
}

:deep(.ant-select-focused .ant-select-selector),
:deep(.ant-input:focus),
:deep(.ant-picker-focused) {
  border-color: #7fa3c7 !important;
  box-shadow: 0 0 0 2px rgb(66 133 244 / 10%) !important;
}

:deep(.ant-btn-primary) {
  border-radius: 2px;
  background: #2b6cb0;
  border-color: #2b6cb0;
}

:deep(.ant-btn-primary:hover) {
  background: #245f9d;
  border-color: #245f9d;
}

:deep(.compact-form-preview .ant-form-item) {
  margin-bottom: 0 !important;
}

:deep(.compact-form-preview .ant-row) {
  row-gap: 2px !important;
  column-gap: 2px !important;
}

/* vben form-field 默认会加 pb-4/pb-2，直接清零 */
:deep(.compact-form-preview .pb-4),
:deep(.compact-form-preview .pb-2) {
  padding-bottom: 0 !important;
}

:deep(.compact-form-preview .ant-form-item-explain),
:deep(.compact-form-preview .ant-form-item-extra) {
  min-height: 0 !important;
  margin-top: 0 !important;
}

:deep(.compact-form-preview .ant-form-item-control-input-content > *) {
  width: 100%;
}

:deep(.compact-form-preview .ant-form-item-row) {
  align-items: center;
}

:deep(.compact-form-preview .ant-form-item-label > label) {
  font-size: 12px;
}

:deep(.compact-form-preview .ant-form-item-label) {
  padding: 0 4px 0 0 !important;
  min-height: var(--wb-control-height);
  line-height: var(--wb-control-height);
}

:deep(.compact-form-preview .ant-form-item-control) {
  min-height: var(--wb-control-height);
}

:deep(.compact-form-preview .ant-input),
:deep(.compact-form-preview .ant-input-number),
:deep(.compact-form-preview .ant-input-textarea),
:deep(.compact-form-preview .ant-picker),
:deep(.compact-form-preview .ant-select) {
  width: 100%;
}

:deep(.compact-form-preview .ant-input),
:deep(.compact-form-preview .ant-picker),
:deep(.compact-form-preview .ant-select-selector) {
  height: var(--wb-control-height) !important;
}

:deep(.compact-form-preview .ant-input-number) {
  width: 100%;
  height: var(--wb-control-height) !important;
}

:deep(.compact-form-preview .ant-input-number-input-wrap),
:deep(.compact-form-preview .ant-input-number-input) {
  height: var(--wb-control-height) !important;
  line-height: var(--wb-control-height) !important;
}

:deep(.compact-form-preview .ant-select-selection-item),
:deep(.compact-form-preview .ant-select-selection-placeholder),
:deep(.compact-form-preview .ant-picker-input > input) {
  line-height: calc(var(--wb-control-height) - 2px) !important;
}

:deep(.compact-form-preview .ant-input-textarea textarea) {
  min-height: var(--wb-control-height);
  height: auto !important;
  line-height: 1.4;
  padding-top: 2px;
  padding-bottom: 2px;
}

:deep(.compact-form-preview .ant-input-textarea-show-count::after) {
  margin-top: 0 !important;
  margin-bottom: 0 !important;
  line-height: 1 !important;
}

:deep(.compact-form-preview .ant-input-textarea-show-count) {
  padding-bottom: 0 !important;
}

/* 多行文本项占整行，避免双列布局产生大块空白 */
:deep(.compact-form-preview .flex-shrink-0:has(.ant-input-textarea)),
:deep(.compact-form-preview .flex-shrink-0:has(textarea)) {
  grid-column: 1 / -1 !important;
}
</style>

