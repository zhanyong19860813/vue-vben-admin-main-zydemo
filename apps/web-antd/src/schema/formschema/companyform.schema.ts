import { useVbenForm,z } from '#/adapter/form'

export const formDemoLayout = [
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
        },
        defaultValue: '测试默认值'
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
    style: { marginLeft: '8px' }
  }
]


interface FormLayout {
  type: 'form'
  cols: number
  schema: any[]
}

interface ButtonLayout {
  type: 'button'
  label: string
  action: string
  style?: Record<string, any>
}

type LayoutItem = FormLayout | ButtonLayout

export const getFormDemoLayoutData = (
  FormValues: Record<string, any>
): LayoutItem[] => {

  let schema = [
    // Input
    {
      fieldName: 'FID',
      label: 'ID',
      component: 'Input',
      componentProps: {
        placeholder: '请输入'
      }
    },

    {
      fieldName: 'Name',
      label: '公司名称',
      component: 'Input',
      componentProps: {
        placeholder: '请输入'
      },
      rules: 'required',
      // ,
      // rules: [
      //   {
      //     required: true,
      //     message: '公司名称不能为空'
      //   }
      // ]
    },
    {
      fieldName: 'SimpleName',
      label: '简称',
      component: 'Input',
      componentProps: {
        placeholder: '请输入'
      },
        rules:z.string().regex(/^[0-9]+$/, '只能输入数字')
    },
    {
      fieldName: 'Location',
      label: '地址',
      component: 'Input',
      componentProps: {
        placeholder: '请输入'
      }
    }
  ];


  return [
    {
      type: 'form',
      cols: 4,
      schema: fillDefaultValue(schema, FormValues)
    }
    // ,
    // {
    //   type: 'button',
    //   label: '提交',
    //   action: 'submitForm',
    //   style: { marginTop: '16px' }
    // },
    // {
    //   type: 'button',
    //   label: '取消',
    //   action: 'custom',
    //   style: { marginLeft: '8px' }
    // }
  ]
}


function fillDefaultValue(schema: any[], values: any) {
  return schema.map(item => ({
    ...item,
    defaultValue: values?.[item.fieldName] ?? item.defaultValue
  }))
}
