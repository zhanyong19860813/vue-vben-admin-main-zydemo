<script lang="ts" setup>
import { useVbenModal } from '@vben/common-ui';
import { Button, Modal, message } from 'ant-design-vue';
import { useVbenForm } from '#/adapter/form';
import { requestClient } from '#/api/request';
import { useVbenVxeGrid } from '#/adapter/vxe-table';
import { ref, nextTick } from 'vue';

defineOptions({ name: 'FormModelAddButton' });

// ================= 1. 响应式变量 =================
const currentQueryMenuId = ref<string>('');
const menuid = ref<string>('');
const roleid = ref<string>('');
const buttonTemplateList = ref<any[]>([]);

// ================= 2. Form 配置 =================
const [Form, formApi] = useVbenForm({
  handleSubmit: onSubmit,
  schema: [
    {
      component: 'Input',
      componentProps: { placeholder: '请输入' },
      fieldName: 'id',
      label: '菜单ID',
      rules: 'required',
      defaultValue: menuid,
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

// ================= 3. 动态列定义 (保持你的原字段名) =================
const dynamicColumns = ref<any[]>([
  { type: 'checkbox', width: 60 },
  { type: 'seq', width: 60 },
  { field: 'id', title: 'ID', width: 80, editRender: { name: 'input' } },
  { field: 'menu_action_id', title: '按钮ID', width: 80, editRender: { name: 'input' } },
  { field: 'role_id', title: '角色ID', width: 80, editRender: { name: 'input' } },
  { field: 'menu_id', title: '菜单ID', width: 100, editRender: { name: 'input' } },
  { field: 'action_key', title: 'Code', editRender: { name: 'input' } },
  {
    field: 'label',
    title: '名称',
    editRender: {
      name: 'select',
      options: [], // 初始为空
      events: {
        //change({ row, value }) {
        change(...args: any[]) {

          // 1. 尝试标准解构：VXE 通常传递一个包含 row 和 value 的对象作为第一个参数
          // 如果 args[0] 是对象且包含 row，则直接解构
          const { row, value } = (args[0] && typeof args[0] === 'object') ? args[0] : { row: args[0], value: args[1] };

          // 2. 容错处理：如果解构出的 value 为空，直接从 row 中读取最新值
          // 这能兼容所有参数传递异常的情况
          const currentLabel = value || row?.label;

          if (!currentLabel) {
            console.warn('⚠️ 未获取到选中的值');
            return;
          }

          let lable = row.label; // 先更新 label 字段

          const template = buttonTemplateList.value.find((item: any) => item.label === lable);

          if (!template) return;
          Object.assign(row, {
            menu_action_id: template.id,//按钮ID 
            menu_id: template.menu_id,
            role_id: roleid.value,
            action_key: template.action_key,
            action: template.action,
            button_type: template.button_type,
            confirm_text: template.confirm_text,
            status: template.status,
            sort: template.sort,
          });

          //    console.log('🔍 选中模板:', template);
        },
      },
    },
  },
  { field: 'button_type', title: '类型', editRender: { name: 'input' } },
  { field: 'action', title: '方法名', editRender: { name: 'input' } },
  { field: 'confirm_text', title: '确认提示', editRender: { name: 'input' } },
  { field: 'sort', title: '排序', editRender: { name: 'input' } },
  { field: 'status', title: '状态', editRender: { name: 'input' } },
]);

// ================= 4. 加载模板数据函数 =================
async function loadButtonTemplates(menuId: string) {
  if (!menuId) {
    buttonTemplateList.value = [];
    return;
  }
  const res = await requestClient.post<any>(
    'http://localhost:5155/api/DynamicQueryBeta/queryforvben',
    {
      TableName: 'vben_menu_actions',
      Page: 1,
      PageSize: 100,
      SortBy: 'sort',
      SortOrder: 'asc',
      SimpleWhere: { menu_id: menuId },
    },
  );
  buttonTemplateList.value = res.items || [];
  console.log('✅ 按钮模板加载完成，数量:', buttonTemplateList.value.length);

  // ⭐ 关键：更新列配置中的 options
  const labelCol = dynamicColumns.value.find((col: any) => col.field === 'label');
  if (labelCol && labelCol.editRender) {
    labelCol.editRender.options = buttonTemplateList.value.map((item: any) => ({
      label: item.label,
      value: item.label,
    }));

    // ⭐ 关键：强制刷新列，确保编辑时下拉框有数据
    if (gridApi && gridApi.grid) {
      await nextTick();
      await gridApi.grid.refreshColumn();
      console.log('🔄 表格列已刷新');
    }
  }
}

// ================= 5. Grid 配置 =================
const gridnewOptions: VxeGridProps<any> = {
  height: 600,
  width: '100%',
  rowConfig: {
    // ⚠️ 必须与列定义中的主键字段一致 (这里是 menu_action_id)
    keyField: 'menu_action_id',
    isHover: true,
    useKey: true,
  },
  border: true,
  stripe: true,
  columns: dynamicColumns.value,
  editConfig: {
    trigger: 'click',
    mode: 'row',
    enabled: true,
    showStatus: true,
    keepSource: true,
  },
  proxyConfig: {
    enabled: true,
    seq: true,
    sort: true,
    ajax: {
      query: async ({ page, sort, formValues }) => {
        const targetId = currentQueryMenuId.value;
        if (!targetId) return { items: [], total: 0 };

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

        if (res.items && res.items.length > 0) {
          console.log('🔍 返回数据样例:', res.items[0]);
        }

        return {
          items: res.items || [],
          total: res.total || 0,
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

// ================= 6. Modal 配置 =================
const [ModalF, modalApi] = useVbenModal({
  fullscreenButton: false,
  class: 'custom-modal',
  onCancel() {
    modalApi.close();
  },
  onConfirm: async () => {
    await formApi.validateAndSubmitForm();
  },
  onOpenChange: async (isOpen) => {
    if (!isOpen) return;

    const data = modalApi.getData<Record<string, any>>();
    const { mode, values } = data || {};

    if (!values) return;

    formApi.resetForm();

    // 赋值
    menuid.value = values.menudata?.menu_id || crypto.randomUUID();
    roleid.value = values.role_id || crypto.randomUUID();

    console.log('🆔 初始化 ID - Menu:', menuid.value, 'Role:', roleid.value);

    formApi.setValues({
      id: values.menudata?.id,
      meta: values.menudata?.meta,
      path: values.menudata?.url,
      component: values.menudata?.component,
      Name: values.menudata?.entity_name,
    });

    // 1. 先加载模板 (填充 options)
    await loadButtonTemplates(values.menu_id);

    // 2. 再加载表格数据
    currentQueryMenuId.value = values.menu_id;
    await gridApi.reload();

    console.log('🏁 Modal 打开流程结束');
  },
  title: '添加按钮',
});

// ================= 7. 提交逻辑 =================
async function onSubmit(values: Record<string, any>) {
  const $grid = gridApi.grid;
  await $grid.clearEdit();
  await nextTick();

  const insertRecords = $grid.getInsertRecords();
  const updateRecords = $grid.getUpdateRecords();
  const removeRecords = $grid.getRemoveRecords();
  //const allData = $grid.getData();

  console.log('📊 提交统计 - 新增:', insertRecords.length, '更新:', updateRecords.length, '删除:', removeRecords.length);

  let finalUpdates = updateRecords;

  console.log('🔍 待保存数据insertRecords:', insertRecords);
  console.log('🔍 待保存数据updateRecords:', updateRecords);


  const btnSaveData = [...insertRecords, ...updateRecords];
  console.log('🔍 待保存数据btnSaveData:', btnSaveData);



  const savedata = btnSaveData.map((item) => {
    // 直接解构出你需要的字段，rest 包含其他所有字段（包括 _original）
    const { role_id, menu_action_id, menu_id, status } = item;

    // 返回一个只包含这 4 个字段的新对象
    return {
      role_id,
      menu_action_id,
      menu_id,
      status
    };
  });
  //console.log('🔍 待保存数据:', savedata);

  const btnDeleteRows = removeRecords.map((item) => ({ id: item.id || item.id }));

  console.log('🔍 待删除数据:', btnDeleteRows);
  if (btnSaveData.length === 0 && btnDeleteRows.length === 0) {
    message.info('无数据变更');
    return;
  }

  await requestClient.post<any>('http://localhost:5155/api/DataSave/datasave-multi', {
    tables: [
      {
        tableName: 'vben_t_sys_role_menu_actions',
        primaryKey: 'id', // 后端表的主键名
        data: savedata,
        deleteRows: btnDeleteRows,
      },
    ],
  });

  message.success('保存成功');
  modalApi.close();
}

// ================= 8. 新增行 =================
const handleAddRow = async () => {
  if (buttonTemplateList.value.length === 0) {
    message.warning('模板数据加载中，请稍后...');
    return;
  }

  const newRow: any = {
    menu_action_id: crypto.randomUUID(), // 对应 keyField
    role_id: roleid.value,
    menu_id: menuid.value, // ⭐ 修复：使用 .value
    label: '',
    action_key: '',
    button_type: 'default',
    action: '',
    confirm_text: '',
    sort: 1,
    status: 1,
  };

  const { row } = await gridApi.grid.insert(newRow);
  await nextTick();
  await gridApi.grid.setEditRow(row);
  await gridApi.grid.setEditCell(row, 'label'); // 聚焦到下拉框
};

// ================= 9. 删除行 =================
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
