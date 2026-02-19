import type { ActionContext } from '#/components/QueryTable/types';

const actions: Record<string, (ctx: ActionContext) => any> = {
  add({ gridApi, schema }) {

     const row = gridApi.grid.getCurrentRecord();
    console.log('用户新增');
  },

  deleteSelected({ gridApi, schema }) {
    const rows = gridApi.grid.getCheckboxRecords();
    console.log('删除用户', rows);
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
