<script setup lang="ts">
/**
 * 表单设计器配置的表单 - 弹窗内容
 * 用于列表【新增】按钮弹出，根据 vben_form_desinger 的 schema_json 动态渲染表单
 * 支持数据字典：将 dataSourceType=dictionary 的字段解析为 options/treeData
 */
import { ref, toRaw, watch, nextTick } from 'vue';
import { Button, message } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import type { VbenFormSchema } from '#/adapter/form';
import { resolveDictionaryInSchema } from '../demos/form-designer/resolveDictionarySchema';

const props = withDefaults(
  defineProps<{
    formSchema: VbenFormSchema[];
    saveEntityName: string;
    primaryKey?: string;
    formTitle?: string;
    layout?: { cols?: number; labelWidth?: number; labelAlign?: string };
    /** 编辑回填：传入选中行数据 */
    initialValues?: Record<string, any>;
  }>(),
  {
    primaryKey: 'id',
    formTitle: '新增',
  }
);

const emit = defineEmits<{
  success: [];
  cancel: [];
}>();

const submitting = ref(false);

const wrapperClass =
  props.layout?.cols === 1
    ? 'grid-cols-1'
    : props.layout?.cols === 3
      ? 'grid-cols-1 md:grid-cols-2 lg:grid-cols-3'
      : 'grid-cols-1 md:grid-cols-2';

const [Form, formApi] = useVbenForm({
  showDefaultActions: false,
  schema: [] as VbenFormSchema[],
  wrapperClass,
  layout: 'horizontal',
  commonConfig: {
    labelWidth: props.layout?.labelWidth ?? 100,
    labelAlign: (props.layout?.labelAlign as any) ?? 'right',
  } as any,
});

/**
 * 将行数据按表单 schema 的 fieldName 映射，兼容后端返回 PascalCase 等情况
 */
function mapRowToSchemaFields(
  row: Record<string, any>,
  schema: VbenFormSchema[],
): Record<string, any> {
  if (!row || !schema?.length) return row ?? {};
  const fieldNames = new Set(schema.map((s) => s.fieldName).filter(Boolean));
  const rowKeysLower = new Map<string, string>(
    Object.keys(row).map((k) => [k.toLowerCase(), k]),
  );
  const result: Record<string, any> = {};
  for (const fn of fieldNames) {
    if (fn in row) {
      result[fn] = row[fn];
    } else {
      const lower = fn.toLowerCase();
      const origKey = rowKeysLower.get(lower);
      if (origKey !== undefined) result[fn] = row[origKey];
    }
  }
  return result;
}

watch(
  () => props.formSchema,
  async (schema) => {
    const raw = schema ? [...schema] : [];
    const resolved = await resolveDictionaryInSchema(raw);
    formApi.setState({ schema: resolved });
    // ⭐ 关键：schema 加载完成后再回填 initialValues，避免被 schema 初始化覆盖
    await nextTick();
    const vals = props.initialValues;
    if (vals && Object.keys(vals).length) {
      const mapped = mapRowToSchemaFields(vals, resolved);
      if (Object.keys(mapped).length) {
        await formApi.setValues(mapped);
      }
    }
  },
  { immediate: true, deep: true }
);

watch(
  () => props.initialValues,
  async (vals) => {
    if (!vals || !Object.keys(vals).length) return;
    const schema = (formApi.getState()?.schema ?? []) as VbenFormSchema[];
    const mapped = mapRowToSchemaFields(vals, schema);
    if (Object.keys(mapped).length) {
      await formApi.setValues(mapped);
    }
  },
  { immediate: false, deep: true }
);

async function handleSubmit() {
  try {
    await formApi.validate(); // 校验
    const raw = await formApi.getValues(); // 获取纯表单字段值，避免 valid/values/errors 等写入库
    const values = toRaw(raw ?? {}) as Record<string, any>;
    // 排除校验结果字段 + 标记为 excludeFromSubmit 的字段（仅展示不保存）
    const BLOCKLIST = new Set(['valid', 'results', 'errors', 'values', 'source']);
    const excludeFields = new Set(
      (props.formSchema || [])
        .filter((s: any) => s.excludeFromSubmit)
        .map((s) => s.fieldName),
    );
    const cleanValues: Record<string, any> = {};
    for (const [k, v] of Object.entries(values)) {
      if (!BLOCKLIST.has(k) && !excludeFields.has(k)) {
        cleanValues[k] = v === undefined ? null : v;
      }
    }
    // 新增时若缺少主键，自动生成 GUID
    const pk = props.primaryKey || 'id';
    if (!cleanValues[pk] || String(cleanValues[pk]).trim() === '') {
      cleanValues[pk] = crypto.randomUUID();
    }
    if (!props.saveEntityName?.trim()) {
      message.warning('未配置保存实体 (saveEntityName)，请联系管理员在列表配置中设置');
      return;
    }
    if (Object.keys(cleanValues).filter((k) => k !== pk).length === 0) {
      message.warning('表单数据为空，请填写表单项后再保存');
      return;
    }
    // 调试输出（上线前可移除）
    console.debug('[FormFromDesigner] 保存参数:', {
      saveEntityName: props.saveEntityName,
      primaryKey: pk,
      data: cleanValues,
    });
    submitting.value = true;
    await requestClient.post<any>(backendApi('DataSave/datasave-multi'), {
      tables: [
        {
          tableName: props.saveEntityName,
          primaryKey: pk,
          data: [cleanValues],
          deleteRows: [],
        },
      ],
    });
    message.success('保存成功');
    emit('success');
  } catch (e: any) {
    if (e?.errorFields) return; // 校验失败
    message.error(e?.message || e?.data?.message || '保存失败');
  } finally {
    submitting.value = false;
  }
}

function handleCancel() {
  emit('cancel');
}
</script>

<template>
  <div class="form-from-designer-modal p-4">
    <Form />
    <div class="mt-4 flex justify-end gap-2 border-t pt-4">
      <Button @click="handleCancel">取消</Button>
      <Button type="primary" :loading="submitting" @click="handleSubmit">
        保存
      </Button>
    </div>
  </div>
</template>
