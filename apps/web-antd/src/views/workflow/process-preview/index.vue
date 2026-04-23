<script setup lang="ts">
import type { Component as VueConcreteComponent } from 'vue';
import { computed, nextTick, onMounted, ref, shallowRef, watch } from 'vue';
import { useRoute } from 'vue-router';

import { Page } from '@vben/common-ui';
import { useUserStore } from '@vben/stores';
import { useAuthStore } from '#/store/auth';

import type { VbenFormSchema } from '#/adapter/form';
import { useVbenForm } from '#/adapter/form';
import { buildWorkflowBuiltinValuesFromUser } from '#/views/demos/form-designer/workflowFormRuntime';
import FormTabsTablePreview from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import type { TabFieldDisplayRule } from '#/views/demos/form-designer/FormTabsTablePreview.vue';

import {
  Button,
  Card,
  message,
  Steps,
  Table,
  Tabs,
  Tag,
  Timeline,
} from 'ant-design-vue';

import type { WfProcessPreviewBoundForm, WfProcessPreviewJson } from './types';
import {
  WF_PROCESS_PREVIEW_LOCAL_KEY,
  WF_PROCESS_PREVIEW_SESSION_KEY,
  isWfProcessPreviewJson,
} from './types';
import ProcessPreviewShell from './ProcessPreviewShell.vue';
import { createExtWorkflowFormComponent } from '#/views/workflowExtForm/registry';

const userStore = useUserStore();
const authStore = useAuthStore();
const route = useRoute();

const model = ref<WfProcessPreviewJson | null>(null);
const loadError = ref('');

const previewFieldRules = ref<Record<string, TabFieldDisplayRule>>({});
const mainFormTabsSchema = ref<VbenFormSchema[]>([]);
const mainBuiltinValues = ref<Record<string, any>>({});
const activeStep = ref(0);
const activeNodeKey = ref('');
const extRuntimeRoot = shallowRef<VueConcreteComponent | null>(null);

const detailColumns = [
  { title: '字段', dataIndex: 'field', key: 'field', width: 160 },
  { title: '值', dataIndex: 'value', key: 'value' },
];
const isMobilePreviewMode = computed(() => String(route.query.mode || '') === 'mobile');

/** 流程元信息：移动端单列「标签 + 值」逐行展示 */
const metaRows = computed(() => {
  const m = model.value?.meta;
  if (!m) return [];
  return [
    { key: 'processNo', label: '流程编号', text: m.processNo, isStatus: false },
    { key: 'formTitle', label: '表单标题', text: m.formTitle, isStatus: false },
    { key: 'initiator', label: '发起人', text: m.initiator, isStatus: false },
    { key: 'dept', label: '发起部门', text: m.dept, isStatus: false },
    { key: 'startTime', label: '发起时间', text: m.startTime, isStatus: false },
    {
      key: 'status',
      label: '当前状态',
      text: m.status.text,
      isStatus: true,
      statusColor: m.status.color,
    },
  ];
});

const showDevDebugLine = import.meta.env.DEV;

const debugNodeBindingLine = computed(() => {
  const selected = selectedNodeBoundForm.value;
  if (selected) {
    return `debug.node nodeId=${selected.nodeKey || '∅'}, nodeTitle=${selected.nodeTitle || '∅'}, formCode=${selected.formCode || '∅'}, layout=${selected.previewLayout}`;
  }
  return `debug.node nodeId=${activeNodeKey.value || '∅'}, nodeTitle=∅, formCode=∅, layout=${model.value?.previewLayout || 'table'}`;
});

function buildPreviewUserInfoSeed() {
  const u = (userStore.userInfo || {}) as Record<string, any>;
  const employeeNo =
    String(
      u.employeeCode || u.employeeNo || u.workNo || u.jobNo || u.empNo || u.userCode || u.code || u.username || '',
    ).trim();
  const position =
    String(
      u.positionName || u.dutyName || u.postName || u.position || u.post || u.title || u.jobTitle || '',
    ).trim();
  const hasName = String(u.realName || u.name || '').trim();
  if (hasName && employeeNo && position) return u;
  const m = model.value?.meta;
  if (!m) {
    return {
      ...u,
      employeeCode: employeeNo || u.employeeCode,
      positionName: position || u.positionName,
    };
  }
  return {
    ...u,
    realName: m.initiator || u.realName,
    name: m.initiator || u.name,
    deptName: m.dept || u.deptName,
    departmentName: m.dept || u.departmentName,
    employeeCode: employeeNo || u.employeeCode || u.userCode || u.username,
    employeeNo: employeeNo || u.employeeNo || u.userCode || u.username,
    positionName: position || u.positionName || u.dutyName || u.postName || '当前登录人岗位',
    dutyName: position || u.dutyName || u.positionName || u.postName || '当前登录人岗位',
  };
}

function needsFetchUserInfo(u: Record<string, any> | null | undefined): boolean {
  const x = (u || {}) as Record<string, any>;
  const hasName = String(x.realName || x.name || '').trim();
  const hasEmp = String(x.employeeCode || x.employeeNo || x.userCode || x.username || '').trim();
  const hasPos = String(x.positionName || x.dutyName || x.postName || x.position || '').trim();
  return !(hasName && hasEmp && hasPos);
}

const selectedNodeBoundForm = computed<WfProcessPreviewBoundForm | null>(() => {
  const m = model.value;
  if (!m || !activeNodeKey.value) return null;
  return m.nodeBoundForms?.[activeNodeKey.value] ?? null;
});

const activeExtFormKey = computed(() => {
  const s = selectedNodeBoundForm.value;
  if (s?.previewLayout === 'extComponent' && s.extFormKey) return s.extFormKey;
  const m = model.value;
  if (
    !selectedNodeBoundForm.value &&
    m?.previewLayout === 'extComponent' &&
    m.startExtFormKey
  ) {
    return m.startExtFormKey;
  }
  return '';
});

const showBusinessTable = computed(() => {
  const m = model.value;
  if (!m) return false;
  if (selectedNodeBoundForm.value) return false;
  if (!activeNodeKey.value && (m.previewLayout === 'startForm' || m.previewLayout === 'startFormTabs')) {
    return false;
  }
  return true;
});

const isTabsBoundForm = computed(
  () =>
    selectedNodeBoundForm.value?.previewLayout === 'startFormTabs' &&
    Array.isArray(selectedNodeBoundForm.value?.tabs) &&
    (selectedNodeBoundForm.value?.tabs?.length ?? 0) > 0,
);

const [PreviewForm, previewFormApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as VbenFormSchema[],
  wrapperClass: 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
  layout: 'horizontal',
  formItemGapPx: 2 as any,
  commonConfig: { labelWidth: 110 } as any,
});

watch(
  isMobilePreviewMode,
  async (mob) => {
    await previewFormApi.setState({
      layout: mob ? 'vertical' : 'horizontal',
      wrapperClass: mob
        ? 'grid-cols-1 gap-y-2'
        : 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
      commonConfig: mob ? ({ labelWidth: 72 } as any) : ({ labelWidth: 110 } as any),
    });
  },
  { immediate: true },
);

watch(
  () => [model.value, activeNodeKey.value, activeExtFormKey.value, userStore.userInfo] as const,
  async ([m]) => {
    const extKey = activeExtFormKey.value;
    if (extKey) {
      const comp = createExtWorkflowFormComponent(extKey);
      extRuntimeRoot.value = comp as any;
      previewFieldRules.value = {};
      mainFormTabsSchema.value = [];
      mainBuiltinValues.value = {};
      await previewFormApi.setState({ schema: [] as VbenFormSchema[] });
      await previewFormApi.setValues({});
      return;
    }
    extRuntimeRoot.value = null;
    const selected = selectedNodeBoundForm.value;
    if (selected) {
      previewFieldRules.value = { ...(selected.fieldRules as Record<string, TabFieldDisplayRule>) };
      const schema = (selected.schema || []) as unknown as VbenFormSchema[];
      if (selected.previewLayout === 'startFormTabs' && selected.tabs?.length) {
        mainFormTabsSchema.value = schema;
        mainBuiltinValues.value = buildWorkflowBuiltinValuesFromUser(schema, {
          userInfo: buildPreviewUserInfoSeed() as any,
          workflowNoPrefix: selected.workflowNoPrefix,
        });
        await previewFormApi.setState({ schema: [] as VbenFormSchema[] });
        await previewFormApi.setValues({});
        return;
      }
      mainFormTabsSchema.value = [];
      await previewFormApi.setState({ schema });
      await nextTick();
      const vals = buildWorkflowBuiltinValuesFromUser(schema, {
        userInfo: buildPreviewUserInfoSeed() as any,
        workflowNoPrefix: selected.workflowNoPrefix,
      });
      await previewFormApi.setValues(vals);
      return;
    }

    previewFieldRules.value = { ...(m?.startFormFieldRules as Record<string, TabFieldDisplayRule>) };
    if (!m?.startFormSchema?.length) {
      mainFormTabsSchema.value = [];
      mainBuiltinValues.value = {};
      await previewFormApi.setState({ schema: [] as VbenFormSchema[] });
      await previewFormApi.setValues({});
      return;
    }
    const schema = m.startFormSchema as unknown as VbenFormSchema[];
    if (m.previewLayout === 'startFormTabs' && m.startFormTabs?.length) {
      mainFormTabsSchema.value = schema;
      mainBuiltinValues.value = buildWorkflowBuiltinValuesFromUser(schema, {
        userInfo: userStore.userInfo as any,
        workflowNoPrefix: m.startFormWorkflowNoPrefix,
      });
      await previewFormApi.setState({ schema: [] as VbenFormSchema[] });
      await previewFormApi.setValues({});
      return;
    }
    mainFormTabsSchema.value = [];
    await previewFormApi.setState({ schema });
    await nextTick();
    const vals = buildWorkflowBuiltinValuesFromUser(schema, {
      userInfo: buildPreviewUserInfoSeed() as any,
      workflowNoPrefix: m.startFormWorkflowNoPrefix,
    });
    await previewFormApi.setValues(vals);
  },
  { immediate: true },
);

const stepItems = computed(() => {
  const nodes = model.value?.nodes ?? [];
  return nodes.map((node, idx) => ({
    title: node.title,
    description: `${node.owner}${model.value?.nodeBoundForms?.[node.key] ? ' · 已绑表单' : ''}`,
    status:
      idx < activeStep.value
        ? ('finish' as const)
        : idx === activeStep.value
          ? ('process' as const)
          : ('wait' as const),
  }));
});

watch(
  () => model.value,
  (m) => {
    const nodes = m?.nodes ?? [];
    if (!nodes.length) {
      activeStep.value = 0;
      activeNodeKey.value = '';
      return;
    }
    const idx = Math.max(0, nodes.findIndex((n) => n.status === 'process'));
    activeStep.value = idx;
    activeNodeKey.value = nodes[idx]?.key ?? nodes[0]?.key ?? '';
  },
  { immediate: true },
);

function parsePayload(raw: string): WfProcessPreviewJson | null {
  try {
    const v = JSON.parse(raw) as unknown;
    return isWfProcessPreviewJson(v) ? v : null;
  } catch {
    return null;
  }
}

function onPreviewFieldRulesUpdate(v: Record<string, TabFieldDisplayRule>) {
  previewFieldRules.value = v;
}

function onStepChange(step: number) {
  const nodes = model.value?.nodes ?? [];
  const node = nodes[step];
  if (!node) return;
  activeStep.value = step;
  activeNodeKey.value = node.key;
}

onMounted(async () => {
  if (needsFetchUserInfo(userStore.userInfo as any)) {
    try {
      await authStore.fetchUserInfo();
    } catch {
      // ignore; preview seed will fallback to meta values
    }
  }
  let raw = '';
  try {
    raw = sessionStorage.getItem(WF_PROCESS_PREVIEW_SESSION_KEY) ?? '';
  } catch {
    raw = '';
  }
  if (!raw) {
    try {
      raw = localStorage.getItem(WF_PROCESS_PREVIEW_LOCAL_KEY) ?? '';
    } catch {
      raw = '';
    }
  }
  if (raw) {
    const parsed = parsePayload(raw);
    if (parsed) {
      model.value = parsed;
      return;
    }
  }

  const base = (import.meta.env.BASE_URL || '/').replace(/\/?$/, '/');
  const url = `${base}workflow/process-preview-demo.json`;
  try {
    const res = await fetch(url, { cache: 'no-store' });
    if (!res.ok) throw new Error(String(res.status));
    const parsed = parsePayload(await res.text());
    if (parsed) {
      model.value = parsed;
      return;
    }
    loadError.value = 'JSON 格式不符合预览契约';
  } catch {
    loadError.value =
      '未找到预览数据：请从流程管理点击「预览」，或确保 public/workflow/process-preview-demo.json 可访问';
  }
  message.warning(loadError.value);
});
</script>

<template>
  <Page
    :content-class="
      model && isMobilePreviewMode
        ? 'flex min-h-0 flex-1 flex-col !p-0'
        : 'flex min-h-0 flex-col'
    "
    :description="
      isMobilePreviewMode
        ? '整页居中，中间为手机外框，预览内容在手机屏幕区域内滚动。'
        : '由 JSON 动态渲染；开始节点绑定表单时主区域为真实表单 schema 预览。'
    "
    title="流程预览"
  >
    <div v-if="!model" class="text-muted-foreground p-6 text-sm">
      {{ loadError || '正在加载预览数据…' }}
    </div>
    <ProcessPreviewShell v-else :frame="isMobilePreviewMode">
      <div class="flex flex-col gap-4" :class="isMobilePreviewMode ? 'gap-3' : ''">
      <Card size="small" title="流程信息与业务数据">
        <div
          v-if="isMobilePreviewMode"
          class="divide-border/55 flex flex-col divide-y text-sm"
        >
          <div
            v-for="r in metaRows"
            :key="r.key"
            class="flex flex-col gap-1 py-3 first:pt-1 last:pb-1"
          >
            <span class="text-muted-foreground text-[11px] leading-tight">{{ r.label }}</span>
            <Tag
              v-if="r.isStatus"
              :color="r.statusColor || 'processing'"
              class="w-fit"
            >
              {{ r.text }}
            </Tag>
            <div v-else class="break-words text-[13px] leading-snug">{{ r.text }}</div>
          </div>
        </div>
        <div v-else class="grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
          <div>
            <span class="text-muted-foreground">流程编号：</span>{{ model.meta.processNo }}
          </div>
          <div>
            <span class="text-muted-foreground">表单标题：</span>{{ model.meta.formTitle }}
          </div>
          <div>
            <span class="text-muted-foreground">发起人：</span>{{ model.meta.initiator }}
          </div>
          <div>
            <span class="text-muted-foreground">发起部门：</span>{{ model.meta.dept }}
          </div>
          <div class="md:col-span-2">
            <span class="text-muted-foreground">发起时间：</span>{{ model.meta.startTime }}
          </div>
          <div class="md:col-span-2">
            <span class="text-muted-foreground">当前状态：</span>
            <Tag :color="model.meta.status.color || 'processing'">
              {{ model.meta.status.text }}
            </Tag>
          </div>
        </div>

        <div
          v-if="isTabsBoundForm && selectedNodeBoundForm?.tabs?.length"
          class="border-border mt-4 border-t pt-4"
        >
          <div
            v-if="showDevDebugLine"
            class="mb-2 rounded border border-dashed px-2 py-1 text-xs text-amber-600"
            style="border-color: hsl(var(--border))"
          >
            {{ debugNodeBindingLine }}
          </div>
          <div class="mb-2 text-sm font-medium">
            节点绑定表单（预览） · {{ selectedNodeBoundForm.nodeTitle || activeNodeKey }}
          </div>
          <FormTabsTablePreview
            :form-schema="(mainFormTabsSchema as unknown as VbenFormSchema[])"
            :tabs="selectedNodeBoundForm.tabs"
            :show-form="mainFormTabsSchema.length > 0"
            binding-preview
            preview-readonly
            :field-rules-map="previewFieldRules"
            :initial-main-form-values="mainBuiltinValues"
            :layout="isMobilePreviewMode ? 'vertical' : 'horizontal'"
            :wrapper-class="
              isMobilePreviewMode ? 'grid-cols-1 gap-y-2' : 'grid-cols-1 md:grid-cols-2'
            "
            :label-width="isMobilePreviewMode ? 88 : 100"
            @update:field-rules-map="onPreviewFieldRulesUpdate"
          />
        </div>
        <div
          v-else-if="activeExtFormKey"
          class="border-border mt-4 border-t pt-4"
        >
          <div
            v-if="showDevDebugLine"
            class="mb-2 rounded border border-dashed px-2 py-1 text-xs text-amber-600"
            style="border-color: hsl(var(--border))"
          >
            {{ debugNodeBindingLine }} · extFormKey={{ activeExtFormKey }}
          </div>
          <div class="mb-2 text-sm font-medium">
            节点绑定表单（硬编码预览） ·
            {{ selectedNodeBoundForm?.nodeTitle || activeNodeKey || '当前节点' }}
          </div>
          <component v-if="extRuntimeRoot" :is="extRuntimeRoot" />
          <div v-else class="text-muted-foreground text-sm">正在加载扩展表单…</div>
        </div>
        <div
          v-else-if="selectedNodeBoundForm?.schema?.length || model.startFormSchema?.length"
          class="border-border mt-4 border-t pt-4"
        >
          <div
            v-if="showDevDebugLine"
            class="mb-2 rounded border border-dashed px-2 py-1 text-xs text-amber-600"
            style="border-color: hsl(var(--border))"
          >
            {{ debugNodeBindingLine }}
          </div>
          <div class="mb-2 text-sm font-medium">
            节点绑定表单（预览） ·
            {{ selectedNodeBoundForm?.nodeTitle || activeNodeKey || '开始节点' }}
          </div>
          <PreviewForm />
        </div>

        <div v-if="showBusinessTable" class="border-border mt-4 border-t pt-4">
          <div class="mb-2 text-sm font-medium">业务数据（示例）</div>
          <div :class="isMobilePreviewMode ? '-mx-1 overflow-x-auto' : ''">
            <Table
              :columns="detailColumns"
              :data-source="model.businessData"
              :pagination="false"
              row-key="field"
              size="small"
            />
          </div>
        </div>
      </Card>

      <Card size="small">
        <Tabs>
          <Tabs.TabPane key="nodes" tab="流程节点">
            <Steps :current="activeStep" :items="stepItems" @change="onStepChange" />
          </Tabs.TabPane>
          <Tabs.TabPane key="timeline" tab="审批记录">
            <Timeline>
              <Timeline.Item
                v-for="row in model.records"
                :key="`${row.time}-${row.action}`"
                :color="row.dotColor || 'blue'"
              >
                <div class="flex flex-col gap-0.5">
                  <span class="text-muted-foreground text-xs">{{ row.time }}</span>
                  <span>{{ row.action }}</span>
                  <Tag :color="row.tagColor || 'success'" class="w-fit">
                    {{ row.result }}
                  </Tag>
                </div>
              </Timeline.Item>
            </Timeline>
          </Tabs.TabPane>
        </Tabs>
      </Card>

      <Card v-if="model.actionBar" size="small" :title="model.actionBar.title">
        <div class="flex flex-wrap gap-2">
          <Button type="primary">同意</Button>
          <Button danger>驳回</Button>
          <Button>转交</Button>
          <Button>加签</Button>
          <Button>撤回</Button>
        </div>
        <p class="text-destructive mt-3 text-xs">
          {{ model.actionBar.hint }}
        </p>
      </Card>
      </div>
    </ProcessPreviewShell>
  </Page>
</template>
