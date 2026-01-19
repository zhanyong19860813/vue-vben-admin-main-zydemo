<script lang="ts" setup>
import type { VxeGridProps, VxeGridListeners } from '#/adapter/vxe-table';
import { useVbenVxeGrid } from '#/adapter/vxe-table';

import { Page } from '@vben/common-ui';
import { Button, message } from 'ant-design-vue';

import { requestClient } from '#/api/request';

// interface RowType {
//   //FID: string;
//   Name: string;
//   // SimpleName: string;
//   // Location: string;
// }


// interface ApiResponse {
//   items: RowType[];
//   total: number;
// }


/**
 * 获取示例表格数据
 */
async function getData(page,sort) {

  try
  {
    console.log('当前页', page.currentPage);
    console.log('每页数量', page.pageSize);

    console.log('排序信息', sort);

     return requestClient.post<ApiResponse>(
    'http://127.0.0.1:5155/api/DynamicQuery/queryforvben',
    {
      TableName: "t_base_company",
      Page: page.currentPage,
      PageSize: page.pageSize,

      SortBy: sort?.field || "Name",               // ⚠️ 使用 sort.field
        SortOrder: sort?.order?.toLowerCase() || "asc" // ⚠️ 转成小写 asc/desc
    
    },
    {
      headers: { 'Content-Type': 'application/json' }
    }
  );
  }catch(ex )
  {
    console.error('请求数据出错:', ex);
    throw ex;


  }
}


interface RowType {
  FID: string;
  Name: string;
  SimpleName?: string;
  Location?: string;
  
}

interface ApiResponse {
  items: RowType[];
  total: number;
}

/**
 * 表格配置
 */
const gridOptions: VxeGridProps<RowType> = {
  height: '600',

  columns: [
    { title: '序号', type: 'seq', width: 60 },
    { field: 'FID', title: 'ID', minWidth: 180 },
    { field: 'Name', title: '公司名', minWidth: 200,sortable:true },
    { field: 'SimpleName', title: '简称', minWidth: 120 ,sortable:true},
    { field: 'Location', title: '地址', minWidth: 260 ,sortable:true} 
  ],

  /**
   * 分页（即使你现在只查 Top=10，也建议保留）
   */
  pagerConfig: {
    enabled: true,
    pageSize: 10,
    pageSizes: [10, 20, 50],
  },

  /**
   * 远程数据代理
   */
  proxyConfig: {
    ajax: {
      query: async ({ page, sort }) => {
            const res = await getData( page, sort );
            return res;
         
      }
    },
  },
  
  sortConfig: {
    defaultSort: { field: 'Name', order: 'desc' },
    remote: true,
  },
  toolbarConfig: {

    custom: true,
    zoom: true,

  }
}

/**
 * 创建 Grid
 */
const [Grid, gridApi] = useVbenVxeGrid<RowType>({
  gridOptions,
});

/**
 * 表格事件
 */
const gridEvents: VxeGridListeners<RowType> = {
  cellClick: ({ row }) => {
    message.info(`点击公司：${row.Name}`);
  },
};

/**
 * 工具栏操作
 */
function reload() {
  gridApi.reload();
}

function query() {
  gridApi.query();
}
</script>

<template>
  <Page title="公司列表" description="演示 vben + vxe-table 远程数据请求">
    <Grid table-title="公司信息" table-title-help="数据来自后台接口" v-on="gridEvents">
      <template #toolbar-tools>
        <Button class="mr-2" type="primary" @click="query">
          刷新当前页
        </Button>
        <Button type="primary" @click="reload">
          刷新并回第一页
        </Button>
      </template>
    </Grid>
  </Page>
</template>
