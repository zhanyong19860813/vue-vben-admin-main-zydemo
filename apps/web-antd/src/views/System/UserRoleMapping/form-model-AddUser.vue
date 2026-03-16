<script lang="ts" setup>
import { useVbenModal } from '@vben/common-ui';

import { message } from 'ant-design-vue';

import { useVbenForm } from '#/adapter/form';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { reactive, ref, onMounted } from 'vue';

import { useDebounceFn } from '@vueuse/core';

defineOptions({
  name: 'formModelAddUser',
});

const keyword = ref('');
const fetching = ref(false);
const submitSuccessCb = ref<undefined | (() => void)>();


// 模拟远程获取数据
 async function fetchRemoteOptions(params: { keyword?: string } = {}) {
  fetching.value = true;
  
   // ✅ 使用传入的 searchKeyword，如果为空则用 keyword.value
    const currentKeyword = params.keyword || keyword.value || '选项';
   
    console.log('远程搜索关键词：', currentKeyword);

    const res =  await requestClient.get(
          backendApi('DynamicQueryBeta/query'),
          {
            params:
            {
              tableName: 'vben_t_sys_user',

              sortBy: 'username',
              sortOrder: 'DESC',
             // page: 1,
              //pageSize: 20,
              simpleWhere:
              {
                username:  currentKeyword
                

              }
            }
          }
        );


    console.log("远程搜索数据res:", res.items);
    const resdata= res.items.map(item=>({
      label: item.username,
      value: item.id,
      username: item.code,
      name: item.name
    }));

    return Promise.resolve(resdata);
  
}

const [Form, formApi] = useVbenForm({
  handleSubmit: onSubmit,
  schema: [
     {
      fieldName: 'role_id',
      label: '角色id',
      component: 'Input',
      //hide: true,
      componentProps: {
       //  style: { display: 'none' }, // 添加 CSS 隐藏
      }
    },

    {
      component: 'ApiSelect',
      // 对应组件的参数
      componentProps: () => {
        return {
          api: fetchRemoteOptions,
          onChange: (value, option) => {

            console.log('选择的值：', value, option);
            formApi.setFieldValue('username', option.username);
             //  formApi.setFieldValue('employee_id', option.value);
            formApi.setFieldValue('name', option.name);
            //  formApi.setFieldValue('password', '61777f2a924e9d9b2e211f583b392a94');
            //  formApi.setFieldValue('user_type', 1);
          },
          // 禁止本地过滤
          filterOption: false,
          // 如果正在获取数据，使用插槽显示一个loading
          notFoundContent: fetching.value ? undefined : null,
          // 搜索词变化时记录下来， 使用useDebounceFn防抖。
          onSearch: useDebounceFn((value: string) => {
            keyword.value = value;
          }, 300),
          // 远程搜索参数。当搜索词变化时，params也会更新
          params: {
            keyword: keyword.value || undefined,
          },
          showSearch: true,
        };
      },
      // 字段名
      fieldName: 'user_id',
      // 界面显示的label
      label: '工号',
      renderComponentContent: () => {
        return {
          //notFoundContent: fetching.value ? h(Spin) : undefined,
        };
      },
      rules: 'selectRequired',
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'name',
      label: '姓名',
      rules: 'required',
    } 
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
          submitSuccessCb.value = values.onSuccess;
        }
      }
    }
  },
  title: '添加用户到角色',
});

interface ApiResponse {
  status: number;
  message: string;
}


async function onSubmit(values: Record<string, any>) {

  console.log('提交的表单值：', values);
  const dbdata={
    role_id: values.role_id,
    user_id: values.user_id
  };

   const res = await requestClient.post<ApiResponse>(backendApi('DataSave/datasave'),
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
    if (submitSuccessCb.value) {
      submitSuccessCb.value();
    }
  }
}
  
  
    // if (submitSuccessCb.value) {
    //   submitSuccessCb.value();
    // }
  //   message.success({
  //     content: `提交成功：${JSON.stringify(values)}`,
  //     duration: 2,
  //     key: 'is-form-submitting',
  //   });
  // }, 3000);
//}
</script>
<template>
  <Modal>
    <Form />
  </Modal>
</template>
