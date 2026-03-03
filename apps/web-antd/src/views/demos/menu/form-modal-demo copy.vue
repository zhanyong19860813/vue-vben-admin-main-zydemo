<script lang="ts" setup>
import { useVbenModal } from '@vben/common-ui';

import { Button, Modal, message } from 'ant-design-vue';

import { useVbenForm } from '#/adapter/form';
import { requestClient } from '#/api/request';

import { useVbenVxeGrid } from '#/adapter/vxe-table';
//import { Button, Modal，message } from 'ant-design-vue';

import { ref } from 'vue';
import type { VxeTableInstance } from 'vxe-table';

defineOptions({
  name: 'FormModelDemo',
});

//菜单id 
let menuid = crypto.randomUUID();
const [Form, formApi] = useVbenForm({
  handleSubmit: onSubmit,
  schema: [
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'id',
      label: '菜单ID',
      rules: 'required',
      defaultValue: menuid
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'Name',
      label: '菜单名',
      //rules: 'required',
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'path',
      label: '路径',
      rules: 'required',
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'component',
      label: '组件',
      rules: 'required',
    },
    {
      component: 'Input',
      componentProps: {
        placeholder: '请输入',
      },
      fieldName: 'meta',
      label: 'meta',
      rules: 'required',
      defaultValue: `{"title": "菜单名称","query": {"menuid": "${menuid}"}}`,
    },

    // {
    //   component: 'Select',
    //   componentProps: {
    //     options: [
    //       { label: '选项1', value: '1' },
    //       { label: '选项2', value: '2' },
    //     ],
    //     placeholder: '请输入',
    //   },
    //   fieldName: 'field3',
    //   label: '字段3',

    // },
  ],
  showDefaultActions: false,
});

const [ModalF, modalApi] = useVbenModal({
  fullscreenButton: false,
  class: 'custom-modal', // ⭐ 自定义类名
  // Props: {
  //   width: 1000,          // ⭐ 设置宽度
  //   bodyStyle: {
  //     maxHeight: '75vh',  // ⭐ 控制高度
  //     overflow: 'auto',
  //   },
  // },
  onCancel() {
    modalApi.close();
  },
  onConfirm: async () => {
    await formApi.validateAndSubmitForm();
    // modalApi.close();
  },
  onOpenChange: async (isOpen) => {
  if (!isOpen) return;

  const data = modalApi.getData<Record<string, any>>();
  const { mode, values } = data || {};

   formApi.resetForm();
  // await gridApi.grid.loadData([]);

   console.log('当前模式:', mode);
   console.log('传入的值:', values);

  if (mode === 'create') {
    console.log('当前是新增模式');

    menuid = crypto.randomUUID();

    formApi.setValues({
      id: menuid,
      meta: `{"title": "菜单名称","query": {"menuid": "${menuid}"}}`
    });

    return;
  }

  if (mode === 'edit') {
    console.log('当前是编辑模式 ID:', values.id);

    menuid = values.id;
    formApi.setValues(values);

   // const res = await requestClient.post(...);

          //   // 查询子表
        const res = await requestClient.post<ApiResponse>(
          'http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben',
          {
            TableName: "vben_menu_actions",
            Page: 1,
            PageSize: 100,
            SortBy: "menu_id",
            SortOrder: "asc",
            SimpleWhere: {
              menu_id: values.id
            }
          }
        );
        console.log('查询子表结果:', res.items);
    await gridApi.grid.loadData(JSON.parse(JSON.stringify(res.items || [])));
    //await gridApi.grid.loadData(res.items || []);
  }
},
//   onOpenChange: async (isOpen) => {
//   if (!isOpen) return;

//   const data = modalApi.getData<Record<string, any>>();
//   const values = data?.values;

//   // ① 先全部清空（避免脏数据）
//   formApi.resetForm();
//   gridApi.grid.reloadData([]);

//   // ========================
//   // 新增模式
//   // ========================
//   if (!values?.id) {
//     console.log('当前是新增模式');
//     return;
//   }

//   // ========================
//   // 编辑模式
//   // ========================
//   console.log('当前是编辑模式 ID:', values.id);

//   menuid = values.id;
//   // 主表赋值
//   formApi.setValues(values);

//   // 查询子表
//   const res = await requestClient.post<ApiResponse>(
//     'http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben',
//     {
//       TableName: "vben_menu_actions",
//       Page: 1,
//       PageSize: 100,
//       SortBy: "menu_id",
//       SortOrder: "asc",
//       SimpleWhere: {
//         menu_id: values.id
//       }
//     }
//   );

//   gridApi.grid.reloadData(res.items || []);
// },
  
  title: '新增菜单',
}

);

interface ApiResponse {
  status: number;
  message: string;
}

async function   onSubmit(values: Record<string, any>) {

  console.log('提交的表单值：', values);
 

      const $grid = gridApi.grid;

        await $grid.clearEdit();
  await new Promise(resolve => setTimeout(resolve, 50)); // 等待内部事件

  // 【关键步骤 1】强制清除所有单元格的编辑状态，将临时值同步到行数据中
  // 如果当前有单元格正在编辑，这一步会触发 blur 事件，完成数据绑定
  //await $grid.clearEdit();
  
  // 【关键步骤 2】刷新表格内部的状态标记（确保 isUpdate 等标记被正确计算）
  // 在某些版本中，clearEdit 后可能需要一点时间或显式调用 updateStatus
  //await $grid.updateStatus();
  const allData = $grid.getData();
  if (allData.length > 0) {
    const row = allData[0];
    // @ts-ignore 访问内部属性
    const original = row._original;

    console.log('--- 🔍 深度诊断 ---');
    console.log('当前行数据:', row);
    console.log('内部原始快照 (_original):', original);
    
    if (!original) {
      console.error('❌ 确诊：_original 不存在！VXE 无法比对。');
    } else if (original === row) {
      console.error('❌ 确诊：_original 与当前行是同一引用！这是 getUpdateRecords 为空的根本原因。');
      console.error('   无论你怎么改，VXE 都认为 当前值 === 原始值。');
    } else {
       console.log('✅ _original 正常。如果此时 getUpdateRecords 仍为空，说明数据真的没变（值相等）。');
    }
  }

  // --- 调试用：打印当前表格的所有行数据，确认值是否已更新 ---
  //const allData = $grid.getData();
  console.log('表格当前所有行数据 (确认值已变):', allData);


console.log(
  '第一行是否修改',
  gridApi.grid.isUpdateByRow(gridApi.grid.getData()[0])
);

  const btnInsertdata = gridApi.grid.getInsertRecords();
  const btnUpdatedata = gridApi.grid.getUpdateRecords();
  const btnDeletedata = gridApi.grid.getRemoveRecords();
  const data= gridApi.grid.getData();
 
  const btnSaveData = [
    ...btnInsertdata,
    ...btnUpdatedata,
   // ...data
  ];

  

  
  console.log('新增数据btnInsertdata', btnInsertdata);
  console.log('更新数据btnUpdatedata', btnUpdatedata);
  console.log('删除数据btnDeletedata', btnDeletedata);

  console.log('合并后的数据', btnSaveData);

  console.log('菜单数据', values);
  
  console.log('菜单数据data', data);
  
    const btnDeleteRows = btnDeletedata.map(item => ({
  id: item.id
}));
    const rest = await requestClient.post<ApiResponse>(
    'http://localhost:5155/api/DataSave/datasave-multi',
    {
      tables: [
        {
          tableName: "vben_menus_new",
          primaryKey: "id",
          data: [values],
          deleteRows: []
        },
        {
          tableName: "vben_menu_actions",
          primaryKey: "id",
          data: btnSaveData,
          deleteRows: btnDeleteRows
        }
      ]
    }
  );
  

  // message.loading({
  //   content: '正在提交中...',
  //   duration: 0,
  //   key: 'is-form-submitting',
  // });
  // modalApi.lock();
  // setTimeout(() => {
  //   modalApi.close();
  //   message.success({
  //     content: `提交成功：${JSON.stringify(values)}`,
  //     duration: 2,
  //     key: 'is-form-submitting',
  //   });
  // }, 3000);
}


//开始定义  按钮列表
interface RowType {
  id: string;
  menu_id?: string;
  action_key?: string;
  label?: string;
  button_type?: string;
  confirm_text?: string;
  sort?: number;
  action?: string;
  status?: number;
}

// { field: 'FID', title: 'ID', minWidth: 180 },
//  { field: 'menu_id', title: '菜单id', minWidth: 180 },
// { field: 'action_key', title: '按钮code', editRender: { name: 'input' },minWidth: 200, sortable: true },
// { field: 'label', title: '按钮名称',editRender: { name: 'input' }, minWidth: 120, sortable: true },
// { field: 'button_type', title: '按钮类型', editRender: { name: 'input' },minWidth: 260, sortable: true },
// { field: 'action', title: '方法名称', editRender: { name: 'input' },minWidth: 260, sortable: true }


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

    // const res = await requestClient.post<ApiResponse>(
    //   'http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben',
    //   {
    //     TableName: "t_base_company",
    //     Page: page.currentPage,
    //     PageSize: page.pageSize,
    //     SortBy: sort?.field || "Name",
    //     SortOrder: sort?.order?.toLowerCase() || "asc",
    //     SimpleWhere: formValues
    //   },
    //   {
    //     headers: { 'Content-Type': 'application/json' }
    //   }
    // );

    return { items: [], total: 0 }; // ⚠️ 返回 { items, total }
  } catch (ex) {
    console.error('请求数据出错:', ex);
    throw ex;
  }
}



const gridnewOptions: VxeGridProps<RowType> = {
  height: 600,
  width: '100%',

  rowConfig: {
    keyField: 'id',       // 必须有，修改追踪靠它
    isHover: true,
      
     
    useKey: true          // ⭐ 建议加上这个，强制使用 keyField 追踪
  },

  border: true,
  stripe: true,

  columns: [
    { type: 'checkbox', width: 60 },
    { type: 'seq', width: 60 },

    { field: 'id', title: 'ID', width: 80, editRender: { name: 'input' } },

    { field: 'menu_id', title: '菜单ID', width: 100, editRender: { name: 'input' } },

    {
      field: 'action_key',
      title: 'Code',
      editRender: { name: 'input' }
    },
    {
      field: 'label',
      title: '名称',
      editRender: { name: 'input' }
    },
    {
      field: 'button_type',
      title: '类型',
      editRender: { name: 'input' }
    },
    {
      field: 'action',
      title: '方法名',
      editRender: { name: 'input' }
    },
    {
      field: 'confirm_text',
      title: '确认提示',
      editRender: { name: 'input' }
    },
    {
      field: 'sort',
      title: '排序',
      editRender: { name: 'input' }
    },
    {
      field: 'status',
      title: '状态',
      editRender: { name: 'input' }
    }
  ],

  editConfig: {
    trigger: 'click',
    mode: 'row',
    enabled: true,      // ⭐ 必须加
    showStatus: true,
    keepSource: true,
    
    
    
   // autoClear: false      // ⭐ 尝试设置为 false，防止自动清空导致状态丢失，由我们手动 clearEdit 控制
  }
};
/**
 * 表格配置
 */
const gridOptions: VxeGridProps<RowType> = {
  height: '600',
  width: '100%',
  rowConfig: {
    keyField: 'id'
  },
  columns: [
    { align: 'left', title: '选择', type: 'checkbox', width: 80 },
    { title: '序号', type: 'seq', width: 40 },
    { field: 'id', title: 'ID', visible: true ,editRender: { name: 'input' }, minWidth: 100 },
    { field: 'menu_id', title: '菜单id1', visible: true , editRender: { name: 'input' }, minWidth: 100},
    { field: 'action_key', title: 'code', editRender: { name: 'input' }, minWidth: 100   },
    { field: 'label', title: '名称', editRender: { name: 'input' }, minWidth: 100},
    { field: 'button_type', title: '类型', editRender: { name: 'input' }, minWidth: 100 },
    { field: 'action', title: '方法名', editRender: { name: 'input' }, minWidth: 100 },
    { field: 'confirm_text', title: '确认提示', visible: true ,editRender: { name: 'input' }, minWidth: 100 },
    { field: 'sort', title: '排序', visible: true, editRender: { name: 'input' }, minWidth: 100 },
    { field: 'status', title: '状态', visible: true, editRender: { name: 'input' }, minWidth: 100 }
  ],
  editConfig: {
    mode: 'row',
    trigger: 'click',
     keepSource: true,
      showStatus: true,
  },
  pagerConfig: {
    enabled: true,
    pageSize: 10,
    pageSizes: [10, 20, 50]
  },

  // proxyConfig: {
  //   ajax: {
  //     query: async ({ page, sort }, formValues) => {


  //       // ✅ 保存当前查询条件（用于导出 / 删除 / 统计等）
  //       currentQuery.value = { ...formValues };

  //       // ⚠️ 传入分页 + 排序参数
  //       const res = await getData(page, sort, formValues);
  //       return res;
  //     }
  //   }, sort: true
  // },

  // sortConfig: {
  //   defaultSort: { field: 'Name', order: 'asc' },
  //   remote: true, // ⚠️ 远程排序
  //   refresh: true,
  //   zoom: true,
  // },



  toolbarConfig: {
    custom: true,
    zoom: true
  }
};

/**
 * 创建 Grid
 */
const [Grid, gridApi] = useVbenVxeGrid<RowType>({
  gridOptions:gridnewOptions
});

const handleAddRow = async () => {
  const newRow: RowType = {
    id: crypto.randomUUID(),
    // name: '新公司',
    label: '按钮名称',
    button_type: '按钮类型',
    action: '方法名称',
    menu_id: menuid,
    sort:1,
    confirm_text: '确认要执行吗？',
    action_key: '按钮code',
    status: 1
  };

  // ① 等待插入完成
  const { row } = await gridApi.grid.insert(newRow);

  // ② 设置编辑行
  await gridApi.grid.setEditRow(row);

  // ③ 聚焦到第一个可编辑列
  await gridApi.grid.setEditCell(row, 'action_key');


};

const handleDeleteRows = async () => {
  const $grid = gridApi.grid;

  // ① 获取选中的行
  const selectRecords = $grid.getCheckboxRecords();

  if (!selectRecords.length) {
    message.warning('请选择要删除的记录');
    return;
  }


  Modal.confirm({
    title: '确认删除',
    content: `确认删除选中的 ${selectRecords.length} 条数据？`,
    async onOk() {
      // await axios.post(props.schema.api.delete, [
      //   {
      //     tablename: deleteEntityName,
      //     key: primaryKey,
      //     Keys: rows.map((r: any) => r[primaryKey]),
      //   },
      // ]);
      // ③ 区分：新增行 or 已存在行
      const insertRecords = $grid.getInsertRecords();

      // 新增但未提交的行（直接移除）
      const newRows = selectRecords.filter(row =>
        insertRecords.includes(row)
      );

      // 数据库已有的行（标记删除）
      const dbRows = selectRecords.filter(row =>
        !insertRecords.includes(row)
      );

      // ④ 移除新增行
      if (newRows.length) {
        await $grid.remove(newRows);
      }

      // ⑤ 标记删除数据库行（不会马上消失）
      if (dbRows.length) {
        await $grid.remove(dbRows);
      }

      message.success('删除成功');

      message.success('删除成功');
      //gridApi.reload();
    },
  });

};

</script>
<style lang="less">
.custom-modal {
  width: 1000px !important;
  max-width: 90vw;
  max-height: 80vh;
  margin: auto;
}
</style>
<template>
  <ModalF>
    <Form />
  
      <Grid table-title="">
      <template #toolbar-tools>
        <Button class="mr-2" type="primary" @click="handleAddRow()">
          新增
        </Button>
        <Button class="mr-2" type="primary" danger @click="handleDeleteRows()">
          删除
        </Button>

      </template>
    </Grid>

  </ModalF>

  
</template>
