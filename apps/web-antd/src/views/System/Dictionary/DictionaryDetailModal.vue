<script setup lang="ts">
import { useVbenModal } from '@vben/common-ui';
import { message } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

defineOptions({ name: 'DictionaryDetailModal' });

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
        formApi.setValues({
          id: values.id,
          dictionary_id: values.dictionary_id,
          name: values.name,
          value: values.value,
          help_code: values.help_code,
          description: values.description,
          sort: values.sort ?? 0,
        });
        modalApi.setState({ title: values.id ? '编辑字典项' : '新增字典项' });
      }
    }
  },
});

async function onSubmit(values: Record<string, any>) {
  message.loading({ content: '提交中...', key: 'dict-detail-save', duration: 0 });
  const data: Record<string, any> = {
    dictionary_id: values.dictionary_id,
    name: values.name,
    value: String(values.value),
    help_code: values.help_code,
    description: values.description,
    sort: values.sort ?? 0,
  };
  if (values.id) data.id = values.id;
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
  } catch (e) {
    message.error({ content: '保存失败', key: 'dict-detail-save' });
  }
}
</script>

<template>
  <Modal>
    <Form />
  </Modal>
</template>
