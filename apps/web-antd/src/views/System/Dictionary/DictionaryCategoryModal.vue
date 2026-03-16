<script setup lang="ts">
import { useVbenModal } from '@vben/common-ui';
import { message } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { requestClient } from '#/api/request';
import { backendApi } from '#/api/constants';

defineOptions({ name: 'DictionaryCategoryModal' });

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
      fieldName: 'parent_id',
      label: '父节点',
      component: 'TreeSelect',
      componentProps: {
        treeData: [],
        placeholder: '请选择父节点（不选则为根节点）',
        allowClear: true,
        treeDefaultExpandAll: true,
      },
    },
    {
      fieldName: 'name',
      label: '名称',
      component: 'Input',
      componentProps: { placeholder: '请输入字典名称' },
      rules: 'required',
    },
    {
      fieldName: 'code',
      label: '代码',
      component: 'Input',
      componentProps: { placeholder: '请输入字典代码' },
    },
    {
      fieldName: 'data_type',
      label: '类型',
      component: 'Input',
      componentProps: { placeholder: '如 string' },
    },
    {
      fieldName: 'description',
      label: '描述',
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
  title: '新增字典分类',
  onConfirm: async () => {
    await formApi.validateAndSubmitForm();
  },
  onOpenChange(isOpen: boolean) {
    if (isOpen) {
      const { values } = modalApi.getData<Record<string, any>>() ?? {};
      const ROOT = '00000000-0000-0000-0000-000000000000';
      const treeData = values?.treeData ?? [{ title: '根节点', value: ROOT, key: 'root' }];
      formApi.updateSchema([
        {
          fieldName: 'parent_id',
          componentProps: {
            treeData,
            placeholder: '请选择父节点（不选则为根节点）',
            allowClear: true,
            treeDefaultExpandAll: true,
          },
        },
      ]);
      if (values?.id) {
        modalApi.setState({ title: '编辑字典分类' });
        formApi.setValues({
          id: values.id,
          parent_id: values.parent_id ?? ROOT,
          name: values.name,
          code: values.code,
          data_type: values.data_type,
          description: values.description,
          sort: values.sort ?? 0,
        });
      } else {
        modalApi.setState({ title: '新增字典分类' });
        formApi.setValues({
          parent_id: values?.parent_id ?? ROOT,
          name: '',
          code: '',
          data_type: 'string',
          description: '',
          sort: 0,
        });
      }
    }
  },
});

interface ApiResponse {
  message: string;
}

async function onSubmit(values: Record<string, any>) {
  message.loading({ content: '提交中...', key: 'dict-save', duration: 0 });
  const ROOT = '00000000-0000-0000-0000-000000000000';
  let parentId = values.parent_id;
  if (Array.isArray(parentId)) parentId = parentId[0];
  if (!parentId || String(parentId).toLowerCase() === ROOT.toLowerCase()) {
    parentId = null;
  }
  const data: Record<string, any> = {
    name: values.name,
    code: values.code || values.name,
    data_type: values.data_type || 'string',
    description: values.description,
    parent_id: parentId,
    sort: values.sort ?? 0,
  };
  if (values.id) {
    data.id = values.id;
  }
  try {
    const res = await requestClient.post<ApiResponse>(
      backendApi('DataSave/datasave'),
      {
        tableName: 'vben_t_base_dictionary',
        data: [data],
        primaryKey: 'id',
        deleteRows: [],
      }
    );
    message.success({ content: res?.message || '保存成功', key: 'dict-save' });
    modalApi.close();
    (modalApi.getData() as any)?.values?.onSuccess?.();
  } catch (e) {
    message.error({ content: '保存失败', key: 'dict-save' });
  }
}
</script>

<template>
  <Modal>
    <Form />
  </Modal>
</template>
