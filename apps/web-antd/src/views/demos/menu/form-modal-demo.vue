<script lang="ts" setup>
import { useVbenModal } from '@vben/common-ui';

import { message } from 'ant-design-vue';

import { useVbenForm } from '#/adapter/form';
import { requestClient } from '#/api/request';


defineOptions({
  name: 'FormModelDemo',
});

const [Form, formApi] = useVbenForm({
  handleSubmit: onSubmit,
  schema: [
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'Name',
      label: '公司名',
      rules: 'required',
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'SimpleName',
      label: '简称',
      rules: 'required',
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'Location',
      label: '地址',
      rules: 'required',
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'Code',
      label: '代码',
      rules: 'required',
    },

    // {
    //   component: 'Select',
    //   componentProps: {
    //     options: [
    //       { label: '选项1', value: '1' },
    //       { label: '选项2', value: '2' },
    //     ],
    //     placeholder: '请输入',
    //   },
    //   fieldName: 'field3',
    //   label: '字段3',

    // },
  ],
  showDefaultActions: false,
});

const [Modal, modalApi] = useVbenModal({
  fullscreenButton: false,
  onCancel() {
    modalApi.close();
  },
  onConfirm: async () => {
    await formApi.validateAndSubmitForm();
    // modalApi.close();
  },
  onOpenChange(isOpen: boolean) {
    if (isOpen) {
      const { values } = modalApi.getData<Record<string, any>>();
      if (values) {
        formApi.setValues(values);
      }
    }
  },
  title: '内嵌表单示例',
});

interface ApiResponse {
  status: number;
  message: string;
}
function onSubmit(values: Record<string, any>) {


  console.log('提交的表单值：', values);

 requestClient.post<ApiResponse>('http://localhost:5155/api/DataSave/datasave',
    {
      tableName: "t_base_company",
       data:[values] ,
      primaryKey: "FID",
     
      deleteRows: []
    }
    // ,
    // {
    //   headers: { 'Content-Type': 'application/json' }
    // }
  );


  message.loading({
    content: '正在提交中...',
    duration: 0,
    key: 'is-form-submitting',
  });
  modalApi.lock();
  setTimeout(() => {
    modalApi.close();
    message.success({
      content: `提交成功：${JSON.stringify(values)}`,
      duration: 2,
      key: 'is-form-submitting',
    });
  }, 3000);
}
</script>
<template>
  <Modal>
    <Form />
  </Modal>
</template>
