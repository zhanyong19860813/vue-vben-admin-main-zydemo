<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, onBeforeRouteUpdate } from 'vue-router'
import QueryTable from '#/components/QueryTable/index.vue'
import { companySchema } from './company.schema'
import { employeeSchema } from './employee.schema'
import { backendApi } from '#/api/constants'
import { requestClient } from '#/api/request'
import { message } from 'ant-design-vue'

//2026-03-09 begin：重构后的版本， 
import { Button, } from 'ant-design-vue';
import { h } from 'vue'
import { useVbenModal } from '@vben/common-ui'
import { useVbenForm, z } from '#/adapter/form'
import { getFormDemoLayoutData } from '#/schema/formschema/entity_list.schema'




// 路由
const route = useRoute()

// 响应式状态
const schema = ref<any>(null)
const isLoading = ref(false)

//当前列表在 数据库 vben_entity_list 的id 
const currentEntityListId = ref<string>('');


  const currentSchema = ref<any[]>([]); // 当前表格的列定义

// 计算 entityName / menuId
const entityName = computed(() => route.meta.query?.entityname as string)
const menuId = computed(() => route.meta.query?.menuid as string)

// 系统操作日志本地 schema（当 VbenSchema/GetSchema 未配置该实体时兜底）
const operationLogSchema = {
  title: '系统操作日志',
  tableName: 'vben_sys_operation_log',
  primaryKey: 'id',
  toolbar: { actions: [{ key: 'reload', label: '刷新', action: 'reload' }] },
  form: { collapsed: true, submitOnChange: true, schema: [
    { component: 'Input', fieldName: 'user_name', label: '用户' },
    { component: 'Input', fieldName: 'action_type', label: '操作类型' },
  ] },
  grid: {
    columns: [
      { type: 'checkbox', width: 80 },
      { type: 'seq', width: 60 },
      { field: 'id', title: 'ID', minWidth: 260 },
      { field: 'user_name', title: '用户', width: 100 },
      { field: 'action_type', title: '操作类型', width: 100 },
      { field: 'target', title: '目标', width: 120 },
      { field: 'description', title: '描述', minWidth: 150 },
      { field: 'created_at', title: '时间', width: 160 },
    ],
    pagerConfig: { enabled: true, pageSize: 20 },
    sortConfig: { remote: true, defaultSort: { field: 'created_at', order: 'desc' } },
  },
  api: {
    query: backendApi('DynamicQueryBeta/queryforvben'),
    delete: backendApi('DataBatchDelete/BatchDelete'),
    export: backendApi('DynamicQueryBeta/ExportExcel'),
  },
}

// 本地兜底函数（当后端 VbenSchema/GetSchema 返回 404 时使用）
function getLocalSchema(name: string) {
  switch (name) {
    case 'company':
      return companySchema
    case 'user':
      return companySchema
    case 'car':
      return employeeSchema
    case 'operationLog':
      return operationLogSchema
    default:
      return employeeSchema
  }
}

// 加载 schema（核心函数）
async function loadSchema() {
  if (!entityName.value) {
    schema.value = null
    return
  }

  isLoading.value = true
  schema.value = null   // 关键：切换菜单时先清空，避免旧数据闪现

  try {
    console.log('正在请求 schema，实体名称:', entityName.value)

    const res = await requestClient.get(
      backendApi('VbenSchema/GetSchema'),
      {
        params: {
          entityName: entityName.value,
          menuId: menuId.value
        }
      }
    )

    console.log('请求到的 schema:', res)

    schema.value = res
     currentEntityListId.value = res.entityListId || '';
    //  console.log("schema.entityListId",schema.value.entityListId);

  } catch (err) {
    console.error('请求 schema 失败:', err)
    message.error('获取 schema 失败，使用本地兜底')
    schema.value = getLocalSchema(entityName.value)
  } finally {
    isLoading.value = false
  }
}

// 首次进入页面
onMounted(() => {
  loadSchema()
})

// 路由变化时（多个菜单复用组件的关键）
onBeforeRouteUpdate(() => {
  loadSchema()
})


//弹出框begin

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

    // const saveEntityName = currentSchema.value.saveEntityName;
    // const primaryKey = currentSchema.value.primaryKey || 'id';

         const saveEntityName = schema.value.saveEntityName;
    const primaryKey = schema.value.primaryKey || 'id';


    if (saveEntityName == undefined || saveEntityName == null || saveEntityName == '') {
      message.success(`保存实体：${saveEntityName}`);
      return;
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
        tables: tables
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
async function openFormOnlyModal(type: 'add' | 'edit', gridApi: any) {
  showModal.value = true
  let selectedRows = gridApi.grid.getCheckboxRecords();

  let formValue = type === 'edit' ? selectedRows[0] : {};

  if (type === 'edit' && !selectedRows.length) {
    message.warning('请至少选择一条数据进行编辑')
    return
  }
  console.log('选中数据', selectedRows)
  const layout = await getFormDemoLayoutData(formValue, currentEntityListId.value || '');


   console.log('获取到的布局数据', layout)  
  formOnlyModalApi.setData({
    // layout: formDemoLayout
    layout: layout
  })

  formOnlyModalApi.open()
}
</script>
<template>
  <div class="flex h-full min-h-0 flex-1 flex-col overflow-hidden">
  <QueryTable v-if="schema" :schema="schema" :loading="isLoading">
    <template #toolbar-tools="{ gridApi }">
      <Button type="primary" @click="openFormOnlyModal('add', gridApi)">
        新增
      </Button>
      <Button type="primary" @click="openFormOnlyModal('edit', gridApi)">
        编辑
      </Button>
      <FormOnlyModal class="w-[1000px]" title="所有表单控件示例">
        <div style="padding:20px">
          <component v-for="(item, index) in formLayout" :key="index" :is="componentMap[item.type](item)" />
        </div>
      </FormOnlyModal>
    </template>
  </QueryTable>
  </div>
</template>
