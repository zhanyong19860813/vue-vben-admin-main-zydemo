<script lang="ts" setup>
import { useVbenModal } from '@vben/common-ui';

import { message } from 'ant-design-vue';

import { useVbenForm } from '#/adapter/form';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { reactive, ref, onMounted } from 'vue';


defineOptions({
  name: 'AddRoleFormModel',
});

const [Form, formApi] = useVbenForm({
  handleSubmit: onSubmit,
  schema: [
    {
      fieldName: 'parent_id',
      label: '',
      component: 'Input',
      //hide: true,
      componentProps: {
        style: { display: 'none' }, // 添加 CSS 隐藏
      }
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'ParentName',
      label: '父节点：',
      rules: 'required',
    },

    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'SimpleName',
      label: '节点名',
      rules: 'required',
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'datatype',
      label: '角色类型',
      defaultValue: 'ROLE', // 👈 默认值
      rules: 'required',
    }
  ],
  showDefaultActions: false
}
);
const submitSuccessCb = ref<undefined | (() => void)>();
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
        //formApi.setValues(values);
        console.log("onOpenChange传递过来的值values:", values);
        formApi.setValues({
          ParentName: values.ParentName, // 给人看的
          parent_id: values.parent_id,   // 👈 隐藏字段
          datatype: 'ROLE',               // 👈 你也可以统一在这设
        });
        //onOpenChange
        // 👇 把 刷新树  回调缓存起来，submit 时用 
        submitSuccessCb.value = values?.onSuccess;
      }
    }
  },
  title: '新增角色',
});

interface ApiResponse {
  message: string;
}
async function onSubmit(values: Record<string, any>) {

  // 1️⃣ 先校验 schema 字段
  formApi.validate();

  // 2️⃣ 拿完整 form model（包含 parent_id）
  const sbumitdata = { name: values.SimpleName, parent_id: values.parent_id, datatype: values.datatype };

  message.loading({
    content: '正在提交中...',
    duration: 0,
    key: 'is-form-submitting',
  });
  const res = await requestClient.post<ApiResponse>(backendApi('DataSave/datasave'),
    {
      tableName: "vben_role",
      data: [sbumitdata],
      primaryKey: "id",
      deleteRows: []
    }
    // ,
    // {
    //   headers: { 'Content-Type': 'application/json' }
    // }
  );

  console.log('提交结果：', res);
  if (res.message === '保存成功') {
    message.success({
      content: '保存成功',
      key: 'is-form-submitting', // 👈 覆盖 loading
      duration: 2,
    });


   // modalApi.lock();
    modalApi.close();

    // 通知父组件刷新树结构
    if (submitSuccessCb.value) {
      submitSuccessCb.value();
    }
  }


}
</script>
<template>

  <Modal>
    <Form />
  </Modal>
</template>
