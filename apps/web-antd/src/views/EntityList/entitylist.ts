import type { QueryTableActionContext } from '#/components/QueryTable/types';

const actions: Record<string, (ctx: QueryTableActionContext) => any> = {


  //  async add({ gridApi }) {
  //   const row = gridApi.grid.getCurrentRecord();

  //   return {
  //     type: 'openModal',
  //     component: 'dynamic-modals/company/AddModal',
  //     props: {
  //       title: '新增公司',
  //       mode: 'add',
  //       row
  //     }
  //   };
  // },

  async Add({ gridApi, schema }) {

    const grid = gridApi.grid;
    const selectedRows = grid?.getCheckboxRecords?.() || [];

      console.log('新增用户，选中数据schema', schema);
    //schema.openFormOnlyModal('add', gridApi);
    // return {
    //   type: 'openModal',
    //   component: 'dynamic-modals/EntityList/AddEntityListModal',

    //   props: {
    //     title: '新增实体',
    //     width: 800,  // 自定义宽度
    //     height: '400px',  // 自定义高度
    //     mode: 'add',             // 字符串
    //     typestr: 'test',         // 字符串
    //     testnum: "123",
    //     aabb: "aabb",
    //     demonum: 19,
    //     selectedRows             // 数组
    //   },
    // };
  },

  deleteSelected({ gridApi, schema }) {
    // const rows = gridApi.grid.getCheckboxRecords();
    const grid = gridApi.grid;
    const selectedRows = grid?.getCheckboxRecords?.() || [];
    return {
      type: 'openModal',
      component: 'dynamic-modals/company/AddModal',

      props: {
        title: '删除公司',
        width: 600,  // 自定义宽度
        height: '400px',  // 自定义高度
        mode: 'add',             // 字符串
        typestr: 'test',         // 字符串
        testnum: "123",
        aabb: "删除公司",
        demonum: 18,
        selectedRows             // 数组
      },
    };
    console.log('删除用户', selectedRows);
  },


  resetPwd({ gridApi }) {
    const row = gridApi.grid.getCurrentRecord();
    console.log('重置密码', row);
  },
  reload({ gridApi }) {
    gridApi.reload();
  }
};

export default actions;
