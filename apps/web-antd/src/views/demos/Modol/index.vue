<script setup lang="ts">
import { ref } from 'vue'
import { Button } from 'ant-design-vue'
import { useVbenModal } from '@vben/common-ui'
import DynamicComplexModal from './DynamicComplexModal.vue'
import FormTabsTableModal from '#/components/FormTabsTableModal/index.vue'
import type { TabTableItem } from '#/components/FormTabsTableModal'

/**
 * ============================
 * Modal
 * ============================
 */

const [Modal, modalApi] = useVbenModal({
  connectedComponent: DynamicComplexModal,
  width: 800
})

/**
 * 表单 + 页签 + 表格 弹窗
 */
const formTabsTableModalRef = ref<InstanceType<typeof FormTabsTableModal>>()

function openFormTabsTableModal() {
  const formSchema = [
    { fieldName: 'name', label: '名称', component: 'Input', componentProps: { placeholder: '请输入' } },
    { fieldName: 'code', label: '编码', component: 'Input', componentProps: { placeholder: '请输入' } }
  ]

  const tabs: TabTableItem[] = [
    {
      key: 'detail',
      tab: '明细列表',
      gridOptions: {
        columns: [
          { type: 'seq', width: 60 },
          { field: 'code', title: '编码' },
          { field: 'value', title: '金额' }
        ],
        data: [
          { code: 'A001', value: 100 },
          { code: 'A002', value: 200 }
        ],
        pagerConfig: { enabled: false }
      }
    },
    {
      key: 'log',
      tab: '操作日志',
      gridOptions: {
        columns: [
          { type: 'seq', width: 60 },
          { field: 'time', title: '时间' },
          { field: 'action', title: '操作' }
        ],
        data: [
          { time: '2024-01-01', action: '创建' },
          { time: '2024-01-02', action: '修改' }
        ],
        pagerConfig: { enabled: false }
      }
    }
  ]

  formTabsTableModalRef.value?.setData({
    title: '表单 + 页签 + 表格',
    formSchema,
    tabs
  })
  formTabsTableModalRef.value?.open()
}

function onFormTabsTableSuccess(values: Record<string, any>) {
  console.log('表单提交数据', values)
}

/**
 * ============================
 * 按钮打开 Modal
 * ============================
 */

// 只有表单
function openFormA() {

  const schema = [
    {
      fieldName: 'name',
      label: '名称',
      component: 'Input'
    },
    {
      fieldName: 'desc',
      label: '描述',
      component: 'Input'
    }
  ]

  modalApi
    .setData({
      title: '只有表单',
      mode: 'form',
      formSchema: schema
    })
    .open()
}


// 表单 + 表格
function openFormWithTable() {

  const schema = [
    {
      fieldName: 'user',
      label: '用户',
      component: 'Input'
    },
    {
      fieldName: 'age',
      label: '年龄',
      component: 'Input'
    }
  ]

  const gridOptions = {
    columns: [
      { type: 'seq', width: 60 },
      { field: 'code', title: '编码' },
      { field: 'value', title: '值' }
    ],
    data: [
      { code: 'A001', value: 100 },
      { code: 'A002', value: 200 }
    ],
    pagerConfig: { enabled: false }
  }

  modalApi
    .setData({
      title: '表单 + 表格',
      mode: 'form+table',
      formSchema: schema,
      gridOptions
    })
    .open()
}
</script>

<template>
  <div style="padding:40px">

    <Button type="primary" @click="openFormA">
      打开：只有表单
    </Button>

    <Button
      type="primary"
      style="margin-left:16px"
      @click="openFormWithTable"
    >
      打开：表单 + 表格
    </Button>

    <Button
      type="primary"
      style="margin-left:16px"
      @click="openFormTabsTableModal"
    >
      打开：表单 + 页签 + 表格
    </Button>

    <!-- Modal 挂载点 -->
    <Modal />

    <FormTabsTableModal
      ref="formTabsTableModalRef"
      @success="onFormTabsTableSuccess"
    />

  </div>
</template>
