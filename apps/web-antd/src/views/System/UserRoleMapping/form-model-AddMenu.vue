<script lang="ts" setup>
import { useVbenModal } from '@vben/common-ui';

import { message } from 'ant-design-vue';

import { useVbenForm } from '#/adapter/form';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';
import { reactive, ref, onMounted } from 'vue';

import { useDebounceFn } from '@vueuse/core';
import type path from 'path';

defineOptions({
  name: 'formModelAddMenu',
});

const keyword = ref('');
const fetching = ref(false);

const submitSuccessCb = ref<undefined | (() => void)>();
//  获取菜单数据
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
              tableName: 'vben_menus_new',

              sortBy: 'name',
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
      path: item.path,
      component: item.component ,
      meta: item.meta
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
            formApi.setFieldValue('path', option.path);
             //  formApi.setFieldValue('employee_id', option.value);
            formApi.setFieldValue('name', option.label);
            formApi.setFieldValue('component', option.component);
            formApi.setFieldValue('meta', option.meta); 
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
          style: { width: '100%' },
        };
      },
      // 字段名
      fieldName: 'menus_id',
      // 界面显示的label
      label: '菜单名称',
      renderComponentContent: () => {
        return {
          //notFoundContent: fetching.value ? h(Spin) : undefined,
        };
      },
      rules: 'selectRequired',
    }
    ,
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'name',
      label: '菜单名称',
      rules: 'required',
    } ,
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'path',
      label: '路径',
      rules: 'required',
    } 
    ,
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'component',
      label: '组件路径',
      rules: 'required',
    } 
    ,
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'meta',
      label: '菜单元信息',
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
  title: '添加菜单到角色',
});

interface ApiResponse {
  status: number;
  message: string;
}
async function onSubmit(values: Record<string, any>) {

  console.log('提交的表单值：', values);
  const dbdata={
    role_id: values.role_id,
    menus_id: values.menus_id,
    bar_items:"*",
    operate_range_type: "ALL"
  };

 const res = await  requestClient.post<ApiResponse>(backendApi('DataSave/datasave'),
    {
      //tableName: "vben_t_sys_user",
      tableName: "vben_t_sys_role_menus",
      
       data:[dbdata] ,
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
    key: 'is-Menuform-submitting',
  });


 
 if (res.message === '保存成功') {
    message.success({
      content: '保存成功',
      key: 'is-Menuform-submitting', // 👈 覆盖 loading
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
