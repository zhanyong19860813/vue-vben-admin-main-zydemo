import type { RouteRecordStringComponent } from '@vben/types';

import { backendApi } from '#/api/constants';
import { requestClient } from '#/api/request';

import { useAuthStore } from '#/store/auth';


/**
 * 获取用户所有菜单
 */
export async function getAllMenusApi() {

  // 拿到当前登录用户信息
  const authStore = useAuthStore();
  const userInfo = await authStore.fetchUserInfo(); // 确保有最新信息
  console.log('当前登录用户 userInfo= ', userInfo);

  console.log('当前 getAllMenusApi  ');
  //请求后台  返回数据
  const data = await requestClient.get(backendApi('Menu/GetMenuFromDb')).then((res) => {

    console.log('当前 getAllMenusApi res= ', res);

    const datamenu=  [
  {
    "name": "Sys",
    "path": "/Sys",
    "meta": {
      "title": "系统设置",
      "icon": "mdi:appstore",
      "affixTab": null
    },
    "children": [
      {
        "name": "TestEntity1",
        "path": "/EntityList/index1",
        "component": "/EntityList/index",
        "meta": {
             "title": "测试实体1",
          "icon": "mdi:appstore",
          "affixTab": null,
          "query": {
            "entityname": "TestEntity1"
          } 
        },
        "children": []
      },
      {
        "name": "TestEntity2",
        "path": "/EntityList/index",
        "component": "/EntityList/index",
        "meta": {
             "title": "测试实体2",
          "icon": "mdi:appstore",
          "affixTab": null,
          "query": {
            "entityname": "TestEntity2"
          } 
        },
        "children": []
      },
      {
        "name": "UserRoleMapping",
        "path": "/UserRoleMapping",
        "component": "System/UserRoleMapping/UserRoleMapping",
        "meta": {
          "title": "角色",
          "icon": "mdi:appstore",
          "affixTab": null
        },
        "children": []
      },
      {
        "name": "AddMenu",
        "path": "/AddMenu",
        "component": "demos/menu/index",
        "meta": {
          "title": "添加菜单",
          "icon": "mdi:appstore",
          "affixTab": null
        },
        "children": []
      },
      {
        "name": "TestQueryTable",
        "path": "/Test/TestQueryTable",
        "component": "/company/index",
        "meta": {
          "title": "测试QueryTable",
          "icon": "mdi:appstore",
          "affixTab": null
        },
        "children": []
      },
      {
        "name": "TestAddMenu",
        "path": "demos/MenuAdd",
        "component": "demos/MenuAdd",
        "meta": {
          "title": "测试addmenu",
          "icon": "mdi:appstore",
          "affixTab": null
        },
        "children": []
      },
      {
        "name": "AddMenuNew",
        "path": "/AddMenuNew",
        "component": "demos/menu/menu",
        "meta": {
          "title": "新菜单列表",
          "icon": "mdi:appstore",
          "affixTab": null
        },
        "children": []
      },
      {
        "name": "tabledemo",
        "path": "/TableDemo",
        "component": "System/Tabledemo",
        "meta": {
          "title": "多页签案例",
          "icon": "mdi:appstore",
          "affixTab": null
        },
        "children": []
      },
      {
        "name": "UserRoleMappingTest",
        "path": "/UserRoleMappingTest",
        "component": "System/UserRoleMappingTest",
        "meta": {
          "title": "测试角色表格",
          "icon": "mdi:appstore",
          "affixTab": null
        },
        "children": []
      },
      {
        "name": "DeptInfo",
        "path": "/DeptInfo",
        "component": "System/DeptInfo",
        "meta": {
          "title": "部门管理",
          "icon": "mdi:appstore",
          "affixTab": null
        },
        "children": []
      },
      {
        "name": "RoleManage",
        "path": "System/RoleManage",
        "component": "System/RoleManage/index",
        "meta": {
          "title": "角色管理",
          "icon": "mdi:appstore",
          "affixTab": null
        },
        "children": []
      }
    ]
  },
  {
    "name": "Dashboard",
    "path": "/",
    "meta": {
      "title": "page.dashboard.title",
      "icon": "mdi:appstore",
      "affixTab": null
    },
    "children": [
      {
        "name": "SimpleTable",
        "path": "/simple-table",
        "component": "demos/simple-table/index",
        "meta": {
          "title": "简单表格",
          "icon": null,
          "affixTab": null
        },
        "children": []
      },
      {
        "name": "UrlTable",
        "path": "/url-table",
        "component": "demos/simple-table/urltable",
        "meta": {
          "title": "表格后台数据后台",
          "icon": null,
          "affixTab": null
        },
        "children": []
      }
    ]
  }
] ;
     return res;
  });

  const jsonStr = JSON.stringify(data, null, 2);
  console.log('当前 getAllMenusApi data= ', data);
  console.log('当前 getAllMenusApi data= ', jsonStr);
  return data;




  const datastr = [
    {
      meta: {
        order: -1,
        title: 'page.dashboard.title',
      },
      name: 'Dashboard',
      path: '/',
      redirect: '/analytics',
      children: [
        {
          name: 'Analytics',
          path: '/analytics',
          // 这里为页面的路径，需要去掉 views/ 和 .vue
          component: '/dashboard/analytics/index',
          meta: {
            affixTab: true,
            title: 'test',
          },
        },
        {
          name: "simple-table",
          path: "SimpleTable",
          component: "demos/simple-table/index",
          meta: {
            affixTab: true,
            title: "简单表格"
          }
        },
        {
          name: "UrlTable",
          path: "url-table",
          component: "demos/simple-table/urltable",
          meta: {
            title: "表格后台数据",
            affixTab: true,

          }
        }

        //  {
        //   path: "simple-table",
        //   name: "SimpleTable",
        //   component: "demos/simple-table/index",
        //   meta: {
        //     title: "简单表格"
        //   }
        // },
        //       {
        //               path: "url-table",
        //               name: "UrlTable",
        //               component: "demos/simple-table/urltable",
        //               meta: {
        //                  affixTab: true,
        //                   title: "表格后台数据"
        //               }
        //           }
      ]
    }
  ];
  return datastr;
  const dashboardMenus = [
    {
      meta: {
        order: -1,
        title: 'page.dashboard.title',
      },
      name: 'Dashboard',
      path: '/',
      redirect: '/analytics',
      children: [
        {
          name: 'Analytics',
          path: '/analytics',
          // 这里为页面的路径，需要去掉 views/ 和 .vue
          component: '/dashboard/analytics/index',
          meta: {
            affixTab: true,
            title: 'test',
          },
        },
        {
          name: 'Workspace',
          path: '/workspace',
          component: '/dashboard/workspace/index',
          meta: {
            title: 'tetttttt',
          },
        },
        {
          path: "simple-table",
          name: "SimpleTable",
          component: "demos/simple-table/index",
          meta: {
            title: "简单表格"
          }
        },
        {
          path: "url-table",
          name: "UrlTable",
          component: "demos/simple-table/urltable",
          meta: {
            affixTab: true,
            title: "表格后台数据"
          }
        }
      ],
    }

  ];
  //   return dashboardMenus;
}
