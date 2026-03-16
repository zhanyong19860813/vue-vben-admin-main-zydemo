<script lang="ts" setup>
import type { VxeGridProps, VxeGridListeners } from '#/adapter/vxe-table';
import { useVbenVxeGrid } from '#/adapter/vxe-table';

import { Page } from '@vben/common-ui';
import { Button, message } from 'ant-design-vue';
import type { VbenFormProps } from '#/adapter/form';
import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

import FormModalDemo from './form-modal-demo.vue';
import { ref } from 'vue';

import axios from 'axios';

import {
  alert,
  clearAllAlerts,
  confirm,

  prompt,
  useVbenModal,
} from '@vben/common-ui';

const currentQuery = ref<Record<string, any>>({});
const formOptions: VbenFormProps = {
  // 默认展开
  collapsed: false,
  fieldMappingTime: [['date', ['start', 'end']]],
  schema: [
    {
      component: 'Input',
      defaultValue: '',
      fieldName: 'Name',
      label: '公司名',
    },
    {
      component: 'Input',
      defaultValue: '',
      fieldName: 'Location',
      label: '地址',
    }
  ],
  // 控制表单是否显示折叠按钮
  showCollapseButton: true,
  // 是否在字段值改变时提交表单
  submitOnChange: true,
  // 按下回车时是否提交表单
  submitOnEnter: false,
};

interface RowType {
  id: string;
  name: string;
  path?: string;
  component?: string;
  meta?: string;
  parent_id?: string | null;
  status?: number;
  type?: string;
  sort?: number;
}

interface ApiResponse {
  items: RowType[];
  total: number;
}

/**
 * 获取表格数据（支持分页 + 排序）
 */
async function getData(page, sort, formValues) {
  try {
    console.log('当前页', page.currentPage);
    console.log('每页数量', page.pageSize);
    console.log('排序信息', sort);
    console.log('表单值', formValues);



    const res = await requestClient.post<ApiResponse>(
      backendApi('DynamicQueryBeta/queryforvben'),
      {
        TableName: "vben_menus_new",
        Page: page.currentPage,
        PageSize: page.pageSize,
        SortBy: sort?.field || "sort",
        SortOrder: sort?.order?.toLowerCase() || "asc",
        SimpleWhere: formValues
      },
      {
        headers: { 'Content-Type': 'application/json' }
      }
    );

    return res; // ⚠️ 返回 { items, total }
  } catch (ex) {
    console.error('请求数据出错:', ex);
    throw ex;
  }
}

/**
 * 表格配置
 */
const gridOptions: VxeGridProps<RowType> = {
  height: 1150,

  columns: [
    { align: 'left', title: '选择', type: 'checkbox', width: 80 },
    { title: '序号', type: 'seq', width: 60 },
    { field: 'id', title: 'ID', minWidth: 200 },
    // 树形节点列：只在「菜单名称」这一列做缩进，其他列正常显示
    { field: 'name', title: '菜单名称', minWidth: 220, sortable: true, treeNode: true },
    { field: 'path', title: '路径', minWidth: 160, sortable: true },
    { field: 'component', title: '组件', minWidth: 260, sortable: true },
    { field: 'meta', title: 'meta', minWidth: 260, sortable: true },
    { field: 'parent_id', title: 'parent_id', minWidth: 200, sortable: true },
    { field: 'status', title: '状态', minWidth: 100, sortable: true },
    { field: 'type', title: '类型', minWidth: 100, sortable: true },
    { field: 'sort', title: '排序', minWidth: 80, sortable: true },
  ],


  // 树形配置：扁平数据转树（参考 DeptInfo.vue）
  treeConfig: {
    rowField: 'id',
    parentField: 'parent_id',
    transform: true,
    expandAll: true,
    line: true,
  },

  pagerConfig: {
    enabled: false,
  },

  proxyConfig: {
    ajax: {
      query: async ({ page, sort }, formValues) => {
        currentQuery.value = { ...formValues };
        // 树形需一次拉全量，用大 pageSize
        const res = await getData({ currentPage: 1, pageSize: 2000 }, sort, formValues);
        return res;
      }
    },
    sort: true,
  },

  sortConfig: {
    defaultSort: { field: 'Name', order: 'asc' },
    remote: true, // ⚠️ 远程排序
    refresh: true,
    zoom: true,
  },



  toolbarConfig: {
    custom: true,
    zoom: true
  }
};

/**
 * 创建 Grid
 */
const [Grid, gridApi] = useVbenVxeGrid<RowType>({
  gridOptions,
  formOptions
});

/**
 * 表格事件
 */
const gridEvents: VxeGridListeners<RowType> = {
  cellClick: ({ row }) => {
    message.info(`点击公司：${row.Name}`);
  }
};

/**
 * 工具栏操作
 */
function reload() {
  gridApi.reload();
}

function expandAll() {
  gridApi.grid?.setAllTreeExpand(true);
}

function collapseAll() {
  gridApi.grid?.setAllTreeExpand(false);
}

function query() {
  gridApi.query();
}

function handleSortChange({ sortList }) {
  // VxeTable 的 sortList 是数组 [{ column, property, order }]
  const sort = sortList[0]; // 取第一个排序字段
  if (sort) {
    console.log('排序字段:', sort.property, '顺序:', sort.order);
    // 触发重新加载（会传入新的 sort 给 proxyConfig）
    gridApi.reload();
  }
}

const [FormModal, formModalApi] = useVbenModal({
  connectedComponent: FormModalDemo,
});

// 打开表单弹窗
function openFormModal() {

  // 传递初始表单值  判断新增还是编辑
  const isEdit = false; // 假设是新增
  //formModalApi
  // .setData({
  //   // 表单值
  //   values: { field1: 'abc', field2: '123' },
  // })
  // .open();

  formModalApi
    .setData({
      mode: 'create',
      values: {},
    })
    .open();
}
// 打开表单弹窗 - 编辑
function openFormModalUpdate() {

  // // 传递初始表单值  判断新增还是编辑
  // const isEdit = true; // 假设是编辑
  // //note: 这里可以根据选中行的数据来设置表单初始值
  //  const grid = gridApi.grid;
  //   const selectedRows = grid?.getCheckboxRecords();
  //   if (!selectedRows?.length) {
  //     message.warning('请先选择一行进行编辑');
  //     return;
  //   }
  //   const rowData = selectedRows[0]; // 取第一行数据进行编辑

  // formModalApi
  //   .setData({
  //     // 表单值
  //     values: rowData,
  //   })
  //   .open();

  const grid = gridApi.grid;
  const selectedRows = grid?.getCheckboxRecords();

  if (!selectedRows?.length) {
    message.warning('请先选择一行进行编辑');
    return;
  }

  const rowData = selectedRows[0];

  formModalApi
    .setData({
      mode: 'edit',
      values: rowData,
    })
    .open();
}


const handleDelete = async () => {
  try {

    const grid = gridApi.grid;
    if (!grid) {
      message.error('表格实例未初始化');
      return;
    }
    const rows = grid.getCheckboxRecords(); // ✅ vxe-table 原生方法

    if (!rows.length) {
      message.warning('请先选择要删除的数据');
      return;
    }


    const res = await requestClient.post<ApiResponse>(
      backendApi('DataBatchDelete/BatchDelete'),
      [
        {
          tablename: "t_base_company",
          key: "FID",
          Keys: rows.map(r => r.FID)
        }
      ],
      {
        headers: { 'Content-Type': 'application/json' }
      });

    console.log("成功删除 ", res);
    message.success(`成功删除 ${res.deletedCount} 条数据`);
    gridApi.reload();
  } catch (error) {
    console.error('删除数据出错:', error);
    message.error('删除数据出错');
  }

};


// const handleExport = async () => {
//   // 1️⃣ 当前查询条件
//   const where = await gridApi.formApi?.getValues();
//   console.log('导出当前查询条件：', where);

//   // 2️⃣ 使用 download（不会进错误拦截）
//   await requestClient.download(
//     'http://localhost:5155/api/DynamicQuery/ExportExcel',
//     {
//       tableName: 't_base_company',
//       columns: ['FID', 'Name', 'SimpleName', 'Location'],
//       where:currentQuery.value,
//       sortBy: 'Name',
//       sortOrder: 'asc',
//     },
//     {
//       fileName: '公司信息.xlsx', // ⭐ 直接指定文件名
//       method: 'POST',
//       headers: { 'Content-Type': 'application/json' }
//     }
//   );

//   message.success('导出成功');
// };
const handleExport = async () => {
  try {
    // ① 拿当前查询条件
    console.log("导出当前查询条件：", currentQuery.value);

    // ② axios POST 下载 Excel
    const res = await axios.post(
      backendApi('DynamicQueryBeta/ExportExcel'),
      {
        TableName: 't_base_company',
        columns: ['FID', 'Name', 'SimpleName', 'Location'],
        QueryField: "FID as ID,Name as 姓名,SimpleName as 简称,Location as 地址",
        SimpleWhere: currentQuery.value, // 当前查询条件
        SortBy: 'Name',
        SortOrder: 'asc',


        // TableName: "t_base_company",
        // Page: page.currentPage,
        // PageSize: page.pageSize,
        // SortBy: sort?.field || "Name",
        // SortOrder: sort?.order?.toLowerCase() || "asc",
        // SimpleWhere: formValues

      },
      {
        responseType: 'blob', // ⚠️ 必须设置
        headers: {
          'Content-Type': 'application/json', // ⚠️ 必须设置
        },
      }
    );

    // ③ 创建 Blob 并下载
    const blob = new Blob([res.data], {
      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = '公司信息.xlsx'; // 文件名
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);

    message.success('导出成功');
  } catch (error: any) {
    console.error('导出数据出错:', error);

    // 处理后台返回的 Blob 错误信息
    let msg = error?.response?.data;
    if (msg instanceof Blob) {
      const text = await msg.text();
      msg = text;
    }

    message.error('导出数据出错：' + (msg || error.message));
  }
};


</script>

<template>
  <Page>
    <Grid table-title="菜单信息" table-title-help="数据来自后台接口" v-on="gridEvents" @sort-change="handleSortChange">
      <template #toolbar-tools>
        <Button class="mr-2" type="primary" @click="expandAll">展开全部</Button>
        <Button class="mr-2" type="primary" @click="collapseAll">折叠全部</Button>
        <Button class="mr-2" type="primary" @click="openFormModal">
          新增
        </Button>
        <Button class="mr-2" type="primary" @click="openFormModalUpdate">
          修改
        </Button>
        <Button class="mr-2" type="primary" danger @click="handleDelete">
          删除
        </Button>
        <Button class="mr-2" type="primary" @click="handleExport">
          导出EXCEL
        </Button>

        <Button class="mr-2" type="primary" @click="query">
          刷新当前页
        </Button>
        <Button type="primary" @click="reload">
          刷新并回第一页
        </Button>
      </template>
    </Grid>
    <!-- <Card class="w-[300px]" title="表单弹窗示例">
      <p>弹窗与表单结合</p>
      <template #actions>
        <Button type="primary" @click="openFormModal"> 打开表单弹窗 </Button>
      </template>
    </Card> -->
    <FormModal />
  </Page>
</template>
