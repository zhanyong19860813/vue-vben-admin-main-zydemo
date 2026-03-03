<script lang="ts" setup>
 import { useVbenModal } from '@vben/common-ui';
import { Button, Modal, message } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { requestClient } from '#/api/request';
import { useVbenVxeGrid } from '#/adapter/vxe-table';

 
import { ref } from 'vue';
import path from 'path';

defineOptions({ name: 'FormModelAddButton' });

// ⭐ 1. 定义一个响应式变量，用于在 gridOptions 和 onOpenChange 之间共享 menu_id
const currentQueryMenuId = ref<string>('');

const menuid =  ref<string>('');//crypto.randomUUID();

  // 这个 menuid 是用来在添加按钮时关联到具体哪个菜单的，初始值可以是空字符串或者一个随机 ID，反正它会在 onOpenChange 时被正确赋值。
const roleid =  ref<string>('');

// ... (Form 定义保持不变) ...
const [Form, formApi] = useVbenForm({
  // ... 你的 form 配置 ...
  handleSubmit: onSubmit,
  schema: [
    // ... schema ...
    {
      component: 'Input',
      componentProps: { placeholder: '请输入' },
      fieldName: 'id',
      label: '菜单ID',
      rules: 'required',
      defaultValue: menuid
    },
    {
      component: 'Input',
      componentProps: { placeholder: '请输入' },
      fieldName: 'Name',
      label: '菜单名',
    },
    {
      component: 'Input',
      componentProps: { placeholder: '请输入' },
      fieldName: 'path',
      label: '路径',
      rules: 'required',
    },
    {
      component: 'Input',
      componentProps: { placeholder: '请输入' },
      fieldName: 'component',
      label: '组件',
      rules: 'required',
    },
    {
      component: 'Input',
      componentProps: { placeholder: '请输入' },
      fieldName: 'meta',
      label: 'meta',
      rules: 'required',
      defaultValue: `{"title": "菜单名称","query": {"menuid": "${menuid}"}}`,
    },
  ],
  showDefaultActions: false,
});


const buttonTemplateList = ref<any[]>([]);
async function loadButtonTemplatesold(menuId: string) {
  if (!menuId) {
    buttonTemplateList.value = [];
    return;
  }

  const res = await requestClient.post<any>(
    'http://localhost:5155/api/DynamicQueryBeta/queryforvben',
    {
      TableName: "vben_menu_actions", // 你的模板表
      Page: 1,
      PageSize: 100,
     SortBy: "sort",
      SortOrder: "asc",
      SimpleWhere: {
        menu_id: menuId
      }
    }
  );
    console.log('按钮数据:', res.items);

  buttonTemplateList.value = res.items || [];
   console.log("gridApi",gridApi);
  // gridApi.setColumns(getDynamicColumns())
}


const getDynamicColumns = () => {
  return [
    { type: 'checkbox', width: 60 },
    { type: 'seq', width: 60 },
    { field: 'id', title: 'ID', width: 80, editRender: { name: 'input' } },
    { field: 'menu_id', title: '菜单 ID', width: 100, editRender: { name: 'input' } },
    { field: 'action_key', title: 'Code', editRender: { name: 'input' } },
    {
      field: 'label',
      title: '名称',
      editRender: {
        name: 'select',
        // ⭐ 关键点：这里不要直接 map，而是每次调用时重新获取最新数据
        // 但 VXE 的 options 通常是在初始化时确定的。
        // 所以我们需要用下面的“刷新列”策略。
        options: buttonTemplateList.value.map(item => ({
          label: item.label,
          value: item.label
        })),
        events: {
          change({ row }) {
            const value = row.label;
            const template = buttonTemplateList.value.find(item => item.label === value);
            if (!template) return;
            Object.assign(row, {
              action_key: template.action_key,
              action: template.action,
              button_type: template.button_type,
              confirm_text: template.confirm_text,
              status: template.status,
              sort: template.sort
            });
          }
        }
      }
    },
    { field: 'button_type', title: '类型', editRender: { name: 'input' } },
    { field: 'action', title: '方法名', editRender: { name: 'input' } },
    { field: 'confirm_text', title: '确认提示', editRender: { name: 'input' } },
    { field: 'sort', title: '排序', editRender: { name: 'input' } },
    { field: 'status', title: '状态', editRender: { name: 'input' } },
  ];
};
 

//role_id,menu_action_id,menu_id,status
 const dynamicColumns = ref<any[]>([
     { type: 'checkbox', width: 60 },
    { type: 'seq', width: 60 },
    { field: 'menu_action_id', title: 'ID', width: 80, editRender: { name: 'input' } },
     { field: 'role_id', title: '角色ID', width: 80, editRender: { name: 'input' } },
    { field: 'menu_id', title: '菜单ID', width: 100,  editRender: { name: 'input' } },
    { field: 'action_key', title: 'Code'  , editRender: { name: 'input' }  },
  // 注意：这里先放一个空 options，或者占位符
  {
    field: 'label',
    title: '名称',
    editRender: {
      name: 'select',
      options: [], // 初始为空
      events: {
        change({ row }) {
           // ... 同上
           const value = row.label;
           const template = buttonTemplateList.value.find(item => item.label === value);
           if (!template) return;
           Object.assign(row, {
             menu_action_id:template.id,
             menu_id: template.menu_id,
             role_id: roleid.value,
             action_key: template.action_key,
             action: template.action,
             button_type: template.button_type,
             confirm_text: template.confirm_text,
             status: template.status,
             sort: template.sort
           });
        }
      }
    }
  },
    { field: 'button_type', title: '类型' , editRender: { name: 'input' } },
    { field: 'action', title: '方法名', editRender: { name: 'input' } },
    { field: 'confirm_text', title: '确认提示', editRender: { name: 'input' } },
    { field: 'sort', title: '排序', editRender: { name: 'input' }},
    { field: 'status', title: '状态' , editRender: { name: 'input' }},
  // ... 其他列
]);

async function loadButtonTemplates(menuId: string) {
   if (!menuId) {
    buttonTemplateList.value = [];
    return;
  }
  const res = await requestClient.post<any>(
    'http://localhost:5155/api/DynamicQueryBeta/queryforvben',
    {
      TableName: "vben_menu_actions", // 你的模板表
      Page: 1,
      PageSize: 100,
     SortBy: "sort",
      SortOrder: "asc",
      SimpleWhere: {
        menu_id: menuId
      }
    }
  );
    console.log('按钮数据:', res.items);

  buttonTemplateList.value = res.items || [];
  // 3. 更新 columns 中的 options
  const labelCol = dynamicColumns.value.find((col: any) => col.field === 'label');
  if (labelCol) {
    labelCol.editRender.options = buttonTemplateList.value.map(item => ({
      label: item.label,
      value: item.label
    }));
    
    // 4. 强制刷新列配置
    // gridApi.grid 是原生 VXE 实例
    await gridApi.grid.refreshColumn(); 
  }
  console.log('按钮模板加载完成，列配置已刷新');
}
const gridnewOptions: VxeGridProps<any> = {
  height: 600,
  width: '100%',
  rowConfig: {
    keyField: 'id',
    isHover: true,
    useKey: true,
  },
  border: true,
  stripe: true,
  // 2. 绑定响应式 columns
  columns: dynamicColumns.value, 
  // 列定义保持不变...
  editConfig: {
    trigger: 'click',
    mode: 'row',
    enabled: true,
    showStatus: true,
    keepSource: true, // 必须开启
    //autoClear: false,
  },

  // ⭐⭐⭐ 核心：配置代理查询 ⭐⭐⭐
  proxyConfig: {
    enabled: true,
    seq: true,
    sort: true,
    ajax: {
      // 这个函数会在 gridApi.reload() 或初始化时自动被 VXE 调用
      query: async ({ page, sort, formValues }) => {
        // 这里读取上面定义的响应式变量 currentQueryMenuId
        const targetId = currentQueryMenuId.value;

        // 如果没有 ID，返回空，防止报错
        if (!targetId) {
          return { items: [], total: 0 };
        }

        console.log('🚀 Proxy 正在查询菜单 ID:', targetId);

        const res = await requestClient.post<any>(
          'http://127.0.0.1:5155/api/DynamicQueryBeta/queryforvben',
          {
            TableName: "vben_v_role_menu_actions",
            Page: page.currentPage,
            PageSize: page.pageSize,
            SortBy: sort?.field || "sort",
            SortOrder: sort?.order || "asc",
            SimpleWhere: {
              menu_id: targetId  // 使用动态传入的 ID
              //role_id: roleid.value
            }
          }
        );

        // ✅ VXE 会自动处理这个返回值，并完美生成 _original 快照！
        return {
          items: res.items || [],
          total: res.total || 0
        };
      },
    },
  },
  pagerConfig: {
    enabled: true,
    pageSize: 100,
    pageSizes: [20, 50, 100],
  },
};

const [Grid, gridApi] = useVbenVxeGrid<any>({
  gridOptions: gridnewOptions,
});

const [ModalF, modalApi] = useVbenModal({
  fullscreenButton: false,
  class: 'custom-modal',
  onCancel() {
    modalApi.close();
  },
  onConfirm: async () => {
    await formApi.validateAndSubmitForm();
  },

  // ⭐ 3. 在 onOpenChange 中只负责“传参”和“触发”，不负责“加载数据”
  onOpenChange: async (isOpen) => {
    if (!isOpen) return;

    const data = modalApi.getData<Record<string, any>>();
    const { mode, values } = data || {};

    formApi.resetForm();
 
      //赋值菜单ID
      menuid.value = values.menudata.menu_id || crypto.randomUUID();

      //赋值角色ID
      roleid.value = values.role_id || crypto.randomUUID();
     console.log('当前菜单ID:', menuid);
    // 重置表格查询参数
    currentQueryMenuId.value = '';
    // console.log(' 参数',values);
        // console.log(' 参数 values.menudata.id',values.menudata.id);
        // console.log(' 参数 values.menudata.meta',values.menudata.meta);
        // console.log(' 参数 values.menudata.path',values.menudata.url);
        // console.log(' 参数 values.menudata.component',values.menudata.component);
        // console.log(' 参数 values.menudata.entity_name',values.menudata.entity_name);
         

         formApi.setValues({
        id: values.menudata.id,
        meta: values.menudata.meta,
        path: values.menudata.url ,
        component: values.menudata.component,
        Name: values.menudata.entity_name,  
      });
       
      //生成菜单下面的按钮数据
       console.log('菜单IDddd:', values.menu_id);

       


       await loadButtonTemplates(values.menu_id);
        
       console.log('按钮模板加载完成');
       await gridApi.reload();
       console.log('网格重新加载完成');

    // if (mode === 'create') {
    //   console.log('当前是新增模式');  

      

    //   if (gridApi && gridApi.grid && gridApi.grid.setColumns) {
    //  await gridApi.grid.setColumns(getDynamicColumns());
    //  console.log('表格列配置已刷新，下拉框现在应该有数据了');
    //   }

    // if (mode === 'create') {
    //   console.log('当前是新增模式');
    //   menuid = crypto.randomUUID();
    //   formApi.setValues({
    //     id: menuid,
    //     meta: `{"title": "菜单名称","query": {"menuid": "${menuid}"}}`
    //   });

    //   // 新增模式下，确保表格是空的（可选，因为没 ID 查出来也是空）
    //   await gridApi.reload();
    //   return;
    // }

    // if (mode === 'edit') {
    //   console.log('当前是编辑模式 ID:', values.id);
    //   menuid = values.id;
    //   formApi.setValues(values);

    //   // ⭐⭐⭐ 关键步骤 ⭐⭐⭐
    //   // 1. 将父组件传来的 ID 赋值给响应式变量
    //   currentQueryMenuId.value = values.id;

    //   // 2. 调用 reload()
    //   // 这会触发 proxyConfig.ajax.query，VXE 内部会正确处理 _original
    //   await gridApi.reload();

    //   console.log('已触发网格重新加载，数据将由 proxyConfig 接管');
    // }
  },
  title: '添加按钮',
});

// ... (onSubmit 函数保持不变，现在 getUpdateRecords 应该能正常工作了) ...
async function onSubmit(values: Record<string, any>) {
  const $grid = gridApi.grid;
    await $grid.clearEdit();
   

  const insertRecords = $grid.getInsertRecords();
  const updateRecords = $grid.getUpdateRecords();
  const removeRecords = $grid.getRemoveRecords();

  // 调试：再次确认 _original 是否存在
  const allData = $grid.getData();
  if (allData.length > 0) {
    // @ts-ignore
    console.log('_original 检查:', !!allData[0]._original);
  }

  console.log('新增:', insertRecords.length, '更新:', updateRecords.length, '删除:', removeRecords.length);

  // 兜底逻辑（以防万一，但现在应该不需要了）
  let finalUpdates = updateRecords;
  if (updateRecords.length === 0 && allData.length > 0) {
    const hasMissing = allData.some((r: any) => !r._original);
    if (hasMissing) {
      const insertIds = new Set(insertRecords.map(r => r.id));
      const removeIds = new Set(removeRecords.map(r => r.id));
      finalUpdates = allData.filter((r: any) => !insertIds.has(r.id) && !removeIds.has(r.id));
      console.log('启用兜底策略');
    }
  }

  const btnSaveData = [...insertRecords, ...finalUpdates];
  const btnDeleteRows = removeRecords.map(item => ({ id: item.id }));

  if (btnSaveData.length === 0 && btnDeleteRows.length === 0) {
    message.info('无数据变更');
    return;
  }

  await requestClient.post<any>(
    'http://localhost:5155/api/DataSave/datasave-multi',
    {
      tables: [
        { tableName: "vben_t_sys_role_menu_actions",
         primaryKey: "id",
          data: btnSaveData, 
          deleteRows: btnDeleteRows 
        },
         
      ]
    }
  );

  message.success('保存成功');
  modalApi.close();
}

// ... (handleAddRow, handleDeleteRows 保持不变) ...
const handleAddRow = async () => {
  console.log("buttonTemplateList.value:", buttonTemplateList.value);
 
  const newRow: any = {
    id: "",
    label: '按钮名称',
    button_type: '按钮类型',
    action: '方法名称',
    menu_id: menuid, // 使用当前的 menuid
    sort: 1,
    confirm_text: '确认要执行吗？',
    action_key: '按钮code',
    status: 1
  };
  const { row } = await gridApi.grid.insert(newRow);
  console.log('gridApi:', gridApi);
    console.log('gridApi.grid:', gridApi.grid);
   // await gridApi.setcolumns(getDynamicColumns());
  await gridApi.grid.setEditRow(row);
  await gridApi.grid.setEditCell(row, 'action_key');
};

const handleDeleteRows = async () => {
  const $grid = gridApi.grid;
  const selectRecords = $grid.getCheckboxRecords();
  if (!selectRecords.length) {
    message.warning('请选择要删除的记录');
    return;
  }
  Modal.confirm({
    title: '确认删除',
    content: `确认删除选中的 ${selectRecords.length} 条数据？`,
    async onOk() {
      await $grid.remove(selectRecords);
      message.success('删除成功');
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
    <Grid table-title="按钮列表">
      <template #toolbar-tools>
        <Button class="mr-2" type="primary" @click="handleAddRow()">新增</Button>
        <Button class="mr-2" type="primary" danger @click="handleDeleteRows()">删除</Button>
      </template>
    </Grid>
  </ModalF>
</template>
