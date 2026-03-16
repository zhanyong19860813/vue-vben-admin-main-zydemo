<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, onBeforeRouteUpdate } from 'vue-router'
import QueryTable from '#/components/QueryTable/index.vue'
import { companySchema } from './company.schema'
import { employeeSchema } from './employee.schema'
import { requestClient } from '#/api/request'
import { message } from 'ant-design-vue'

// 路由
const route = useRoute()

// 响应式状态
const schema = ref<any>(null)
const isLoading = ref(false)

// 计算 entityName / menuId
const entityName = computed(() => route.meta.query?.entityname as string)
const menuId = computed(() => route.meta.query?.menuid as string)

// 本地兜底函数
function getLocalSchema(name: string) {
  switch (name) {
    case 'company':
      return companySchema
    case 'user':
      return companySchema
    case 'car':
      return employeeSchema
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
      'http://localhost:5155/api/VbenSchema/GetSchema',
      {
        params: {
          entityName: entityName.value,
          menuId: menuId.value
        }
      }
    )

    console.log('请求到的 schema:', res)

    schema.value = res

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
</script>
<template>
   
  <QueryTable
    v-if="schema"
    :schema="schema"
    :loading="isLoading"
   ></QueryTable>
</template>
