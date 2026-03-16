<script setup lang="ts">
import { Button, message } from 'ant-design-vue';
import QueryTable from '#/components/QueryTable/index.vue';
import { companySchema } from './company.schema';

import { employeeSchema } from './employee.schema';
import { useRoute } from 'vue-router';
 import { computed } from 'vue';


import { h, ref } from 'vue'
import { useVbenModal } from '@vben/common-ui'
import { useVbenForm } from '#/adapter/form'


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
    case 'car':
      return employeeSchema;
    default:
      return employeeSchema; // 兜底
  }
});
console.log('当前实体:route.meta', route.meta);
console.log('当前实体 参数:', route.meta.query?.entityname);



// 模态框相关代码 begin
const formLayout = ref<any[]>([])

const cols = 2

const [FormOnlyModal, formOnlyModalApi] = useVbenModal({
  onOpenChange(isOpen) {
    if (!isOpen) return

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

function openFormOnlyModal() {
  formOnlyModalApi.setData({
    layout: [
      {
        type: 'form',
        cols: 4,
        schema: [
          // Input
          { 
            fieldName: 'input', 
            label: 'Input', 
            component: 'Input',
            componentProps: {
              placeholder: '请输入'
            }
          },
          
          // InputNumber
          { 
            fieldName: 'inputNumber', 
            label: 'InputNumber', 
            component: 'InputNumber',
            componentProps: {
              placeholder: '请输入数字',
              min: 0,
              max: 100
            }
          },
          
          // InputPassword
          { 
            fieldName: 'inputPassword', 
            label: 'InputPassword', 
            component: 'InputPassword',
            componentProps: {
              placeholder: '请输入密码'
            }
          },
          
          // AutoComplete
          { 
            fieldName: 'autoComplete', 
            label: 'AutoComplete', 
            component: 'AutoComplete',
            componentProps: {
              options: [
                { value: '选项1' },
                { value: '选项2' },
                { value: '选项3' }
              ],
              placeholder: '请输入'
            }
          },
          
          // Select
          { 
            fieldName: 'select', 
            label: 'Select', 
            component: 'Select',
            componentProps: {
              options: [
                { label: '黄金会员', value: 'gold' },
                { label: '白金会员', value: 'platinum' },
                { label: '钻石会员', value: 'diamond' }
              ],
              placeholder: '请选择'
            }
          },
          
          // RadioGroup
          { 
            fieldName: 'radioGroup', 
            label: 'RadioGroup', 
            component: 'RadioGroup',
            componentProps: {
              options: [
                { label: '选项X', value: 'X' },
                { label: '选项Y', value: 'Y' },
                { label: '选项Z', value: 'Z' }
              ]
            }
          },
          
          // CheckboxGroup
          { 
            fieldName: 'checkboxGroup', 
            label: 'CheckboxGroup', 
            component: 'CheckboxGroup',
            componentProps: {
              options: [
                { label: '选项A', value: 'A' },
                { label: '选项B', value: 'B' },
                { label: '选项C', value: 'C' }
              ]
            }
          },
          
          // DatePicker
          { 
            fieldName: 'datePicker', 
            label: 'DatePicker', 
            component: 'DatePicker',
            componentProps: {
              placeholder: '选择日期'
            }
          },
          
          // RangePicker
          { 
            fieldName: 'rangePicker', 
            label: 'RangePicker', 
            component: 'RangePicker',
            componentProps: {
              placeholder: ['开始日期', '结束日期']
            }
          },
          
          // TimePicker
          { 
            fieldName: 'timePicker', 
            label: 'TimePicker', 
            component: 'TimePicker',
            componentProps: {
              placeholder: '选择时间'
            }
          },
          
          // Switch
          { 
            fieldName: 'switch', 
            label: 'Switch', 
            component: 'Switch',
            componentProps: {
              checkedChildren: '开启',
              unCheckedChildren: '关闭'
            }
          },
          
          // Rate
          { 
            fieldName: 'rate', 
            label: 'Rate', 
            component: 'Rate'
          },
          
          // Textarea
          { 
            fieldName: 'textarea', 
            label: 'Textarea', 
            component: 'Textarea',
            componentProps: {
              placeholder: '请输入多行文本',
              rows: 3
            }
          },
          
          // TreeSelect
          { 
            fieldName: 'treeSelect', 
            label: 'TreeSelect', 
            component: 'TreeSelect',
            componentProps: {
              treeData: [
                {
                  title: '根节点',
                  value: 'root',
                  children: [
                    { title: '子节点1', value: 'child1' },
                    { title: '子节点2', value: 'child2' }
                  ]
                }
              ],
              placeholder: '请选择'
            }
          },
          
          // Mentions
          { 
            fieldName: 'mentions', 
            label: 'Mentions', 
            component: 'Mentions',
            componentProps: {
              options: [
                { value: 'user1', label: '用户1' },
                { value: 'user2', label: '用户2' }
              ],
              placeholder: '@提及用户'
            }
          },
          
          // IconPicker
          { 
            fieldName: 'iconPicker', 
            label: 'IconPicker', 
            component: 'IconPicker'
          },
          
          // Upload
          { 
            fieldName: 'upload', 
            label: 'Upload', 
            component: 'Upload',
            componentProps: {
              name: 'file',
              action: '#',
              listType: 'picture-card'
            },
            renderComponentContent: () => ['上传']
          }
        ]
      },

      {
        type: 'button',
        label: '提交',
        action: 'submitForm',
        style: { marginTop: '16px' }
      },

      {
        type: 'button',
        label: '取消',
        action: 'custom',
        style: { marginLeft: '8px' },
        onClick: () => {
          formOnlyModalApi.close()
        }
      }
    ]
  })

  formOnlyModalApi.open()
}
</script>
<template>
 <QueryTable :schema="currentSchema">
  <template #toolbar-tools="{ gridApi }">
    <Button @click="handleAdd">新增code</Button>
    <Button @click="handleCustom(gridApi)">自定义code</Button>
  </template>
</QueryTable>

<!-- 
<FormOnlyModal class="w-[1000px]" title="所有表单控件示例">
      <div style="padding:20px">
        <component
          v-for="(item,index) in formLayout"
          :key="index"
          :is="componentMap[item.type](item)"
        />
      </div>
    </FormOnlyModal> -->
</template>   
