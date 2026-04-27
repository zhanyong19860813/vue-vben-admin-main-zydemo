<script setup lang="ts">
import { ref } from 'vue';

import type { VbenFormSchema } from '#/adapter/form';
import type { TabTableConfig } from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import type { WfNodeFormFieldRule } from '#/views/demos/workflow-designer/workflow-definition.schema';

import { Card } from 'ant-design-vue';
import RuntimeFormHost from '#/views/workflow/shared/RuntimeFormHost.vue';

import RuntimeViewerActionPanel from './RuntimeViewerActionPanel.vue';
import RuntimeViewerHeaderInfo from './RuntimeViewerHeaderInfo.vue';
import RuntimeViewerPerfPanel from './RuntimeViewerPerfPanel.vue';

const props = defineProps<{
  actionComment: string;
  actionOpen: boolean;
  actionSubmitting: boolean;
  actionType: 'agree' | 'reject';
  boundFormComponent: unknown;
  boundFormMode: 'designer' | 'ext' | 'snapshot';
  businessDataColumns: Array<Record<string, unknown>>;
  businessDataRows: Array<{ field: string; value: string }>;
  currentNodeId: string;
  extRuntimeRoot: unknown;
  formLoading: boolean;
  formSchema: VbenFormSchema[];
  headerDept: string;
  headerEmployeeNo: string;
  headerFlowNo: string;
  headerPosition: string;
  headerStartTime: string;
  headerStarter: string;
  instanceMetaStatus: { color: string; text: string };
  isMobilePreviewMode: boolean;
  layoutIsTabs: boolean;
  loadedProcessName: string;
  mobileHeaderRows: Array<{ isStatus?: boolean; key: string; label: string; statusColor?: string; value: string }>;
  myTodo: boolean;
  processName: string;
  runtimeNodeNameMap: Record<string, string>;
  runtimePerfLogs: Array<{ at: string; error?: string; ms: number; name: string; ok: boolean }>;
  showRuntimePerfLog: boolean;
  tabsConfig: TabTableConfig[];
  tabsFieldRulesMap: Record<string, WfNodeFormFieldRule>;
  tabsInitialMainValues: Record<string, any>;
  todoLoading: boolean;
  userEmpNo: string;
  userName: string;
}>();

const emit = defineEmits<{
  (e: 'confirm-action'): void;
  (e: 'open-action', type: 'agree' | 'reject'): void;
  (e: 'update:actionComment', value: string): void;
  (e: 'update:actionOpen', value: boolean): void;
  (e: 'update:actionType', value: 'agree' | 'reject'): void;
}>();

const formPanelRef = ref<InstanceType<typeof RuntimeFormHost> | null>(null);

async function getWorkflowRuntimePayload() {
  return await formPanelRef.value?.getWorkflowRuntimePayload?.();
}

async function validateAllTabs() {
  return await formPanelRef.value?.validateAllTabs?.();
}

function loadTabsDataFromObject(data: Record<string, any[]> | null | undefined) {
  formPanelRef.value?.loadTabsDataFromObject?.(data);
}

defineExpose({
  getWorkflowRuntimePayload,
  validateAllTabs,
  loadTabsDataFromObject,
});
</script>

<template>
  <Card size="small" :title="props.loadedProcessName || '流程'">
    <template #extra>
      <RuntimeViewerActionPanel
        :actor-name="props.userName"
        :actor-emp-no="props.userEmpNo"
        :loading="props.todoLoading"
        :action-submitting="props.actionSubmitting"
        :disabled="!props.myTodo"
        :model-value-open="props.actionOpen"
        :model-value-type="props.actionType"
        :model-value-comment="props.actionComment"
        @submit-action="(type) => emit('open-action', type)"
        @confirm="emit('confirm-action')"
        @update:model-value-open="(v) => emit('update:actionOpen', v)"
        @update:model-value-type="(v) => emit('update:actionType', v)"
        @update:model-value-comment="(v) => emit('update:actionComment', v)"
      />
    </template>

    <RuntimeViewerHeaderInfo
      :is-mobile-preview-mode="props.isMobilePreviewMode"
      :mobile-header-rows="props.mobileHeaderRows"
      :header-flow-no="props.headerFlowNo"
      :process-name="props.processName"
      :loaded-process-name="props.loadedProcessName"
      :header-starter="props.headerStarter"
      :header-start-time="props.headerStartTime"
      :header-employee-no="props.headerEmployeeNo"
      :header-dept="props.headerDept"
      :header-position="props.headerPosition"
      :instance-meta-status="props.instanceMetaStatus"
      :runtime-node-name-map="props.runtimeNodeNameMap"
      :resolved-current-node-id="props.currentNodeId"
    />

    <RuntimeViewerPerfPanel
      :show="props.showRuntimePerfLog"
      :logs="props.runtimePerfLogs"
    />

    <RuntimeFormHost
      ref="formPanelRef"
      :form-loading="props.formLoading"
      :bound-form-mode="props.boundFormMode"
      :form-schema="(props.formSchema as any)"
      :layout-is-tabs="props.layoutIsTabs"
      :tabs-config="props.tabsConfig"
      :tabs-field-rules-map="props.tabsFieldRulesMap"
      :is-mobile-preview-mode="props.isMobilePreviewMode"
      :tabs-initial-main-values="props.tabsInitialMainValues"
      :bound-form-component="props.boundFormComponent"
      :ext-runtime-root="props.extRuntimeRoot"
      :business-data-rows="props.businessDataRows"
      :business-data-columns="props.businessDataColumns"
    />
  </Card>
</template>
