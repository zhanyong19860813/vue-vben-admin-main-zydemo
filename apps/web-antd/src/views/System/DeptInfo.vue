<script lang="ts" setup>
import type { VxeGridProps } from '#/adapter/vxe-table';

import { Page } from '@vben/common-ui';

import { Button } from 'ant-design-vue';

import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { requestClient } from '#/api/request';
import { reactive, ref ,onMounted } from 'vue';

import axios from 'axios';

//import { MOCK_TREE_TABLE_DATA } from './table-data';

interface RowType {
  
  id: string;
  name: string;
  parentId: null | number;
   
}

//默认展开第一层
 

 
onMounted(async () => {

  try {
  
  
        const res = await requestClient.post(
      'http://localhost:5155/api/DynamicQueryBeta/queryforvben',
      {
  "tableName": "t_base_department",
  "page": 1,
  "pageSize":1000,
  "sortBy": "path",
  "sortOrder": "asc",
  "queryField": "id  ,parent_id as parentId,name"
   }
      
    );
 
          console.log("部门数据res:",res.items);
     deptDatas.value=res.items;
        console.log("gridApi",gridApi);
     gridApi.reload(deptDatas.value);
  } catch (error) {
    console.error("请求 数据时出错:", error);
  } 

});

const gridOptions: VxeGridProps<RowType> = {
  columns: [
    // { type: 'seq', width: 70 },
    //  { field: 'id', minWidth: 300, title: 'ID', treeNode: true },
    { field: 'name', minWidth: 300, title: '名字', treeNode: true },
    // { field: 'size', title: 'Size' },
    // { field: 'type', title: 'Type' },
    // { field: 'date', title: 'Date' },
  ],

  proxyConfig: {
    ajax: {
      query: async ({ page, sort }) => {


                const res = await requestClient.post(
            'http://localhost:5155/api/DynamicQueryBeta/queryforvben',
            {
        "tableName": "t_base_department",
        "page": 1,
        "pageSize":1000,
        "sortBy": "path",
        "sortOrder": "asc",
        "queryField": "id  ,parent_id as parentId,name"
          }
            
          );
            return {
              items: res.items,
              total: res.total,
            };
        
         
      },
    },
  },
  pagerConfig: {
    enabled: false,
  },
  treeConfig: {
    parentField: 'parentId',
    rowField: 'id',
    transform: true,
  },
};

const [Grid, gridApi] = useVbenVxeGrid({ gridOptions });

const expandAll = () => {
  gridApi.grid?.setAllTreeExpand(true);
};

const collapseAll = () => {
  gridApi.grid?.setAllTreeExpand(false);
};
</script>

<template>
  <Page>
    <Grid table-title="数据列表" table-title-help="提示">
      <template #toolbar-tools>
        <Button class="mr-2" type="primary" @click="expandAll">
          展开全部
        </Button>
        <Button type="primary" @click="collapseAll"> 折叠全部 </Button>
      </template>
    </Grid>
  </Page>
</template>
