import type { QueryTableActionContext } from '#/components/QueryTable/types';
import type { TabTableItem } from '#/components/FormTabsTableModal/types';

const actions: Record<string, (ctx: QueryTableActionContext) => any> = {
  /** 新增：弹出表单+页签+表格弹窗，参数由此方法传递 */
  async add({ gridApi }) {
    const grid = gridApi.grid;
    const selectedRows = grid?.getCheckboxRecords?.() || [];

    const formSchema = [
      {
        fieldName: 'name',
        label: '公司名称',
        component: 'Input',
        componentProps: { placeholder: '请输入公司名称' },
      },
      {
        fieldName: 'code',
        label: '公司编码',
        component: 'Input',
        componentProps: { placeholder: '请输入' },
      },
    ];

    const tabs: TabTableItem[] = [
      {
        key: 'detail',
        tab: '明细列表',
        gridOptions: {
          columns: [
            { type: 'seq', width: 60 },
            { field: 'code', title: '编码' },
            { field: 'value', title: '金额' },
          ],
          data: [
            { code: 'A001', value: 100 },
            { code: 'A002', value: 200 },
          ],
          pagerConfig: { enabled: false },
        },
      },
      {
        key: 'log',
        tab: '操作日志',
        gridOptions: {
          columns: [
            { type: 'seq', width: 60 },
            { field: 'time', title: '时间' },
            { field: 'action', title: '操作' },
          ],
          data: [
            { time: '2024-01-01', action: '创建' },
            { time: '2024-01-02', action: '修改' },
          ],
          pagerConfig: { enabled: false },
        },
      },
    ];

    return {
      type: 'openFormTabsTableModal',
      title: '新增公司',
      formSchema,
      tabs,
      width: 900,
    };
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
      testnum:"123",
      aabb:"删除公司",
      demonum:18,
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
