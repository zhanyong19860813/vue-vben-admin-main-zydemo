<script setup lang="ts">
import { useVbenModal } from '@vben/common-ui';
import { message } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

defineOptions({ name: 'DictionaryDetailModal' });

/** 网格/接口可能返回 snake_case 或 camelCase，统一成表单字段 */
function normalizeDetailRow(row: Record<string, any>) {
  return {
    id: row.id ?? row.Id,
    dictionary_id: row.dictionary_id ?? row.dictionaryId,
    name: row.name,
    value: row.value,
    help_code: row.help_code ?? row.helpCode,
    description: row.description,
    sort: row.sort ?? 0,
  };
}

const [Form, formApi] = useVbenForm({
  handleSubmit: onSubmit,
  schema: [
    {
      fieldName: 'id',
      label: '',
      component: 'Input',
      componentProps: { style: { display: 'none' } },
    },
    {
      fieldName: 'dictionary_id',
      label: '',
      component: 'Input',
      componentProps: { style: { display: 'none' } },
    },
    {
      fieldName: 'name',
      label: '值名称',
      component: 'Input',
      componentProps: { placeholder: '如：男、锁具' },
      rules: 'required',
    },
    {
      fieldName: 'value',
      label: '值',
      component: 'Input',
      componentProps: { placeholder: '如：1、0' },
      rules: 'required',
    },
    {
      fieldName: 'help_code',
      label: '辅助值',
      component: 'Input',
      componentProps: { placeholder: '可选' },
    },
    {
      fieldName: 'description',
      label: '说明',
      component: 'Input',
      componentProps: { placeholder: '可选' },
    },
    {
      fieldName: 'sort',
      label: '排序',
      component: 'InputNumber',
      defaultValue: 0,
    },
  ],
  showDefaultActions: false,
});

const [Modal, modalApi] = useVbenModal({
  title: '新增字典项',
  onConfirm: async () => {
    await formApi.validateAndSubmitForm();
  },
  onOpenChange(isOpen: boolean) {
    if (isOpen) {
      const { values } = modalApi.getData<Record<string, any>>();
      if (values) {
        const v = normalizeDetailRow(values);
        formApi.setValues({
          id: v.id,
          dictionary_id: v.dictionary_id,
          name: v.name,
          value: v.value,
          help_code: v.help_code,
          description: v.description,
          sort: v.sort,
        });
        modalApi.setState({ title: v.id ? '编辑字典项' : '新增字典项' });
      }
    }
  },
});

async function onSubmit(values: Record<string, any>) {
  message.loading({ content: '提交中...', key: 'dict-detail-save', duration: 0 });
  const v = normalizeDetailRow(values);
  const data: Record<string, any> = {
    dictionary_id: v.dictionary_id,
    name: v.name,
    value: String(v.value ?? ''),
    help_code: v.help_code,
    description: v.description,
    sort: v.sort ?? 0,
  };
  if (v.id) data.id = v.id;
  try {
    const res = await requestClient.post(
      backendApi('DataSave/datasave'),
      {
        tableName: 'vben_t_base_dictionary_detail',
        data: [data],
        primaryKey: 'id',
        deleteRows: [],
      }
    );
    message.success({ content: (res as any)?.message || '保存成功', key: 'dict-detail-save' });
    modalApi.close();
    (modalApi.getData() as any)?.values?.onSuccess?.();
  } catch (e: any) {
    const msg =
      e?.response?.data?.message
      ?? e?.response?.data?.error
      ?? e?.message
      ?? '保存失败';
    message.error({ content: String(msg), key: 'dict-detail-save' });
  }
}
</script>

<template>
  <Modal>
    <Form />
  </Modal>
</template>
