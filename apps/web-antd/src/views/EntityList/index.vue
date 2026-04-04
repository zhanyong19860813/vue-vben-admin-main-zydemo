<script setup lang="ts">
import { Button, message } from 'ant-design-vue';
import QueryTable from '#/components/QueryTable/index.vue';
import { companySchema } from './company.schema';

import { employeeSchema } from './employee.schema';
import { useRoute } from 'vue-router';
 import { computed } from 'vue';


import { h, ref } from 'vue'
import { useVbenModal } from '@vben/common-ui'
import { useVbenForm,z } from '#/adapter/form'

import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

import  {formDemoLayout,getFormDemoLayoutData} from '#/schema/formschema/companyform.schema'
//D:\code\vue-vben-admin-main\vue-vben-admin-main\apps\web-antd\src\schema\formschema\formDemo.schema.ts

const handleAdd = () => {
  message.success('新增按钮点击');
};

const handleCustom = (gridApi: any) => {
  const rows = gridApi.grid?.getCheckboxRecords();
  message.success(`选中 ${rows.length} 条`);
};


const route = useRoute();
//const entityName = route.query.entityname as string;

//console.log('当前实体:route', route);
//const entityName = route.meta.entityname as string
const entityName = computed(() => {
  // 你现在是从 meta.query 拿，这是对的
  return route.meta.query?.entityname as string;
});

const currentSchema = computed(() => {

  console.log('当前实体:entityName', entityName.value);
  switch (entityName.value) {
    case 'company':
      return companySchema;
    case 'user':
      return companySchema;
    // case 'car':
    //   return employeeSchema;
     case 'car':
      return companySchema;
    default:
      return companySchema; // 兜底
  }
});
console.log('当前实体:route.meta', route.meta);
console.log('当前实体 参数:', route.meta.query?.entityname);



// 模态框相关代码 begin
const formLayout = ref<any[]>([])

const showModal = ref(false)

const cols = 2

const [FormOnlyModal, formOnlyModalApi] = useVbenModal({
  onOpenChange(isOpen) {
    if (!isOpen) return

      showModal.value = true
    const data = formOnlyModalApi.getData()
    formLayout.value = data.layout || []

    formLayout.value.forEach((item) => {
      if (item.type === 'form') {
        formApi.setState({
          schema: item.schema,
          //wrapperClass: 'grid-cols-1 md:grid-cols-2 lg:grid-cols-3',
            wrapperClass: `grid-cols-${cols}`,
          layout: 'horizontal',
          labelAlign: 'right',
          labelWidth: 100
        })
      }
    })
  },
    // ⭐ 这里就是提交按钮
  async onConfirm() {
    
    //数据校验
    //const values = await formApi.validate()

      const formsvalues = await formApi.getValues()

      const saveEntityName = currentSchema.value.saveEntityName ;
      const primaryKey = currentSchema.value.primaryKey || 'id' ;
      if (saveEntityName == undefined||saveEntityName == null||saveEntityName == '') {
        message.success(`保存实体：${saveEntityName}`);
        return ;
      }  
      
         //通用保存方法
        let tables = [{ tableName: saveEntityName, primaryKey: primaryKey, data: [formsvalues], deleteRows: [] },];
        // if (btnSaveData.length > 0) {
        //   tables.push({ tableName: "vben_menu_actions", primaryKey: "id", data: btnSaveData, deleteRows: btnDeleteRows });
        // }
         
        //console.log('保存数据 tables', tables)
        await requestClient.post<any>(
          backendApi('DataSave/datasave-multi'),
          {
            tables:  tables
          }
        );

       
      //saveEntityName = currentSchema.value.saveEntityName || currentSchema.value.entityName || '未知实体'
      //message.success(  JSON.stringify(formsvalues))
      message.success('表单提交成功')
       formOnlyModalApi.close()
       gridApi.grid.reload() // 刷新表格数据
    //message.success('当前保存实体：' + entityName.value)

    //formOnlyModalApi.close()
  },
  onCancel() {
  console.log('点击取消')
  formOnlyModalApi.close()
}
})

const [Form, formApi] = useVbenForm({
  showDefaultActions: false,
  schema: []
})


const componentMap = {
  form: () => h(Form),
  
  button: (item: any) =>
    h(
      Button,
      {
        type: item.type || 'primary',
        onClick: async () => {
          if (item.action === 'submitForm') {
            const values = await formApi.validate()
            console.log('表单提交数据', values)
            message.success('表单提交成功')
          }

          if (item.action === 'custom') {
            item.onClick?.()
          }
        },
        style: item.style || {}
      },
      () => item.label || '按钮'
    )
}

/// 打开表单模态框  新增或者编辑
function openFormOnlyModal( type: 'add' | 'edit',gridApi: any) {
   showModal.value = true
     let  selectedRows = gridApi.grid.getCheckboxRecords();
     
     let formValue= type === 'edit' ? selectedRows[0] : {} ;
     
     if(type === 'edit' && !selectedRows.length){
       message.warning('请至少选择一条数据进行编辑')
       return
     }
     console.log('选中数据', selectedRows)
   
  formOnlyModalApi.setData({
    // layout: formDemoLayout
      layout:getFormDemoLayoutData(formValue)
  })

  formOnlyModalApi.open()
}
</script>
<template>
  <div class="flex h-full min-h-0 flex-1 flex-col overflow-hidden">
 <QueryTable :schema="currentSchema">
  <template #toolbar-tools="{ gridApi }">
    <Button @click="handleAdd">新增code</Button>
    <Button @click="handleCustom(gridApi)">自定义code</Button>
     
    <Button type="primary" @click="openFormOnlyModal('add', gridApi)">
      新增
    </Button>
      <Button type="primary" @click="openFormOnlyModal('edit', gridApi)">
      编辑
    </Button>
    <FormOnlyModal    class="w-[1000px]" title="所有表单控件示例">
      <div style="padding:20px">
        <component
          v-for="(item,index) in formLayout"
          :key="index"
          :is="componentMap[item.type](item)"
        />
      </div>
    </FormOnlyModal> 
  </template>
</QueryTable>
  </div>

</template>   
