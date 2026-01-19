import type { RouteRecordStringComponent } from '@vben/types';

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
 const data= await requestClient.get('http://localhost:5155/api/Menu/GetMenuFromDb').then((res) => {
   
    console.log('当前 getAllMenusApi res= ', res);
   
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
return  datastr;
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
