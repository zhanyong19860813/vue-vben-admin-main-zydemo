<script setup lang="ts">
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { Form, FormItem, Input, Modal, Radio, RadioGroup, Select, message } from 'ant-design-vue';
import { onMounted, reactive, ref } from 'vue';

const props = defineProps<{
  mode: 'add' | 'edit';
  id?: string;
  title?: string;
  onSuccess?: (v?: any) => void;
  onCancel?: () => void;
}>();

const loading = ref(false);
const groupOptions = ref<{ label: string; value: string }[]>([]);
const levelOptions = ref<{ label: string; value: string }[]>([]);
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
      Where: { Logic: 'AND', Conditions: [{ Field: 'code', Operator: 'eq', Value: 'duty_level_no' }], Groups: [] },
    }),
  ]);
  groupOptions.value = (groupRows.items ?? []).map((x: any) => ({ value: String(x.id), label: String(x.name ?? '').trim() }));
  levelOptions.value = (levelRows.items ?? []).map((x: any) => ({ value: String(x.value ?? '').trim(), label: String(x.name ?? '').trim() }));
}

async function calcNextSJID() {
  const res = await requestClient.post<{ items: Array<{ SJID?: string }> }>(backendApi('DynamicQueryBeta/queryforvben'), {
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

async function loadDetail(id: string) {
  const res = await requestClient.post<{ items: any[] }>(backendApi('DynamicQueryBeta/queryforvben'), {
    TableName: 'v_t_base_duty_group',
    Page: 1,
    PageSize: 1,
    QueryField: 'id,name,SJID,level_no,is_manager,group_id,description',
    Where: { Logic: 'AND', Conditions: [{ Field: 'id', Operator: 'eq', Value: id }], Groups: [] },
  });
  const d = (res.items ?? [])[0];
  if (!d) return;
  formState.id = String(d.id ?? id);
  formState.name = String(d.name ?? '').trim();
  formState.SJID = String(d.SJID ?? '').trim();
  formState.level_no = d.level_no != null ? String(d.level_no) : undefined;
  formState.is_manager = String(d.is_manager ?? '0') === '1' ? '1' : '0';
  formState.group_id = d.group_id != null ? String(d.group_id) : undefined;
  formState.description = String(d.description ?? '').trim();
}

async function onSave() {
  const name = formState.name.trim();
  if (!name) return message.warning('请输入职务名称');
  if (props.mode === 'add' && !formState.SJID.trim()) return message.warning('岗位编码不能为空');

  if (props.mode === 'add') {
    const [dupName, dupSJID] = await Promise.all([
      requestClient.post<{ total?: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
        TableName: 't_base_duty',
        Page: 1,
        PageSize: 1,
        QueryField: 'id',
        Where: { Logic: 'AND', Conditions: [{ Field: 'name', Operator: 'eq', Value: name }], Groups: [] },
      }),
      requestClient.post<{ total?: number }>(backendApi('DynamicQueryBeta/queryforvben'), {
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

  loading.value = true;
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
    if (props.mode === 'add') row.SJID = formState.SJID.trim();
    await requestClient.post(backendApi('DataSave/datasave-multi'), {
      tables: [{ tableName: 't_base_duty', primaryKey: 'id', data: [row] }],
    });
    message.success('保存成功');
    props.onSuccess?.('success');
  } catch (e: unknown) {
    message.error(e instanceof Error ? e.message : '保存失败');
  } finally {
    loading.value = false;
  }
}

onMounted(async () => {
  await loadDictOptions();
  if (props.mode === 'edit' && props.id) {
    formState.id = props.id;
    await loadDetail(props.id);
  } else {
    formState.id = newGuid();
    formState.SJID = await calcNextSJID();
  }
});
</script>

<template>
  <div>
    <Form layout="horizontal" :label-col="{ flex: '0 0 110px' }" :wrapper-col="{ flex: '1' }" :colon="false">
      <FormItem label="职务名称" required>
        <Input v-model:value="formState.name" allow-clear />
      </FormItem>
      <FormItem label="职务编码">
        <Input v-model:value="formState.SJID" :disabled="props.mode === 'edit'" />
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
      <FormItem :wrapper-col="{ offset: 7 }">
        <div class="flex gap-2">
          <a-button type="primary" :loading="loading" @click="onSave">保存</a-button>
          <a-button @click="props.onCancel?.()">取消</a-button>
        </div>
      </FormItem>
    </Form>
  </div>
</template>

