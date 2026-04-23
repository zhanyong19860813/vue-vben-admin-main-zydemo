<script setup lang="ts">
import type { Component as VueConcreteComponent } from 'vue';
import { computed, defineComponent, h, nextTick, ref, shallowRef, watch } from 'vue';

import { useUserStore } from '@vben/stores';

import { Button, Modal, Radio, Select, Space, message } from 'ant-design-vue';

import type { VbenFormSchema } from '#/adapter/form';
import { useVbenForm } from '#/adapter/form';
import { getWorkflowFormSchemaList } from '#/api/workflow';
import FormTabsTablePreview from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import type { TabTableConfig } from '#/views/demos/form-designer/FormTabsTablePreview.vue';
import { buildWorkflowBuiltinValuesFromUser } from '#/views/demos/form-designer/workflowFormRuntime';
import type {
  WfNodeFormBinding,
  WfNodeFormFieldRule,
} from '#/views/demos/workflow-designer/workflow-definition.schema';
import HelpHintPopover from '#/components/HelpHintPopover.vue';
import {
  buildExtFormCode,
  createExtWorkflowFormComponent,
  listExtWorkflowForms,
  parseExtFormKeyFromFormCode,
} from '#/views/workflowExtForm/registry';

type FormRec = {
  id: string;
  code: string;
  title?: string;
  schemaJson?: string;
  formCategory?: string;
};

function pickFirstNonEmpty(...vals: unknown[]): string {
  for (const v of vals) {
    const s = String(v ?? '').trim();
    if (s) return s;
  }
  return '';
}

function isWorkflowFormCategory(raw: unknown): boolean {
  const v = String(raw ?? '')
    .trim()
    .toLowerCase();
  return (
    v === 'workflow' ||
    v === 'workflowform' ||
    v === 'workflow_form' ||
    v === 'flow' ||
    v === 'process'
  );
}

function inferWorkflowFormFromSchemaJson(schemaJson?: string): boolean {
  const raw = String(schemaJson ?? '').trim();
  if (!raw) return false;
  try {
    const parsed = JSON.parse(raw) as Record<string, any>;
    return isWorkflowFormCategory(
      parsed.formCategory ??
        parsed.formType ??
        parsed.category ??
        parsed.type ??
        parsed.form_category ??
        parsed.form_type,
    );
  } catch {
    return false;
  }
}

function isWorkflowFormRecord(row: Record<string, any>, schemaJson?: string): boolean {
  if (
    isWorkflowFormCategory(
      row.formCategory ??
        row.formType ??
        row.category ??
        row.type ??
        row.form_category ??
        row.form_type ??
        row.FormCategory ??
        row.FormType,
    )
  ) {
    return true;
  }
  return inferWorkflowFormFromSchemaJson(schemaJson);
}

const props = defineProps<{
  open: boolean;
  nodeId: string;
  nodeName?: string;
  initialBinding: WfNodeFormBinding | null;
  nodeOptions?: Array<{ value: string; label: string }>;
}>();

const emit = defineEmits<{
  'update:open': [open: boolean];
  saved: [binding: WfNodeFormBinding | null];
  syncToNodes: [payload: { nodeIds: string[]; binding: WfNodeFormBinding }];
}>();

const RULE_OPTIONS: { value: WfNodeFormFieldRule; label: string }[] = [
  { value: 'visible', label: '可见' },
  { value: 'hidden', label: '隐藏' },
  { value: 'readonly', label: '只读' },
  { value: 'required', label: '必填' },
];

const userStore = useUserStore();

const formsLoading = ref(false);
const formList = ref<FormRec[]>([]);
/** 设计器表单 code；硬编码模式下置空 */
const formCode = ref<string | undefined>(undefined);
const formKind = ref<'designer' | 'ext'>('designer');
const extFormKey = ref<string | undefined>(undefined);
const extPreviewRoot = shallowRef<VueConcreteComponent | null>(null);
const syncTargetNodeIds = ref<string[]>([]);

/** 当前预览/保存用的字段策略（主表 fieldName；页签表格列为 `tabKey::field`） */
const fieldRulesMap = ref<Record<string, WfNodeFormFieldRule>>({});

const layoutIsTabs = ref(false);
const cachedNormalizedSchema = ref<VbenFormSchema[]>([]);
const cachedTabs = ref<TabTableConfig[]>([]);
const cachedWorkflowNoPrefix = ref<string | undefined>(undefined);

/** 上表+页签预览用 */
const mainDecoratedSchemaForTabs = ref<VbenFormSchema[]>([]);
const tabsPreviewClone = ref<TabTableConfig[]>([]);
const mainBuiltinValues = ref<Record<string, any>>({});

const [PreviewForm, previewFormApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as VbenFormSchema[],
  wrapperClass: 'grid-cols-1 md:grid-cols-2 gap-x-[2px] gap-y-[2px]',
  layout: 'horizontal',
  formItemGapPx: 2 as any,
  commonConfig: { labelWidth: 110 } as any,
});

const FieldRuleSelect = defineComponent({
  name: 'NodeFormFieldRuleSelect',
  props: {
    fieldKey: { type: String, required: true },
  },
  setup(props) {
    return () =>
      h(Select as any, {
        value: fieldRulesMap.value[props.fieldKey] ?? 'visible',
        size: 'small',
        class: 'wf-node-fbind-sel',
        style: { width: '100px' },
        options: RULE_OPTIONS.map((o) => ({ value: o.value, label: o.label })),
        onChange: (v: WfNodeFormFieldRule) => {
          fieldRulesMap.value = {
            ...fieldRulesMap.value,
            [props.fieldKey]: v,
          };
        },
      });
  },
});

const titleText = computed(() => {
  const name = (props.nodeName || '').trim();
  return name ? `节点表单 — ${name}` : `节点表单 — ${props.nodeId || '（未选节点）'}`;
});

function parseFormSchemaJson(raw: string | undefined) {
  if (!raw?.trim()) return null;
  try {
    const parsed = JSON.parse(raw) as Record<string, any>;
    const srcSchema = Array.isArray(parsed?.schema) ? parsed.schema : [];
    const layoutType = parsed?.layout?.layoutType ?? parsed?.layoutType;
    const tabs = Array.isArray(parsed?.tabs) ? (parsed.tabs as TabTableConfig[]) : [];
    const layoutIsTabsMode = layoutType === 'formTabsTable' && tabs.length > 0;
    return {
      layoutIsTabs: layoutIsTabsMode,
      srcSchema,
      tabs,
      workflowNoPrefix: parsed?.workflowNoPrefix as string | undefined,
    };
  } catch {
    return null;
  }
}

function collectBindingKeysFromParsed(
  p: NonNullable<ReturnType<typeof parseFormSchemaJson>>,
): string[] {
  const keys: string[] = [];
  for (const s of p.srcSchema as { fieldName?: string }[]) {
    const k = String(s?.fieldName || '').trim();
    if (k) keys.push(k);
  }
  if (p.layoutIsTabs) {
    for (const tab of p.tabs) {
      const tk = String(tab?.key || '').trim();
      if (!tk) continue;
      for (const c of tab.columns || []) {
        if (c?.visible === false) continue;
        const f = String(c?.field || '').trim();
        if (f) keys.push(`${tk}::${f}`);
      }
    }
  }
  return keys;
}

function normalizeSchemaForPreview(src: unknown[]): VbenFormSchema[] {
  return (src as any[]).map((s: any) => {
    const cp = s?.componentProps ?? {};
    const isTextarea =
      String(s?.component ?? '').toLowerCase().includes('textarea') ||
      String(cp?.type ?? '').toLowerCase() === 'textarea' ||
      typeof cp?.rows === 'number';
    if (!isTextarea) return s as VbenFormSchema;
    return {
      ...s,
      componentProps: {
        ...cp,
        rows: 1,
        autoSize: false,
        showCount: false,
      },
      formItemClass: [s?.formItemClass, 'md:col-span-2'].filter(Boolean).join(' '),
    } as VbenFormSchema;
  });
}

function decorateSchemaItem(item: VbenFormSchema): VbenFormSchema {
  const key = String(item.fieldName || '').trim();
  if (!key) return item;
  const rule = fieldRulesMap.value[key] ?? 'visible';
  const baseCp =
    typeof item.componentProps === 'function' ? {} : { ...(item.componentProps || {}) };
  const readOnly = rule === 'readonly' || rule === 'hidden';
  return {
    ...item,
    componentProps: {
      ...baseCp,
      readOnly,
    },
    formItemClass: [item.formItemClass, `wf-node-fbind-item wf-node-fbind--${rule}`]
      .filter(Boolean)
      .join(' '),
    suffix: () => h(FieldRuleSelect, { fieldKey: key }),
  };
}

function onTabsFieldRulesUpdate(v: Record<string, WfNodeFormFieldRule>) {
  fieldRulesMap.value = { ...v };
}

async function refreshPreviewSchema() {
  if (formKind.value === 'ext') {
    previewFormApi.setState({ schema: [] as VbenFormSchema[] });
    await previewFormApi.setValues({});
    mainDecoratedSchemaForTabs.value = [];
    tabsPreviewClone.value = [];
    mainBuiltinValues.value = [];
    return;
  }
  if (!props.open || !formCode.value) {
    previewFormApi.setState({ schema: [] as VbenFormSchema[] });
    await previewFormApi.setValues({});
    mainDecoratedSchemaForTabs.value = [];
    tabsPreviewClone.value = [];
    mainBuiltinValues.value = {};
    return;
  }

  if (layoutIsTabs.value && cachedTabs.value.length > 0) {
    const mainDecorated = cachedNormalizedSchema.value.map((s) =>
      decorateSchemaItem(s as VbenFormSchema),
    );
    mainDecoratedSchemaForTabs.value = mainDecorated;
    tabsPreviewClone.value = JSON.parse(JSON.stringify(cachedTabs.value)) as TabTableConfig[];
    const wf = buildWorkflowBuiltinValuesFromUser(mainDecorated as any, {
      userInfo: userStore.userInfo as any,
      workflowNoPrefix: cachedWorkflowNoPrefix.value,
    });
    mainBuiltinValues.value = wf;
    previewFormApi.setState({ schema: [] as VbenFormSchema[] });
    await nextTick();
    await previewFormApi.setValues({});
    return;
  }

  const decorated = cachedNormalizedSchema.value.map((s) =>
    decorateSchemaItem(s as VbenFormSchema),
  );
  previewFormApi.setState({ schema: decorated as any });
  await nextTick();
  const wf = buildWorkflowBuiltinValuesFromUser(decorated as any, {
    userInfo: userStore.userInfo as any,
    workflowNoPrefix: cachedWorkflowNoPrefix.value,
  });
  await previewFormApi.setValues(wf);
  mainDecoratedSchemaForTabs.value = [];
  tabsPreviewClone.value = [];
  mainBuiltinValues.value = {};
}

function rebuildFieldRulesFromForm() {
  if (formKind.value === 'ext') {
    fieldRulesMap.value = {};
    layoutIsTabs.value = false;
    cachedNormalizedSchema.value = [];
    cachedTabs.value = [];
    cachedWorkflowNoPrefix.value = undefined;
    void refreshPreviewSchema();
    return;
  }
  if (!formCode.value) {
    fieldRulesMap.value = {};
    layoutIsTabs.value = false;
    cachedNormalizedSchema.value = [];
    cachedTabs.value = [];
    cachedWorkflowNoPrefix.value = undefined;
    void refreshPreviewSchema();
    return;
  }
  const f = formList.value.find((x) => x.code === formCode.value);
  const parsed = parseFormSchemaJson(f?.schemaJson);
  if (!parsed) {
    fieldRulesMap.value = {};
    layoutIsTabs.value = false;
    cachedNormalizedSchema.value = [];
    cachedTabs.value = [];
    cachedWorkflowNoPrefix.value = undefined;
    void refreshPreviewSchema();
    return;
  }

  layoutIsTabs.value = parsed.layoutIsTabs;
  cachedNormalizedSchema.value = normalizeSchemaForPreview(parsed.srcSchema);
  cachedTabs.value = parsed.tabs;
  cachedWorkflowNoPrefix.value = parsed.workflowNoPrefix;

  const keyList = collectBindingKeysFromParsed(parsed);
  const cur = props.initialBinding;
  const sameForm = !!(cur && formCode.value && cur.formCode === formCode.value);
  const rules = (sameForm ? cur?.fieldRules : undefined) || {};
  const next: Record<string, WfNodeFormFieldRule> = {};
  for (const key of keyList) {
    next[key] = (rules[key] as WfNodeFormFieldRule) || 'visible';
  }
  fieldRulesMap.value = next;
}

function syncFromInitial() {
  const b = props.initialBinding;
  const extFromProp =
    (b?.formSource === 'ext' && String(b?.extFormKey || '').trim()) ||
    parseExtFormKeyFromFormCode(String(b?.formCode || ''));
  if (extFromProp) {
    formKind.value = 'ext';
    extFormKey.value = extFromProp;
    formCode.value = undefined;
    fieldRulesMap.value = {};
    layoutIsTabs.value = false;
    cachedNormalizedSchema.value = [];
    cachedTabs.value = [];
    cachedWorkflowNoPrefix.value = undefined;
    mainDecoratedSchemaForTabs.value = [];
    tabsPreviewClone.value = [];
    mainBuiltinValues.value = [];
    void refreshPreviewSchema();
    return;
  }
  formKind.value = 'designer';
  extFormKey.value = undefined;
  const code = String(b?.formCode || '').trim();
  if (code) {
    formCode.value = code;
  } else {
    const name = String(b?.formName || '').trim();
    const nameLower = name.toLowerCase();
    const hit = name
      ? formList.value.find((x) => {
          const title = String(x.title || '').trim();
          const c = String(x.code || '').trim();
          if (title && title === name) return true;
          if (c && c === name) return true;
          const titleLower = title.toLowerCase();
          const cLower = c.toLowerCase();
          return (
            (titleLower && titleLower.includes(nameLower)) ||
            (cLower && cLower.includes(nameLower))
          );
        })
      : undefined;
    formCode.value = hit?.code || undefined;
  }
  rebuildFieldRulesFromForm();
}

async function loadForms() {
  formsLoading.value = true;
  try {
    const raw = (await getWorkflowFormSchemaList()) as any;
    const rows =
      (Array.isArray(raw) ? raw : undefined) ||
      (Array.isArray(raw?.items) ? raw.items : undefined) ||
      (Array.isArray(raw?.records) ? raw.records : undefined) ||
      [];
    formList.value = (rows as Record<string, any>[])
      .map((x) => {
        const schemaJson =
          typeof x?.schemaJson === 'string'
            ? x.schemaJson
            : typeof x?.SchemaJson === 'string'
              ? x.SchemaJson
              : undefined;
        return {
          id: pickFirstNonEmpty(x?.id, x?.Id),
          code: pickFirstNonEmpty(
            x?.code,
            x?.formCode,
            x?.form_code,
            x?.Code,
            x?.FormCode,
            x?.id,
          ),
          title: pickFirstNonEmpty(
            x?.title,
            x?.formTitle,
            x?.formName,
            x?.name,
            x?.Title,
          ),
          schemaJson,
          formCategory: pickFirstNonEmpty(
            x?.formCategory,
            x?.formType,
            x?.category,
            x?.type,
            x?.form_category,
            x?.form_type,
            x?.FormCategory,
            x?.FormType,
          ),
        } as FormRec;
      })
      .filter((x) => isWorkflowFormRecord(x as Record<string, any>, x.schemaJson));
  } catch {
    formList.value = [];
    message.error('加载表单列表失败');
  } finally {
    formsLoading.value = false;
  }
}

watch(
  () => props.open,
  (v) => {
    if (!v) return;
    void loadForms().then(() => syncFromInitial());
  },
);

watch(
  () => props.initialBinding,
  () => {
    if (props.open) syncFromInitial();
  },
  { deep: true },
);

watch(formCode, () => {
  if (props.open) rebuildFieldRulesFromForm();
});

watch(
  fieldRulesMap,
  () => {
    if (!props.open || formKind.value === 'ext' || !formCode.value) return;
    void refreshPreviewSchema();
  },
  { deep: true },
);

watch(
  () => [props.open, formKind.value, extFormKey.value] as const,
  ([open, kind, key]) => {
    if (!open || kind !== 'ext' || !String(key || '').trim()) {
      extPreviewRoot.value = null;
      return;
    }
    extPreviewRoot.value = createExtWorkflowFormComponent(String(key).trim()) as any;
  },
  { immediate: true },
);

watch(formKind, (kind) => {
  if (!props.open) return;
  if (kind === 'designer') {
    extFormKey.value = undefined;
    extPreviewRoot.value = null;
    rebuildFieldRulesFromForm();
  } else {
    formCode.value = undefined;
    fieldRulesMap.value = {};
    layoutIsTabs.value = false;
    cachedNormalizedSchema.value = [];
    cachedTabs.value = [];
    cachedWorkflowNoPrefix.value = undefined;
    mainDecoratedSchemaForTabs.value = [];
    tabsPreviewClone.value = [];
    mainBuiltinValues.value = {};
    void refreshPreviewSchema();
  }
});

const extFormSelectOptions = computed(() => listExtWorkflowForms().map((x) => ({ ...x, value: x.key })));

const formSelectOptions = computed(() =>
  formList.value
    .filter((x) => String(x.code || '').trim())
    .map((x) => ({
      value: x.code,
      label: `${x.code}${x.title ? ` — ${x.title}` : ''}`,
    })),
);

function close() {
  emit('update:open', false);
}

function onUnbind() {
  emit('saved', null);
  close();
}

function onSubmit() {
  if (formKind.value === 'ext') {
    const key = String(extFormKey.value || '').trim();
    if (!key) {
      message.warning('请选择硬编码表单');
      return;
    }
    const hit = extFormSelectOptions.value.find((x) => x.key === key);
    emit('saved', {
      formSource: 'ext',
      extFormKey: key,
      formCode: buildExtFormCode(key),
      formName: (hit?.label || key).replace(/（硬编码）$/, '').trim() || key,
      fieldRules: {},
    });
    close();
    return;
  }
  if (!formCode.value) {
    message.warning('请选择表单');
    return;
  }
  const rec = formList.value.find((x) => x.code === formCode.value);
  if (!rec) {
    message.warning('所选表单已不存在，请重新选择');
    return;
  }
  emit('saved', {
    formCode: rec.code,
    formName: (rec.title || '').trim() || rec.code,
    fieldRules: { ...fieldRulesMap.value },
  });
  close();
}

function onSyncToSelectedNodes() {
  if (!syncTargetNodeIds.value.length) {
    message.warning('请先选择要同步的节点');
    return;
  }
  if (formKind.value === 'ext') {
    const key = String(extFormKey.value || '').trim();
    if (!key) {
      message.warning('请先选择硬编码表单');
      return;
    }
    const hit = extFormSelectOptions.value.find((x) => x.key === key);
    emit('syncToNodes', {
      nodeIds: [...syncTargetNodeIds.value],
      binding: {
        formSource: 'ext',
        extFormKey: key,
        formCode: buildExtFormCode(key),
        formName: (hit?.label || key).replace(/（硬编码）$/, '').trim() || key,
        fieldRules: {},
      },
    });
    return;
  }
  if (!formCode.value) {
    message.warning('请先选择当前节点绑定表单');
    return;
  }
  const rec = formList.value.find((x) => x.code === formCode.value);
  if (!rec) {
    message.warning('当前所选表单已不存在，请重新选择');
    return;
  }
  emit('syncToNodes', {
    nodeIds: [...syncTargetNodeIds.value],
    binding: {
      formCode: rec.code,
      formName: (rec.title || '').trim() || rec.code,
      fieldRules: { ...fieldRulesMap.value },
    },
  });
}
</script>

<template>
  <Modal
    :open="open"
    :title="titleText"
    width="960px"
    destroy-on-close
    @cancel="close"
  >
    <div class="mb-3 flex flex-col gap-2">
      <div class="text-muted-foreground text-sm">
        <template v-if="layoutIsTabs">
          当前为<strong>上表 + 下页签表格</strong>布局预览：主表字段右侧可选策略；每个页签下方可配置<strong>列表列</strong>策略。列表列在保存中的键为
          <code class="text-xs">页签key::列field</code>
          （与表单设计器一致）。隐藏 / 只读在主表与列表中均以样式与禁用体现。
        </template>
        <template v-else>
          下方为选中表单的<strong>实时预览</strong>（布局与运行时一致）。每项右侧可选择<strong>可见 / 隐藏 / 只读 / 必填</strong>：隐藏、只读时控件不可编辑；隐藏项会以浅色虚线标出，必填项会高亮标识。保存后写入画布节点属性。
        </template>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <span class="shrink-0 text-sm">表单来源</span>
        <Radio.Group v-model:value="formKind" size="small">
          <Radio.Button value="designer">表单设计器</Radio.Button>
          <Radio.Button value="ext">硬编码（workflowExtForm）</Radio.Button>
        </Radio.Group>
        <HelpHintPopover title="表单来源说明">
          <div class="space-y-2.5">
            <div>
              <div class="text-foreground mb-1 font-medium">表单设计器</div>
              <p class="text-muted-foreground mb-0">
                在菜单进入<strong class="text-foreground">「演示 → 表单设计器」</strong>（路由一般为
                <code class="rounded bg-muted px-1 py-0.5 text-[11px]">/demos/form-designer</code>
                ），新建或编辑表单并保存后，在此选择「表单设计器」并在下方下拉框中绑定。
              </p>
            </div>
            <div>
              <div class="text-foreground mb-1 font-medium">硬编码（workflowExtForm）</div>
              <p class="text-muted-foreground mb-0">
                在源码目录
                <code class="break-all rounded bg-muted px-1 py-0.5 text-[11px]">
                  apps/web-antd/src/views/workflowExtForm
                </code>
                下按「一个表单一个子文件夹」开发；入口文件固定为
                <code class="rounded bg-muted px-1 py-0.5 text-[11px]">index.vue</code>
                。构建后会在「扩展表单」中自动列出，无需手写注册。
              </p>
            </div>
          </div>
        </HelpHintPopover>
      </div>
      <div v-if="formKind === 'designer'" class="flex flex-wrap items-center gap-2">
        <span class="shrink-0 text-sm">绑定表单</span>
        <Select
          v-model:value="formCode"
          allow-clear
          show-search
          :filter-option="
            (input: string, option: any) =>
              String(option?.label ?? '')
                .toLowerCase()
                .includes(input.trim().toLowerCase())
          "
          :loading="formsLoading"
          :options="formSelectOptions"
          class="min-w-[280px] max-w-full flex-1"
          placeholder="请选择表单"
        />
      </div>
      <div v-else class="flex flex-wrap items-center gap-2">
        <span class="shrink-0 text-sm">扩展表单</span>
        <Select
          v-model:value="extFormKey"
          allow-clear
          show-search
          :filter-option="
            (input: string, option: any) =>
              String(option?.label ?? option?.value ?? '')
                .toLowerCase()
                .includes(input.trim().toLowerCase())
          "
          :options="extFormSelectOptions"
          class="min-w-[280px] max-w-full flex-1"
          placeholder="选择 workflowExtForm 子目录（index.vue）"
        />
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <span class="shrink-0 text-sm">同步到节点</span>
        <Select
          v-model:value="syncTargetNodeIds"
          mode="multiple"
          allow-clear
          show-search
          :filter-option="
            (input: string, option: any) =>
              String(option?.label ?? '')
                .toLowerCase()
                .includes(input.trim().toLowerCase())
          "
          :options="(props.nodeOptions || []).filter((x) => x.value !== props.nodeId)"
          class="min-w-[280px] max-w-full flex-1"
          placeholder="可多选其他节点，批量同步当前表单绑定"
        />
        <Button @click="onSyncToSelectedNodes">同步到选中节点</Button>
      </div>
    </div>
    <div
      class="wf-node-fbind-preview rounded-md border border-solid p-3"
      style="border-color: hsl(var(--border)); background: hsl(var(--muted) / 0.35)"
    >
      <div class="max-h-[min(480px,58vh)] overflow-y-auto overflow-x-hidden pr-1">
        <template v-if="formKind === 'ext'">
          <p v-if="extFormKey" class="text-muted-foreground mb-2 text-xs">
            预览挂载自
            <code class="text-xs">views/workflowExtForm/{{ extFormKey }}/index.vue</code>
            。字段显隐、校验请在组件内自行实现（本弹窗不写入 fieldRules）。
          </p>
          <component v-if="extPreviewRoot" :is="extPreviewRoot" />
          <div v-else-if="extFormKey" class="text-destructive text-sm">
            未找到入口文件，请确认目录与文件名。
          </div>
          <div v-else class="text-muted-foreground text-sm">请选择扩展表单。</div>
        </template>
        <template v-else>
          <FormTabsTablePreview
            v-if="layoutIsTabs && tabsPreviewClone.length"
            :form-schema="(mainDecoratedSchemaForTabs as unknown as VbenFormSchema[])"
            :tabs="tabsPreviewClone"
            :show-form="cachedNormalizedSchema.length > 0"
            binding-preview
            :field-rules-map="fieldRulesMap"
            :initial-main-form-values="mainBuiltinValues"
            @update:field-rules-map="onTabsFieldRulesUpdate"
          />
          <PreviewForm v-else />
        </template>
      </div>
    </div>
    <template #footer>
      <Space>
        <Button @click="onUnbind">解除绑定</Button>
        <Button @click="close">取消</Button>
        <Button type="primary" @click="onSubmit">保存</Button>
      </Space>
    </template>
  </Modal>
</template>

<style scoped>
:deep(.wf-node-fbind-item) {
  position: relative;
  border-radius: 6px;
  transition:
    opacity 0.15s ease,
    background 0.15s ease;
}

:deep(.wf-node-fbind--visible) {
  box-shadow: inset 3px 0 0 0 hsl(var(--primary) / 0.55);
}

:deep(.wf-node-fbind--readonly) {
  box-shadow: inset 3px 0 0 0 hsl(38 92% 50% / 0.75);
}

:deep(.wf-node-fbind--hidden) {
  opacity: 0.45;
  background: repeating-linear-gradient(
    -45deg,
    hsl(var(--muted)),
    hsl(var(--muted)) 6px,
    transparent 6px,
    transparent 12px
  );
  box-shadow: inset 3px 0 0 0 hsl(var(--border));
}

:deep(.wf-node-fbind--required) {
  box-shadow: inset 3px 0 0 0 hsl(355 88% 58% / 0.8);
}

:deep(.wf-node-fbind-sel) {
  max-width: 100%;
}
</style>
