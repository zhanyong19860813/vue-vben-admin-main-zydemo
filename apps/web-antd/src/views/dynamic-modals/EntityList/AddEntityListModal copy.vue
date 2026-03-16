<script setup lang="ts">
import { Button, message } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { useVbenModal } from '@vben/common-ui';
import { requestClient } from '#/api/request';

defineOptions({ name: 'AddEntityListModal' });
 
/**
 * ⭐ 用 useVbenModal 包一层
 */
// const [ModalF, modalApi] = useVbenModal({
//   fullscreenButton: false,
//   onCancel() {
//     modalApi.close();
//   },
//   onConfirm: async () => {
//     await handleOk();
//   },
// });

/**
 * ⭐ useVbenForm 正确用法（和你成功页面一致）
 */
// const [Form, formApi] = useVbenForm({
//   //showActionButtonGroup: false,
//   schemas: [
//     {
//       field: 'entity_name',
//       label: '实体名',
//       component: 'Input',
//       required: true,
//       componentProps: { placeholder: '请输入实体名' },
//     },
//     {
//       field: 'title',
//       label: '标题',
//       component: 'Input',
//       required: true,
//       componentProps: { placeholder: '请输入标题' },
//     },
//     {
//       field: 'tableName',
//       label: '实体名称',
//       component: 'Input',
//       required: true,
//       componentProps: { placeholder: '请输入表名' },
//     },
//     {
//       field: 'primaryKey',
//       label: '主键',
//       component: 'Input',
//       defaultValue: 'id',
//     },
//     {
//       field: 'deleteEntityName',
//       label: '删除实体名',
//       component: 'Input',
//     },
//     {
//       field: 'defaultSchema',
//       label: '默认 Schema 文件名',
//       component: 'Input',
//     },
//     {
//       field: 'status',
//       label: '状态',
//       component: 'Input',
//     },
//     {
//       field: 'actionModule',
//       label: '自定义事件文件名',
//       component: 'Input',
//     },
//     {
//       field: 'sortFieldName',
//       label: '排序字段名',
//       component: 'Input',
//     },
//     {
//       field: 'sortType',
//       label: '排序 asc|desc',
//       component: 'Input',
//     },
//   ],
// });

async function onSubmit(values: Record<string, any>) {

  console.log('提交的表单值：', values);
  const dbdata={
    role_id: values.role_id,
    user_id: values.user_id
  };

   const res = await requestClient.post<ApiResponse>('http://localhost:5155/api/DataSave/datasave',
    {
      //tableName: "vben_t_sys_user",
      tableName: "vben_t_sys_user_role",
      
       data:[dbdata] ,
      primaryKey: "id",
     
      deleteRows: []
    });
    // ,
    // {
    //   headers: { 'Content-Type': 'application/json' }
    // }
 


  message.loading({
    content: '正在提交中...',
    duration: 0,
    key: 'is-Userform-submitting',
  });


 
 if (res.message === '保存成功') {
    message.success({
      content: '保存成功',
      key: 'is-Userform-submitting', // 👈 覆盖 loading
      duration: 2,
    });


   // modalApi.lock();
    modalApi.close();

    // 通知父组件刷新树结构
    // if (submitSuccessCb.value) {
    //   submitSuccessCb.value();
    // }
  }
}

const [Form, formApi] = useVbenForm({
  handleSubmit: onSubmit,
    schemas: [
    {
      field: 'entity_name',
      label: '实体名',
      component: 'Input',
      required: true,
      componentProps: { placeholder: '请输入实体名' },
    },
    {
      field: 'title',
      label: '标题',
      component: 'Input',
      required: true,
      componentProps: { placeholder: '请输入标题' },
    },
    {
      field: 'tableName',
      label: '实体名称',
      component: 'Input',
      required: true,
      componentProps: { placeholder: '请输入表名' },
    },
    {
      field: 'primaryKey',
      label: '主键',
      component: 'Input',
      defaultValue: 'id',
    },
    {
      field: 'deleteEntityName',
      label: '删除实体名',
      component: 'Input',
    },
    {
      field: 'defaultSchema',
      label: '默认 Schema 文件名',
      component: 'Input',
    },
    {
      field: 'status',
      label: '状态',
      component: 'Input',
    },
    {
      field: 'actionModule',
      label: '自定义事件文件名',
      component: 'Input',
    },
    {
      field: 'sortFieldName',
      label: '排序字段名',
      component: 'Input',
    },
    {
      field: 'sortType',
      label: '排序 asc|desc',
      component: 'Input',
    },
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
        if (values.onSuccess) {
          //submitSuccessCb.value = values.onSuccess;
        }
      }
    }
  },
  title: '添加用户到角色',
});
/**
 * 保存
 */
async function handleOk() {
  try {
    const values = await formApi.validate();

    await requestClient.post('/api/entitylist/add', values);

    message.success('新增成功');

    modalApi.close();
  } catch (err) {
    console.error(err);
  }
}
</script>

<template>
 
  <Modal>
    <Form />
  </Modal>
 

</template>
