<script setup lang="ts">
import { h, ref } from 'vue'
import { Button, message, Popconfirm, Tabs, TabPane } from 'ant-design-vue'
import { useVbenModal } from '@vben/common-ui'
import { useVbenForm } from '#/adapter/form'
import { useVbenVxeGrid } from '#/adapter/vxe-table'

const layout = ref<any[]>([])
const gridData = ref<any[]>([])
const modalTitle = ref('') // 动态标题

const [Modal, modalApi] = useVbenModal({
  onOpenChange(isOpen) {
    if (!isOpen) return

    const data = modalApi.getData()
    layout.value = data.layout || []
    gridData.value = data.gridData || []

    layout.value.forEach((item) => {
      if (item.type === 'form') {
        formApi.setState({
          schema: item.schema,
          wrapperClass: 'grid-cols-1 md:grid-cols-2',
          layout: 'horizontal',
          labelAlign: 'right',
          labelWidth: 100
        })
      }

      if (item.type === 'grid') {
        const gridOptions = {
          ...item.gridOptions,
          data: gridData.value,
          editConfig: {
            enabled: true,
            mode: 'row',
            trigger: 'click',
            showStatus: true
          }
        }

        gridApi.setGridOptions(gridOptions)
      }
    })
  }
})

const [Form, formApi] = useVbenForm({
  showDefaultActions: false,
  schema: []
})

const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    columns: [],
    data: []
  }
})

const handleAddRow = () => {
  const newRow = {
    id: Date.now(),
    code: '',
    value: 0,
    isNew: true
  }

  gridData.value = [...gridData.value, newRow]
  gridApi.setGridOptions({ data: gridData.value })
  message.success('新增行成功')
}

const handleDeleteRow = (row: any) => {
  gridData.value = gridData.value.filter(item => item.id !== row.id)
  gridApi.setGridOptions({ data: gridData.value })
  message.success('删除成功')
}

const componentMap = {
  form: () => h(Form),
  grid: () => h(Grid),
  
  tabs: (item: any) => 
    h(
      Tabs,
      {
        defaultActiveKey: '1',
        style: { marginTop: '16px', marginBottom: '16px' }
      },
      {
        default: () => [
          h(
            TabPane,
            { key: '1', tab: '表格数据' },
            {
              default: () => [
                h(Button, {
                  type: 'primary',
                  onClick: handleAddRow,
                  style: { marginBottom: '16px' }
                }, () => '➕ 新增行'),
                
                h(Grid)
              ]
            }
          ),
          h(
            TabPane,
            { key: '2', tab: '其他信息' },
            {
              default: () => [
                h('div', { style: { padding: '16px 0' } }, '其他信息内容')
              ]
            }
          )
        ]
      }
    ),

  button: (item: any) =>
    h(
      Button,
      {
        type: 'primary',
        onClick: async () => {
          if (item.action === 'submitForm') {
            const values = await formApi.validate()
            console.log('表单提交数据', values)
            message.success('表单提交成功')
          }

          if (item.action === 'custom') {
            item.onClick?.()
          }

          if (item.action === 'addRow') {
            handleAddRow()
          }
        },
        style: item.style || {}
      },
      () => item.label || '按钮'
    )
}

// 打开含表格的 Modal
function openDemo() {
  modalTitle.value = '可编辑表格示例'
  const initialGridData = [
    { id: 1, code: 'A01', value: 100 },
    { id: 2, code: 'A02', value: 200 },
    { id: 3, code: 'A03', value: 300 }
  ]

  // 先设置 gridData
  gridData.value = initialGridData
  
  // 然后设置 gridOptions
  setTimeout(() => {
    gridApi.setGridOptions({
      columns: [
        { type: 'seq', width: 60, title: '序号' },
        {
          field: 'code',
          title: '编码',
          editRender: {
            name: 'input',
            attrs: { placeholder: '请输入编码' }
          }
        },
        {
          field: 'value',
          title: '值',
          editRender: {
            name: 'input',
            attrs: { placeholder: '请输入值' }
          }
        },
        {
          field: 'action',
          title: '操作',
          width: 100,
          slots: {
            default: ({ row }: any) => {
              return h(
                Popconfirm,
                {
                  title: '确定删除吗？',
                  onConfirm: () => handleDeleteRow(row)
                },
                {
                  default: () =>
                    h(
                      Button,
                      { size: 'small', danger: true },
                      '删除'
                    )
                }
              )
            }
          }
        }
      ],
      data: initialGridData,
      pagerConfig: { enabled: false },
      height: 200,
      editConfig: {
        enabled: true,
        mode: 'row',
        trigger: 'click',
        showStatus: true
      }
    })
  }, 100)

  modalApi.setData({
    gridData: initialGridData,
    layout: [
      {
        type: 'form',
        cols: 2,
        schema: [
          { fieldName: 'name', label: '姓名', component: 'Input' },
          { fieldName: 'age', label: '年龄', component: 'InputNumber' },
          { fieldName: 'phone', label: '电话', component: 'Input' },
          { fieldName: 'email', label: '邮箱', component: 'Input' }
        ]
      },
      {
        type: 'tabs'
      },
      {
        type: 'button',
        label: '提交表单',
        action: 'submitForm',
        style: { marginTop: '16px' }
      }
    ]
  })

  modalApi.open()
}

// 打开纯表单 Modal
function openFormOnlyModal() {
  modalTitle.value = '所有表单控件示例'
  
  modalApi.setData({
    layout: [
      {
        type: 'form',
        cols: 3,
        schema: [
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
          
          // Checkbox
          { 
            fieldName: 'checkbox', 
            label: 'Checkbox', 
            component: 'Checkbox',
            renderComponentContent: () => ['同意协议']
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
          
          // Radio
          { 
            fieldName: 'radio', 
            label: 'Radio', 
            component: 'Radio',
            renderComponentContent: () => ['单选']
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
          
          // RangePicker
          { 
            fieldName: 'rangePicker', 
            label: 'RangePicker', 
            component: 'RangePicker',
            componentProps: {
              placeholder: ['开始日期', '结束日期']
            }
          },
          
          // Rate
          { 
            fieldName: 'rate', 
            label: 'Rate', 
            component: 'Rate'
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
          
          // TimePicker
          { 
            fieldName: 'timePicker', 
            label: 'TimePicker', 
            component: 'TimePicker',
            componentProps: {
              placeholder: '选择时间'
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
          
          // Upload
          { 
            fieldName: 'upload', 
            label: 'Upload', 
            component: 'Upload',
            componentProps: {
              name: 'file',
              action: '#',
              headers: { authorization: 'authorization-text' },
              listType: 'picture-card'
            },
            renderComponentContent: () => ['上传']
          },
          
          // IconPicker
          { 
            fieldName: 'iconPicker', 
            label: 'IconPicker', 
            component: 'IconPicker'
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
          modalApi.close()
        }
      }
    ]
  })

  modalApi.open()
}

function updateModalWidth(width: number) {
  modalApi.setState({ width })
}
</script>

<template>
  <div style="padding: 40px">
    <Button type="primary" @click="openDemo">
      打开动态 Modal（含表格）
    </Button>

    <Button style="margin-left:16px" type="primary" @click="openFormOnlyModal">
      打开纯表单 Modal
    </Button>

    <Button style="margin-left:16px" @click="updateModalWidth(1200)">
      设置为1200px
    </Button>

    <!-- 只有一个 Modal，根据点击的按钮动态显示不同内容 -->
    <Modal :class="modalTitle === '可编辑表格示例' ? 'w-[900px]' : 'w-[1000px]'" :title="modalTitle">
      <div style="padding:20px">
        <component
          v-for="(item,index) in layout"
          :key="index"
          :is="componentMap[item.type](item)"
        />
      </div>
    </Modal>
  </div>
</template>
