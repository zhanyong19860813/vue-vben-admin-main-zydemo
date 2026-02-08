<script lang="ts" setup>
import { reactive, ref ,onMounted } from 'vue';

import { ColPage } from '@vben/common-ui';
import { IconifyIcon } from '@vben/icons';

import { requestClient } from '#/api/request';
//import { BasicTree } from '#/components/Tree';


import type { VxeGridListeners, VxeGridProps } from '#/adapter/vxe-table';
import { useVbenVxeGrid } from '#/adapter/vxe-table';


import { Tree as ATree } from 'ant-design-vue';
import { Button, message } from 'ant-design-vue';
import {
  Alert,
 Tabs,
  Card,
  Checkbox,
  Slider,
  Tag,
  Tooltip,
} from 'ant-design-vue';

const props = reactive({
  leftCollapsedWidth: 5,
  leftCollapsible: true,
  leftMaxWidth: 50,
  leftMinWidth: 20,
  leftWidth: 30,
  resizable: true,
  rightWidth: 70,
  splitHandle: true,
  splitLine: true,
});


// 树形数据和展开节点
const roleTreeDatas = ref<any[]>([]);
//默认展开第一层
const expandedKeys = ref<string[]>([]);
onMounted(async () => {

  try {

    const res = await requestClient.get('http://localhost:5155/api/QueryTreeData/tree');
     roleTreeDatas.value = res;

    // 默认展开第一层
    expandedKeys.value = res.map(n => n.key);

    roleTreeDatas.value=res;
  } catch (error) {
    console.error("请求树形数据时出错:", error);
  }

});

 const handleExpand = (keys: string[]) => {
  expandedKeys.value = keys; // 手动更新 expandedKeys
};

  interface RowType {
  user_name: string;
  user_code: number;
  employee_id: number;

  }
const currentRoleId = ref<string>()
const gridOptions: VxeGridProps<RowType> = {
  columns: [
    { title: '序号', type: 'seq', width: 50 },
    { field: 'user_name', title: '用户名' },
    { field: 'user_code', sortable: true, title: '工号' },
    { field: 'employee_id', sortable: true, title: '员工ID' }
  ],
  //data: tabeldata,
  pagerConfig: {
    enabled: false,
  },
  proxyConfig: {
    ajax: {
      query: async ({ page, sort }) => {

        if(currentRoleId.value==undefined){
        return {records:[],total:0}
        }
          console.log("当前角色ID:",currentRoleId.value);

        const res = await requestClient.get(
        'http://localhost:5155/api/DynamicQueryBeta/query',
        {
            params: 
            {
              //  tableName: 'vben_user_role',
                tableName: 'v_vben_t_sys_user_role',
                sortBy: 'user_code',
                sortOrder: 'DESC',
                page: 1,
                pageSize: 20,
                simpleWhere: 
                {
                role_id: currentRoleId.value
                }
            }
        }
        );

        console.log("用户角色数据res:",res);
        return res;
        },
    },
  },
  sortConfig: {
    multiple: true,
  },
};
const gridEvents: VxeGridListeners<RowType> = {
  cellClick: ({ row }) => {
    message.info(`cell-click: ${row.name}`);
  },
};
const [Grid, gridApi] = useVbenVxeGrid<RowType>({

  gridEvents,
  gridOptions,
});

//----------------------开始定义第二个表格菜单--------------------------------------------------------
interface MenuRowType {
  entity_name: string;
  url: string;
  bar_items: string;
}

const gridMenuOptions: VxeGridProps<MenuRowType> = {
   columns: [
     { title: '序号', type: 'seq', width: 50 },
    { field: 'entity_name', title: '菜单名' },
    { field: 'url',   title: '路径' },
    { field: 'bar_items',   title: '按钮' }
  ],
  //data: tabeldata,
  data: [],
  pagerConfig: {
    enabled: false,
  },
  proxyConfig: {
    ajax: {
      query: async ({ page, sort }) => {

        if(currentRoleId.value==undefined){
          return {records:[],total:0}
        }
           console.log("当前角色ID:",currentRoleId.value);
        

        
        const res = await requestClient.get(
        'http://localhost:5155/api/DynamicQueryBeta/query',
        {
            params: 
            {
                tableName: 'vben_role_menu',
                sortBy: 'entity_name',
                sortOrder: 'DESC',
                page: 1,
                pageSize: 20,
                simpleWhere: 
                {
                role_id: currentRoleId.value
                }
            }
        }
        );





        console.log("gridMenuOptions菜单权限数据res:",res);
         return res;
              
        //  return {
        //   items: res.items || res, // 适配你的接口返回结构
        //   total: res.total || (res.data ? res.data.length : 0),
        // };

      },
    },
  },
  sortConfig: {
    multiple: true,
  },
};


const gridMenuEvents: VxeGridListeners<MenuRowType> = {
  cellClick: ({ row }) => {
    console.log("gridMenuEvents row:",row);
    //message.info(`cell-click: ${row.name}`);
  },
};
 
const [MenuGrid, gridMenuApi] = useVbenVxeGrid<MenuRowType>({
gridEvents:gridMenuEvents,
gridOptions:gridMenuOptions,
});
/// 选择节点 事件 触发 表格刷新
const handleSelect = async (selectedKeys: string[], info: any) => {

  // 获取选中的节点的 key 值  当前角色ID
 currentRoleId.value =selectedKeys[0];

 // 刷新表格数据
  gridApi.query();

   // 刷新表格数据
  gridMenuApi.query();

};
const showBorder = gridApi.useStore((state) => state.gridOptions?.border);
// const showBorder = gridApi.useStore((state) => state.gridOptions?.border);


function changeBorder() {
  gridApi.setGridOptions({
    border: !showBorder.value,
  });
}

function changeStripe() {
  gridApi.setGridOptions({
    stripe: !showStripe.value,
  });
}

function changeLoading() {
  gridApi.setLoading(true);
  setTimeout(() => {
    gridApi.setLoading(false);
  }, 2000);
}


const activeKey = ref('user');
//const activeKey2 = ref('role');


</script>
<template>

<ColPage
    auto-content-height
    description="ColPage 是一个双列布局组件，支持左侧折叠、拖拽调整宽度等功能。"
    v-bind="props"
    title="ColPage 双列布局组件"
  >

    <template #left="{ isCollapsed, expand }">
      <div v-if="isCollapsed" @click="expand">
        <Tooltip title="点击展开左侧">
          <Button
            shape="circle"
            type="primary"
            class="flex items-center justify-center"
          >
            <template #icon>
              <IconifyIcon class="text-2xl" icon="bi:arrow-right" />
            </template>
          </Button>
        </Tooltip>
      </div>
      <div
        v-else
        :style="{ minWidth: '250px' }"
        class="mr-2 rounded-[var(--radius)] border border-border bg-card p-2"
      >
  <!-- <div>  左边左边</div> -->

  <div :style="{ minWidth: '250px', height: '600px' }" class="mr-2 rounded-[var(--radius)] border border-border bg-card p-2">

 <ATree
            :tree-data="roleTreeDatas"
            default-expand-all
               @expand="handleExpand"
            :expanded-keys="expandedKeys"
            @select="handleSelect"
          />
  </div>


      </div>
    </template>


 
    <Card class="ml-1" title="用户信息">
        <Tabs v-model:activeKey="activeKey"   :destroyInactiveTabPane="false">
      <!-- Tab 1 -->
      <Tabs.TabPane key="user" tab="用户列表">
        <div class="p-2">
           
        
          <div class="flex flex-col gap-2">
          <Grid  table-title-help="提示"></Grid>
          </div>
        </div>
      </Tabs.TabPane>
      <!-- Tab 2 -->
      <Tabs.TabPane key="role" tab="菜单权限">
        <div class="p-2">
           <div class="flex flex-col gap-2">

             <MenuGrid  table-title-help="提示"></MenuGrid>  
           </div>

        </div>
      </Tabs.TabPane>
    </Tabs>

    </Card>

  </ColPage>




</template>
