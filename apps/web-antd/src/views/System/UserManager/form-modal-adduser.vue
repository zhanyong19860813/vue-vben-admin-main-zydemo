<script lang="ts" setup>
import { useVbenModal } from '@vben/common-ui';

import { message } from 'ant-design-vue';

import { useVbenForm } from '#/adapter/form';
import { requestClient } from '#/api/request';
import { reactive, ref, onMounted } from 'vue';

import { useDebounceFn } from '@vueuse/core';

defineOptions({
  name: 'FormModelDemo',
});

const keyword = ref('');
const fetching = ref(false);
// 模拟远程获取数据
 async function fetchRemoteOptions(params: { keyword?: string } = {}) {
  fetching.value = true;
  
   // ✅ 使用传入的 searchKeyword，如果为空则用 keyword.value
    const currentKeyword = params.keyword || keyword.value || '选项';
   
    console.log('远程搜索关键词：', currentKeyword);

    const res =  await requestClient.get(
          'http://localhost:5155/api/DynamicQueryBeta/query',
          {
            params:
            {
              tableName: 't_base_employee',

              sortBy: 'code',
              sortOrder: 'DESC',
             // page: 1,
              //pageSize: 20,
              simpleWhere:
              {
                name:  currentKeyword
                

              }
            }
          }
        );

    console.log("远程搜索数据res:", res.items);
    const resdata= res.items.map(item=>({
      label: item.name,
      value: item.id,
      username: item.code
    }));
  // const mockData = [
  //     { id: '1', name: `${currentKeyword}-1` },
  //     { id: '2', name: `${currentKeyword}-2` },
  //     { id: '3', name: `${currentKeyword}-3` },
  //     { id: '4', name: `${currentKeyword}-4` },
  //   ];
  //    fetching.value = false;
  //   // 转换为Select需要的格式
  //   const resdata= mockData.map(item => ({
  //     label: item.name,
  //     value: item.id,
  //   }));

    return Promise.resolve(resdata);
  // return new Promise((resolve) => {
  //   setTimeout(() => {
  //     const options = Array.from({ length: 10 }).map((_, index) => ({
  //       label: `${keyword}-${index}`,
  //       value: `${keyword}-${index}`,
  //     }));
  //     resolve(options);
  //     fetching.value = false;
  //   }, 1000);
  // });
}

const [Form, formApi] = useVbenForm({
  handleSubmit: onSubmit,
  schema: [
    //  {
    //   fieldName: 'employee_id',
    //   label: '',
    //   component: 'Input',
    //   //hide: true,
    //   componentProps: {
    //      style: { display: 'none' }, // 添加 CSS 隐藏
    //   }
    // },

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
            formApi.setFieldValue('name', option.label);
             formApi.setFieldValue('password', '61777f2a924e9d9b2e211f583b392a94');
             formApi.setFieldValue('user_type', 1);
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
      fieldName: 'employee_id',
      // 界面显示的label
      label: '姓名',
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
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'username',
      label: '账号',
      rules: 'required',
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'password',
      label: '密码',
      rules: 'required',
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'user_type',
      label: '用户类型',
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
      tableName: "vben_t_sys_user",
       data:[values] ,
      primaryKey: "id",
     
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
