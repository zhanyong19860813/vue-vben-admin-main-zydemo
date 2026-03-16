<script setup lang="ts">
import { Button, Modal, message } from 'ant-design-vue';
//  import ModalWrapper from '#/components/ModalWrapper.vue';
import { ref, defineAsyncComponent, h } from 'vue';
import axios from 'axios';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { requestClient } from '#/api/request';
import type { QueryTableSchema } from './types';

import { getCurrentInstance } from 'vue'

const vm = getCurrentInstance();
 
 
import {   createApp } from 'vue';
 
//import { Modal } from 'ant-design-vue';

/**
 * props
 */
const props = defineProps<{
  schema: QueryTableSchema;
}>();

/**
 * 当前查询条件
 */
const currentQuery = ref<Record<string, any>>({});

/**
 * ===============================
 * 1️⃣ 初始化 Grid
 * ===============================
 */
const [Grid, gridApi] = useVbenVxeGrid({
  gridOptions: {
    ...props.schema.grid,
    proxyConfig: {
      ajax: {
        query: async ({ page, sort }, formValues) => {
          const cleanWhere = Object.fromEntries(
            Object.entries(formValues || {}).filter(
              ([_, v]) => v !== undefined && v !== null && v !== ''
            )
          );

          currentQuery.value = cleanWhere;

          return requestClient.post(props.schema.api.query, {
            TableName: props.schema.tableName,
            Page: page.currentPage,
            PageSize: page.pageSize,
            SortBy:
              sort?.field ||
              props.schema.grid.sortConfig?.defaultSort?.field,
            SortOrder:
              sort?.order?.toLowerCase() ||
              props.schema.grid.sortConfig?.defaultSort?.order ||
              'asc',
            SimpleWhere: cleanWhere,
          });
        },
      },
    },
  },
  formOptions: props.schema.form,
});

/**
 * ===============================
 * 2️⃣ 预加载 action 模块（仍然 eager）
 * ===============================
 */
const actionModules = import.meta.glob(
  '/src/views/EntityList/*.ts',
  { eager: true }
);

/**
 * ===============================
 * 3️⃣ 打开弹窗（只在当前组件内部）
 * ===============================
 */
/**
 * ===============================
 * 3️⃣ 打开弹窗（修复版）
 * ===============================
 */
async function openModal(componentPath: string, modalProps?: Record<string, any>) {
  return new Promise((resolve) => {
    const AsyncComp = defineAsyncComponent(() =>
      import(`/src/views/${componentPath}.vue`)
    )

    const modalInstance = Modal.confirm({
      title: modalProps?.title || '',
      icon: null,
      width: 800,
      footer: null,
      content: () => {
        const vnode = h(AsyncComp, {
          ...(modalProps || {}),
          onSuccess: (data: any) => {
            resolve(data || 'success')
            modalInstance.destroy()
          },
          onCancel: () => {
            resolve('cancel')
            modalInstance.destroy()
          }
        })

        // ⭐ 关键
        if (vm) {
          vnode.appContext = vm.appContext
        }

        return vnode
      },
    })
  })
}
// async function openModal(componentPath: string, modalProps?: Record<string, any>) {
//   return new Promise((resolve) => {
//     const AsyncComp = defineAsyncComponent(() =>
//       import(`/src/views/${componentPath}.vue`)
//     )

//     // ⭐ 关键：获取当前实例
//     const vm = getCurrentInstance()

//     const modalInstance = Modal.confirm({
//       title: modalProps?.title || '',
//       icon: null,
//       width: 800,
//       footer: null,
//       content: () => {
//         const vnode = h(AsyncComp, {
//           ...(modalProps || {}),
//           onSuccess: (data: any) => {
//             resolve(data || 'success')
//             modalInstance.destroy()
//           },
//           onCancel: () => {
//             resolve('cancel')
//             modalInstance.destroy()
//           }
//         })

//         // ⭐ 关键一行：继承当前 appContext
//         if (vm) {
//           vnode.appContext = vm.appContext
//         }

//         return vnode
//       },
//     })
//   })
// }
   
//  async function openModal(componentPath: string, modalProps?: Record<string, any>) {
//   return new Promise((resolve) => {
//     const AsyncComp = defineAsyncComponent(() =>
//       import(`/src/views/${componentPath}.vue`)
//     );

//     // 1. 提取可能冲突的事件监听器，防止被覆盖
//     const { onSuccess: userOnSuccess, onCancel: userOnCancel, ...restProps } = modalProps || {};

//     const modalInstance = Modal.confirm({
//       title: modalProps?.title || '',
//       icon: null,
//       width: 800,
//       footer: null,
//       content: () =>
//         h(AsyncComp, {
//           // 2. 显式传递普通 Props (避免展开运算符带来的不确定性)
//           ...restProps, 
          
//           // 3. 显式绑定内部事件
//           onSuccess: (data: any) => {
//             // 优先执行用户传入的 onSuccess (如果有)
//             if (userOnSuccess) userOnSuccess(data);
//             resolve(data || 'success');
//             modalInstance.destroy();
//           },
//           onCancel: () => {
//             // 优先执行用户传入的 onCancel (如果有)
//             if (userOnCancel) userOnCancel();
//             resolve('cancel');
//             modalInstance.destroy();
//           }
//         }),
//     });
//   });
// }
// async function openModal(componentPath: string, modalProps?: Record<string, any>) {
//   return new Promise((resolve) => {
//     const AsyncComp = defineAsyncComponent(() =>
//       import(`/src/views/${componentPath}.vue`)
//     );

//     const modalInstance = Modal.confirm({
//       title: modalProps?.title || '',
//       icon: null,
//       width: 800,
//       footer: null,
//       content: () =>
//         h(AsyncComp, {
//           ...(modalProps || {}), // 展开用户自定义所有参数
//           onSuccess: (data: any) => {
//             resolve(data || 'success');
//             modalInstance.destroy();
//           },
//           onCancel: () => {
//             resolve('cancel');
//             modalInstance.destroy();
//           }
//         }),
//     });
//   });
// }

// 如果需要暴露给外部调用，可以在 defineExpose
//defineExpose({ openModal });
//  async function openModal(componentPath: string, modalProps?: Record<string, any>) {
//   return new Promise((resolve) => {
//     // 🔥 动态加载组件
//     const AsyncComp = defineAsyncComponent(() =>
//       import(`/src/views/${componentPath}.vue`)
//     );

//     const modalInstance = Modal.confirm({
//       title: modalProps?.title || '',
//       icon: null,
//       width: 800,
//       footer: null,
//       content: () => {
//         // 拆分 modalProps
//         const { title, selectedRows, ...rest } = modalProps || {};

//         return h(AsyncComp, {
//           title,                  // 字符串显式绑定
//           selectedRows,           // 数组/对象直接传
//           ...(rest || {}),        // 其他函数或对象 prop 可以展开
//           onSuccess: (data: any) => {
//             resolve(data || 'success');
//             modalInstance.destroy();
//           },
//           onCancel: () => {
//             resolve('cancel');
//             modalInstance.destroy();
//           },
//         });
//       },
//     });
//   });
// }
// async function openModal(componentPath: string, modalProps?: any) {
//   return new Promise((resolve) => {

//     // 🔥 动态加载组件
//     const AsyncComp = defineAsyncComponent(() =>
//       import(`/src/views/${componentPath}.vue`)
//     );

//     const modalInstance = Modal.confirm({
//       title: modalProps?.title || '',
//       icon: null,
//       width: 800,
//       footer: null,
//       content: () =>
//         h(AsyncComp, {
//           ...modalProps,

//           // 子组件 emit success
//           onSuccess: (data: any) => {
//             resolve(data || 'success');
//             modalInstance.destroy();
//           },

//           // 子组件 emit cancel
//           onCancel: () => {
//             resolve('cancel');
//             modalInstance.destroy();
//           }
//         }),
//     });
//   });
// }

/**
 * ===============================
 * 4️⃣ toolbar 分发（核心改造点）
 * ===============================
 */
async function handleToolbarClick(btn: any) {
  const actionName = btn.action;
  if (!actionName) {
    message.warning('按钮未配置 action');
    return;
  }

  const modulePath = props.schema.actionModule;
  const mod: any = actionModules[modulePath];

  if (!mod || !mod.default) {
    message.error(`未找到 action 模块`);
    return;
  }

  const fn = mod.default[actionName];
  if (!fn) {
    message.error(`未找到 action：${actionName}`);
    return;
  }

  // ✅ 只传纯数据，不传实例函数
  const result = await fn({
    gridApi,
    schema: props.schema,
  });

  // ✅ 由当前组件决定行为
  if (result?.type === 'openModal') {
    // 这里我们传递宽度和高度给弹窗
    const res = await openModal(result.component, {
      ...result.props,
      // 传递宽度和高度（可以通过按钮的 props 或者自定义值来传递）
      width: result.props?.width || 800, // 如果按钮没有指定宽度，默认为 800
      style: { height: result.props?.height || '500px' }, // 如果按钮没有指定高度，默认为 500px
      onSuccess: (data: any) => {
        console.log('新增成功数据', data);
        gridApi.reload(); // 刷新列表
        console.log('测试刷新列表', data);
      },
    });
  }
}
 

/**
 * ===============================
 * 5️⃣ 删除
 * ===============================
 */
async function handleDelete() {
  const grid = gridApi.grid;
  if (!grid) return;

  const rows = grid.getCheckboxRecords();
  if (!rows.length) {
    message.warning('请选择要删除的数据');
    return;
  }

  const primaryKey = props.schema.primaryKey || 'FID';
  const deleteEntityName =
    props.schema.deleteEntityName || props.schema.tableName;

  Modal.confirm({
    title: '确认删除',
    content: `确认删除选中的 ${rows.length} 条数据？`,
    async onOk() {
      await axios.post(props.schema.api.delete, [
        {
          tablename: deleteEntityName,
          key: primaryKey,
          Keys: rows.map((r: any) => r[primaryKey]),
        },
      ]);

      message.success('删除成功');
      gridApi.reload();
    },
  });
}

/**
 * ===============================
 * 6️⃣ 导出
 * ===============================
 */
async function handleExport() {
  const sort = gridApi.grid?.getSortColumns?.()?.[0];

  const queryField = props.schema.grid.columns
    ?.filter((c: any) => c.field)
    .map((c: any) => (c.title ? `${c.field} as ${c.title}` : c.field))
    .join(',');

  const res = await axios.post(
    props.schema.api.export,
    {
      TableName: props.schema.tableName,
      SimpleWhere: currentQuery.value,
      SortBy: sort?.field || 'Name',
      SortOrder: sort?.order?.toLowerCase() || 'asc',
      QueryField: queryField,
    },
    { responseType: 'blob' }
  );

  const blob = new Blob([res.data]);
  const url = window.URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${props.schema.title}.xlsx`;
  a.click();
  window.URL.revokeObjectURL(url);
}

/**
 * 暴露 gridApi
 */
defineExpose({ gridApi });
</script>

<template>
  <Grid :table-title="schema.title">
    <template #toolbar-tools>
      <div class="query-table-toolbar">
        <div class="toolbar-left">
          <Button
            v-for="btn in schema.toolbar?.actions || []"
            :key="btn.key"
            class="mr-2"
            :type="btn.type || 'default'"
            @click="handleToolbarClick(btn)"
          >
            {{ btn.label }}
          </Button>
        </div>

        <div class="toolbar-center">
          <Button
            v-if="schema.api.delete"
            danger
            class="mr-2"
            @click="handleDelete"
          >
            删除
          </Button>

          <Button
            v-if="schema.api.export"
            class="mr-2"
            @click="handleExport"
          >
            导出
          </Button>

          <Button type="primary" @click="gridApi.reload()">
            刷新
          </Button>
        </div>

        <div class="toolbar-right">
          <slot name="toolbar-tools" :gridApi="gridApi" />
        </div>
      </div>
    </template>
  </Grid>
</template>
<style scoped>

.query-table-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: nowrap; /* 不换行 */
  width: 100%;
}

.toolbar-left,
.toolbar-center,
.toolbar-right {
  display: flex;
  align-items: center;
}

.toolbar-left {
  gap: 8px;
}

.toolbar-center {
  gap: 8px;
}

.toolbar-right {
  gap: 8px;
}
 </style>
