<script setup lang="ts">
import { ref, watch } from 'vue'
import { useVbenModal } from '@vben/common-ui'
import { useVbenForm } from '#/adapter/form'
import { useVbenVxeGrid } from '#/adapter/vxe-table'
import { message } from 'ant-design-vue'

const mode = ref<'form' | 'form+table'>('form')
const title = ref('')

const formSchema = ref<any[]>([])
const gridOptions = ref<any>({})

/**
 * Modal
 */
const [Modal, modalApi] = useVbenModal({
  onOpenChange(isOpen) {
    if (!isOpen) return

    const data = modalApi.getData()

    mode.value = data.mode
    title.value = data.title

    formSchema.value = data.formSchema || []
    gridOptions.value = data.gridOptions || {}

    formApi.setState({
      schema: formSchema.value
    })

    gridApi.setState({
      gridOptions: gridOptions.value
    })
  }
})

/**
 * 表单
 */
const [Form, formApi] = useVbenForm({
  showDefaultActions: false,
  schema: []
})

/**
 * 表格
 */
const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    columns: [],
    data: [],
    pagerConfig: { enabled: false }
  }
})

/**
 * 提交
 */
async function handleSubmit() {
  const values = await formApi.validate()

  console.log('表单数据', values)

  message.success('提交成功')

  modalApi.close()
}
</script>

<template>
  <Modal>
    <div style="padding:20px">

      <h3>{{ title }}</h3>

      <!-- 表单 -->
      <Form />

      <!-- 表格 -->
      <div v-if="mode === 'form+table'" style="margin-top:20px">
        <Grid />
      </div>

      <div style="margin-top:20px">
        <a-button type="primary" @click="handleSubmit">
          提交
        </a-button>
      </div>

    </div>
  </Modal>
</template>
